import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { api, createTask, seedWidget, USER_TOKEN } from "./helpers";
import { webhook } from "../src/billing";
import type { Env } from "../src/index";
import { expireStaleTasks } from "../src/index";

const keys = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
  publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
function pem(bytes: ArrayBuffer, kind: string) {
  const base64 = btoa(String.fromCharCode(...new Uint8Array(bytes)));
  return `-----BEGIN ${kind}-----\n${base64.match(/.{1,64}/g)?.join("\n")}\n-----END ${kind}-----`;
}
const privatePEM = pem(await crypto.subtle.exportKey("pkcs8", keys.privateKey), "PRIVATE KEY");
const publicPEM = pem(await crypto.subtle.exportKey("spki", keys.publicKey), "PUBLIC KEY");
const billingEnv = { ...env, WAFFO_MERCHANT_ID: "MER_2D5F8G3H1K4M6N9P0Q7R8S",
  WAFFO_STORE_ID: "STO_test", WAFFO_PRIVATE_KEY: privatePEM,
  WAFFO_WEBHOOK_PUBLIC_KEY: publicPEM, WAFFO_ENVIRONMENT: "test" } as Env;

async function signedWebhook(event: Record<string, unknown>) {
  const body = JSON.stringify(event);
  const time = String(Date.now());
  const signatureBytes = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", keys.privateKey,
    new TextEncoder().encode(`${time}.${body}`));
  const signature = btoa(String.fromCharCode(...new Uint8Array(signatureBytes)));
  return new Request("https://example.com/api/v2/billing/webhook", { method: "POST", body,
    headers: { "Content-Type": "application/json", "x-waffo-signature": `t=${time},v1=${signature}` } });
}

async function balance() {
  const row = await env.DB.prepare("SELECT balance FROM wallets WHERE user_id=1").first<{ balance: number }>();
  return row?.balance;
}

