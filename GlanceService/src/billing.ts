import { TaxCategory, WaffoPancake, type PriceSnapshot, type WebhookEventData } from "@waffo/pancake-ts";
import type { Env } from "./index";
import { readSmallJSON, requireAppUser } from "./app-auth";

type Sku = "pro_lifetime" | "updates_year" | "credits_100" | "credits_300" | "credits_1000";
type Product = { sku: Sku; price: string; credits: number; label: string; productId: string };
const at = () => new Date().toISOString();
const response = (result: unknown, status = 200) => new Response(JSON.stringify({ success: true, result }),
  { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
const fail = (code: string, message: string, status: number) => new Response(JSON.stringify({ success: false, error: { code, message } }),
  { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
const cents = (amount: string) => {
  if (!/^\d+(?:\.\d{1,2})?$/.test(amount)) return NaN;
  const [whole, fraction = ""] = amount.split(".");
  return Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
};

function products(env: Env): Product[] {
  return [
    { sku: "pro_lifetime", price: env.PRO_LIFETIME_CNY || "99.00", credits: 100, label: "Glance Pro", productId: env.WAFFO_PRODUCT_PRO || "" },
    { sku: "updates_year", price: "59.00", credits: 0, label: "One year of feature updates", productId: env.WAFFO_PRODUCT_UPDATES_YEAR || "" },
    { sku: "credits_100", price: "10.00", credits: 100, label: "100 credits", productId: env.WAFFO_PRODUCT_CREDITS_100 || "" },
    { sku: "credits_300", price: "30.00", credits: 300, label: "300 credits", productId: env.WAFFO_PRODUCT_CREDITS_300 || "" },
    { sku: "credits_1000", price: "100.00", credits: 1000, label: "1000 credits", productId: env.WAFFO_PRODUCT_CREDITS_1000 || "" }
  ];
}

function pancake(env: Env) {
  if (!env.WAFFO_MERCHANT_ID || !env.WAFFO_PRIVATE_KEY || !env.WAFFO_ENVIRONMENT) return null;
  return new WaffoPancake({ merchantId: env.WAFFO_MERCHANT_ID, privateKey: env.WAFFO_PRIVATE_KEY,
    environment: env.WAFFO_ENVIRONMENT === "test" ? "test" : "prod",
    webhookPublicKey: env.WAFFO_WEBHOOK_PUBLIC_KEY });
}

export async function catalog(env: Env, request: Request) {
  await requireAppUser(env, request);
  return response({ currency: "CNY", products: products(env).map(({ sku, price, credits, label }) => ({ sku, price, credits, label })) });
}

export async function wallet(env: Env, request: Request) {
  const user = await requireAppUser(env, request);
  const balance = await env.DB.prepare("SELECT balance FROM wallets WHERE user_id=?")
    .bind(user.id).first<{ balance: number }>();
  const entitlement = await env.DB.prepare("SELECT pro_lifetime,updates_until FROM app_entitlements WHERE user_id=?")
    .bind(user.id).first<{ pro_lifetime: number; updates_until: string | null }>();
  const trialUntil = new Date(Date.parse(user.created_at) + 14 * 86_400_000).toISOString();
  return response({ balance: balance?.balance || 0, proLifetime: !!entitlement?.pro_lifetime,
    updatesUntil: entitlement?.updates_until || null, trialUntil, trialActive: !entitlement?.pro_lifetime && Date.now() < Date.parse(trialUntil) });
}

export async function createCheckout(env: Env, request: Request) {
  const user = await requireAppUser(env, request);
  const body = await readSmallJSON(request);
  if (!body) return fail("invalid_json", "A JSON object is required.", 400);
  const product = products(env).find((item) => item.sku === body.sku);
  if (!product) return fail("invalid_sku", "Unknown product.", 400);
  if (!product.productId) return fail("product_not_configured", "This product is not configured for checkout.", 503);
  if (!Number.isSafeInteger(cents(product.price)) || cents(product.price) <= 0) {
    return fail("invalid_price_config", "This product's price is not configured correctly.", 503);
  }
  const client = pancake(env);
  if (!client) return fail("payment_not_configured", "Payment is not configured.", 503);
  if (product.sku === "pro_lifetime" || product.sku === "updates_year") {
    const entitlement = await env.DB.prepare("SELECT pro_lifetime FROM app_entitlements WHERE user_id=?")
      .bind(user.id).first<{ pro_lifetime: number }>();
    if (product.sku === "pro_lifetime" && entitlement?.pro_lifetime) return fail("already_pro", "Pro is already active.", 409);
    if (product.sku === "updates_year" && !entitlement?.pro_lifetime) return fail("pro_required", "Buy Pro before renewing updates.", 409);
  }
  const orderID = `order_${crypto.randomUUID()}`;
  await env.DB.prepare(`INSERT INTO billing_orders(id,user_id,sku,product_id,currency,amount,granted_credits,created_at)
    VALUES(?,?,?,?,?,?,?,?)`).bind(orderID, user.id, product.sku, product.productId, "CNY", product.price, product.credits, at()).run();
  try {
    const checkout = await client.checkout.authenticated.create({
      productId: product.productId, currency: "CNY", buyerIdentity: String(user.id), buyerEmail: user.email,
      // The current API documents taxIncluded; SDK 0.26 forwards it even though its type omits the field.
      orderMerchantExternalId: orderID, priceSnapshot: { amount: product.price, taxIncluded: true,
        taxCategory: product.sku.startsWith("credits_") ? TaxCategory.DigitalGoods : TaxCategory.Software
      } as PriceSnapshot & { taxIncluded: boolean },
      language: "zh-Hans", successUrl: `${env.PUBLIC_ORIGIN}/payment/return?order=${encodeURIComponent(orderID)}`,
      metadata: { sku: product.sku }
    }, { idempotencyKey: orderID });
    await env.DB.prepare("UPDATE billing_orders SET checkout_session_id=?,checkout_expires_at=? WHERE id=?")
      .bind(checkout.sessionId, checkout.expiresAt, orderID).run();
    // The URL contains a buyer JWT fragment. Return it only to the authenticated caller; never persist or log it.
    return response({ orderId: orderID, checkoutUrl: checkout.checkoutUrl, expiresAt: checkout.expiresAt }, 201);
  } catch {
    return fail("checkout_unavailable", "Could not start checkout. Please try again.", 502);
  }
}

export async function orderStatus(env: Env, request: Request, orderID: string) {
  const user = await requireAppUser(env, request);
  const order = await env.DB.prepare(`SELECT id,sku,currency,amount,granted_credits,status,created_at,completed_at,refunded_at
    FROM billing_orders WHERE id=? AND user_id=?`).bind(orderID, user.id).first();
  return order ? response(order) : fail("order_not_found", "Order not found.", 404);
}

export async function webhook(env: Env, request: Request) {
  if (!env.WAFFO_WEBHOOK_PUBLIC_KEY || !env.WAFFO_ENVIRONMENT || !env.WAFFO_STORE_ID) return fail("webhook_not_configured", "Webhook is not configured.", 503);
  const client = pancake(env);
  if (!client) return fail("payment_not_configured", "Payment is not configured.", 503);
  if (Number(request.headers.get("Content-Length") || 0) > 128_000) return fail("payload_too_large", "Webhook payload is too large.", 413);
  const raw = await request.text();
  if (raw.length > 128_000) return fail("payload_too_large", "Webhook payload is too large.", 413);
  let event;
  try { event = client.webhooks.verify<WebhookEventData>(raw, request.headers.get("x-waffo-signature"),
    { environment: env.WAFFO_ENVIRONMENT === "test" ? "test" : "prod" }); }
  catch { return fail("invalid_signature", "Invalid webhook signature.", 401); }
  if (event.mode !== env.WAFFO_ENVIRONMENT || event.storeId !== env.WAFFO_STORE_ID) {
    return fail("wrong_store", "Webhook store or environment does not match.", 400);
  }
  if (event.eventType !== "order.completed" && event.eventType !== "refund.succeeded") return response({ received: true });
  const orderID = event.data.orderMerchantExternalId;
  if (!orderID) return fail("missing_order", "Order identifier is missing.", 400);
  const order = await env.DB.prepare(`SELECT id,user_id,currency,amount,status,provider_order_id,paid_cents,refunded_cents
    FROM billing_orders WHERE id=?`).bind(orderID).first<{ id: string; user_id: number; currency: string; amount: string;
      status: string; provider_order_id: string | null; paid_cents: number | null; refunded_cents: number }>();
  if (!order || order.currency !== event.data.currency ||
      (event.data.merchantProvidedBuyerIdentity && event.data.merchantProvidedBuyerIdentity !== String(order.user_id)) ||
      (order.provider_order_id && order.provider_order_id !== event.data.orderId)) {
    return fail("order_mismatch", "Webhook order does not match checkout.", 409);
  }
  const already = await env.DB.prepare("SELECT id FROM billing_webhook_events WHERE id=?").bind(event.id).first();
  if (already) return response({ received: true, duplicate: true });
  if (event.eventType === "order.completed") {
    const listed = event.data.listPrice?.total;
    if (listed && cents(listed) !== cents(order.amount)) return fail("amount_mismatch", "Order amount does not match checkout.", 409);
    const paid = cents(event.data.chargedAmount || event.data.amount);
    if (!Number.isSafeInteger(paid) || paid < 0) return fail("invalid_amount", "Payment amount is invalid.", 400);
    if (order.status === "pending" || order.status === "expired") {
      await env.DB.batch([
        env.DB.prepare(`UPDATE billing_orders SET status='completed',provider_order_id=?,paid_cents=?,completed_at=?
          WHERE id=? AND status IN ('pending','expired') AND NOT EXISTS(SELECT 1 FROM billing_webhook_events WHERE id=?)`)
          .bind(event.data.orderId, paid, at(), orderID, event.id),
        env.DB.prepare("INSERT OR IGNORE INTO billing_webhook_events(id,event_type,order_id,created_at) VALUES(?,?,?,?)")
          .bind(event.id, event.eventType, orderID, at())
      ]);
    } else {
      await env.DB.prepare("INSERT OR IGNORE INTO billing_webhook_events(id,event_type,order_id,created_at) VALUES(?,?,?,?)")
        .bind(event.id, event.eventType, orderID, at()).run();
    }
  } else {
    if (order.status === "pending" || order.status === "expired" || !order.paid_cents) {
      return fail("order_not_completed", "Order payment is not completed.", 409);
    }
    const refunded = cents(event.data.refundedAmount || event.data.amount);
    if (!Number.isSafeInteger(refunded) || refunded <= 0) return fail("invalid_amount", "Refund amount is invalid.", 400);
    await env.DB.batch([
      env.DB.prepare(`UPDATE billing_orders SET refunded_cents=refunded_cents+?,
        status=CASE WHEN refunded_cents+?>=paid_cents THEN 'refunded' ELSE status END,
        refunded_at=CASE WHEN refunded_cents+?>=paid_cents THEN ? ELSE refunded_at END
        WHERE id=? AND status='completed' AND NOT EXISTS(SELECT 1 FROM billing_webhook_events WHERE id=?)`)
        .bind(refunded, refunded, refunded, at(), orderID, event.id),
      env.DB.prepare("INSERT OR IGNORE INTO billing_webhook_events(id,event_type,order_id,created_at) VALUES(?,?,?,?)")
        .bind(event.id, event.eventType, orderID, at())
    ]);
  }
  return response({ received: true });
}