describe("billing ledger", () => {
  it("requires a real app session for wallet and checkout", async () => {
    expect((await api("/api/v2/billing/wallet")).status).toBe(401);
    expect((await api("/api/v2/billing/wallet", { token: "arbitrary-token" })).status).toBe(401);
    const wallet = await api("/api/v2/billing/wallet", { token: USER_TOKEN });
    expect(wallet.status).toBe(200);
    expect(await wallet.json()).toMatchObject({ result: { balance: 10000, proLifetime: false } });
    expect((await api("/api/v2/tasks", { method: "POST", token: env.FLOW_TEST_TOKEN,
      json: { widgetID: "any", commandID: "run" } })).status).toBe(403);
  });

  it("grants a Pro purchase once and reverses it on a full refund", async () => {
    const order = `order_${crypto.randomUUID()}`;
    const at = new Date().toISOString();
    await env.DB.prepare(`INSERT INTO billing_orders(id,user_id,sku,product_id,currency,amount,granted_credits,created_at)
      VALUES(?,?,?,?,?,?,?,?)`).bind(order, 1, "pro_lifetime", "PROD_test", "CNY", "99.00", 100, at).run();
    await env.DB.prepare("UPDATE billing_orders SET status='completed',provider_order_id=?,paid_cents=9900,completed_at=? WHERE id=?")
      .bind("ORD_test", at, order).run();
    expect(await balance()).toBe(10100);
    expect((await env.DB.prepare("SELECT pro_lifetime FROM app_entitlements WHERE user_id=1")
      .first<{ pro_lifetime: number }>())?.pro_lifetime).toBe(1);
    await env.DB.prepare("UPDATE billing_orders SET status='completed' WHERE id=?").bind(order).run();
    expect(await balance()).toBe(10100);
    await env.DB.prepare("UPDATE billing_orders SET status='refunded',refunded_at=? WHERE id=?")
      .bind(at, order).run();
    expect(await balance()).toBe(10000);
    expect((await env.DB.prepare("SELECT pro_lifetime FROM app_entitlements WHERE user_id=1")
      .first<{ pro_lifetime: number }>())?.pro_lifetime).toBe(0);
    const ledger = await env.DB.prepare("SELECT delta FROM wallet_ledger WHERE user_id=1 AND source_key IN (?,?)")
      .bind(`purchase:${order}`, `refund:${order}`).all<{ delta: number }>();
    expect(ledger.results.map((entry) => entry.delta).sort((a, b) => a - b)).toEqual([-100, 100]);
  });

  it("recalculates feature-update access when a renewal is refunded", async () => {
    const pro = `order_${crypto.randomUUID()}`;
    const renewal = `order_${crypto.randomUUID()}`;
    const paidAt = "2026-01-01T00:00:00.000Z";
    for (const [id, sku, amount] of [[pro, "pro_lifetime", "99.00"], [renewal, "updates_year", "59.00"]]) {
      await env.DB.prepare(`INSERT INTO billing_orders(id,user_id,sku,product_id,currency,amount,created_at)
        VALUES(?,?,?,?,?,?,?)`).bind(id, 1, sku, "PROD_test", "CNY", amount, paidAt).run();
    }
    await env.DB.prepare("UPDATE billing_orders SET status='completed',completed_at=? WHERE id=?").bind(paidAt, pro).run();
    const first = await env.DB.prepare("SELECT updates_until FROM app_entitlements WHERE user_id=1")
      .first<{ updates_until: string }>();
    expect(first?.updates_until).toBe("2027-01-01");
    await env.DB.prepare("UPDATE billing_orders SET status='completed',completed_at=? WHERE id=?").bind(paidAt, renewal).run();
    const extended = await env.DB.prepare("SELECT updates_until FROM app_entitlements WHERE user_id=1")
      .first<{ updates_until: string }>();
    expect(extended?.updates_until).toBe("2028-01-01");
    await env.DB.prepare("UPDATE billing_orders SET status='refunded',refunded_at=? WHERE id=?")
      .bind(paidAt, renewal).run();
    const restored = await env.DB.prepare("SELECT updates_until FROM app_entitlements WHERE user_id=1")
      .first<{ updates_until: string }>();
    expect(restored?.updates_until).toBe("2027-01-01");
  });

  it("charges a task atomically and refunds queued cancellation or worker failure", async () => {
    await seedWidget();
    const first = await createTask();
    expect(first.response.status).toBe(202);
    expect(first.body?.creditCost).toBe(8);
    expect(await balance()).toBe(9992);
    expect((await api(`/api/v2/tasks/${first.taskID}`, { method: "DELETE", token: USER_TOKEN })).status).toBe(200);
    expect(await balance()).toBe(10000);

    const second = await createTask();
    expect(await balance()).toBe(9992);
    await env.DB.prepare("UPDATE widget_tasks SET status='running' WHERE id=?").bind(second.taskID).run();
    await env.DB.prepare("UPDATE widget_tasks SET status='failed',completed_at=? WHERE id=?")
      .bind(new Date().toISOString(), second.taskID).run();
    expect(await balance()).toBe(10000);

    const third = await createTask();
    await env.DB.prepare("UPDATE widget_tasks SET status='running' WHERE id=?").bind(third.taskID).run();
    await api(`/api/v2/tasks/${third.taskID}`, { method: "DELETE", token: USER_TOKEN });
    expect(await balance()).toBe(9992);
  });

  it("rejects a task without enough credits", async () => {
    await seedWidget();
    await env.DB.prepare("UPDATE wallets SET balance=7 WHERE user_id=1").run();
    const task = await api("/api/v2/tasks", { method: "POST", token: USER_TOKEN,
      json: { widgetID: "11111111-1111-4111-8111-111111111111", commandID: "run" } });
    expect(task.status).toBe(402);
    expect(await task.json()).toMatchObject({ error: { code: "insufficient_credits" } });
    expect(await balance()).toBe(7);
  });

  it("refunds a task that times out without a result", async () => {
    await seedWidget();
    const task = await createTask();
    expect(await balance()).toBe(9992);
    await env.DB.prepare("UPDATE widget_tasks SET created_at=? WHERE id=?")
      .bind(new Date(Date.now() - 2 * 60 * 60_000).toISOString(), task.taskID).run();
    await expireStaleTasks(env);
    await expireStaleTasks(env);
    expect(await balance()).toBe(10000);
    const row = await env.DB.prepare("SELECT status,error_code FROM widget_tasks WHERE id=?")
      .bind(task.taskID).first<{ status: string; error_code: string }>();
    expect(row).toMatchObject({ status: "failed", error_code: "timeout" });
  });

  it("accepts only signed same-store events and deduplicates payment/refund delivery", async () => {
    const orderID = `order_${crypto.randomUUID()}`;
    const providerOrderID = `ORD_${crypto.randomUUID()}`;
    const at = new Date().toISOString();
    await env.DB.prepare(`INSERT INTO billing_orders(id,user_id,sku,product_id,currency,amount,granted_credits,created_at)
      VALUES(?,?,?,?,?,?,?,?)`).bind(orderID, 1, "credits_100", "PROD_test", "CNY", "10.00", 100, at).run();
    const base = { timestamp: at, eventId: "PAY_test", storeId: "STO_test", storeName: "Test", mode: "test",
      data: { orderId: providerOrderID, orderMerchantExternalId: orderID, merchantProvidedBuyerIdentity: "1",
        currency: "CNY", buyerEmail: "test@example.com", amount: "10.00", chargedAmount: "10.00",
        listPrice: { total: "10.00", taxAmount: "0.00" }, productName: "100 credits" } };
    const completed = { ...base, id: crypto.randomUUID(), eventType: "order.completed" };
    const otherStore = { ...completed, storeId: "STO_other" };
    expect((await webhook(billingEnv, await signedWebhook(otherStore))).status).toBe(400);
    expect(await balance()).toBe(10000);
    const unsigned = new Request("https://example.com/api/v2/billing/webhook", { method: "POST", body: JSON.stringify(completed) });
    expect((await webhook(billingEnv, unsigned)).status).toBe(401);
    await env.DB.prepare("UPDATE billing_orders SET checkout_expires_at=? WHERE id=?")
      .bind(new Date(Date.now() - 60_000).toISOString(), orderID).run();
    await expireStaleTasks(env);
    expect((await env.DB.prepare("SELECT status FROM billing_orders WHERE id=?")
      .bind(orderID).first<{ status: string }>())?.status).toBe("expired");
    expect((await webhook(billingEnv, await signedWebhook(completed))).status).toBe(200);
    expect((await webhook(billingEnv, await signedWebhook(completed))).status).toBe(200);
    expect(await balance()).toBe(10100);

    const partial = { ...base, id: crypto.randomUUID(), eventType: "refund.succeeded",
      data: { ...base.data, refundedAmount: "4.00" } };
    expect((await webhook(billingEnv, await signedWebhook(partial))).status).toBe(200);
    expect(await balance()).toBe(10100);
    const rest = { ...partial, id: crypto.randomUUID(), data: { ...base.data, refundedAmount: "6.00" } };
    expect((await webhook(billingEnv, await signedWebhook(rest))).status).toBe(200);
    expect((await webhook(billingEnv, await signedWebhook(rest))).status).toBe(200);
    expect(await balance()).toBe(10000);
  });
});
