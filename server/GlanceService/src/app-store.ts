import type { Env } from './index';
import { authenticatedUser } from './users';
import { orderPublic, readOrder } from './billing';
import { BillingError, billingBody, billingReply, isoNow, readPricing, sha256, CURRENCIES, type Currency } from './pricing';

/**
 * Mac App Store in-app purchases.
 *
 * The client sends only a transaction ID. The transaction itself is always
 * fetched from Apple's App Store Server API over TLS, so its contents are
 * trusted without verifying the JWS certificate chain locally. A verified
 * purchase becomes an ordinary paid order (payment_method 'app_store'); the
 * existing order triggers grant credits, Pro and the Pro bonus, and revoke
 * them on refund. `provider_order_id` is unique, so replays never grant twice.
 *
 * Product IDs follow `<bundle id>.credits.<pack id>` and `<bundle id>.pro.<tier id>`.
 */

type AppleEnvironment = 'Production' | 'Sandbox';
export type AppleTransaction = {
  transactionId: string; originalTransactionId?: string; bundleId: string; productId: string;
  purchaseDate?: number; type?: string; appAccountToken?: string; environment?: AppleEnvironment;
  price?: number; currency?: string; revocationDate?: number; revocationReason?: number;
};

const API_HOSTS: Record<AppleEnvironment, string> = {
  Production: 'https://api.storekit.itunes.apple.com',
  Sandbox: 'https://api.storekit-sandbox.itunes.apple.com',
};

const bundleID = (env: Env) => env.APP_STORE_BUNDLE_ID || 'com.glance.app';

function base64url(bytes: Uint8Array | string) {
  const raw = typeof bytes === 'string' ? bytes : String.fromCharCode(...bytes);
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Decodes a JWS payload without verifying it. Only use on data received from Apple's API. */
export function jwsPayload<T>(jws: string): T {
  const part = jws.split('.')[1];
  if (!part) throw new Error('Malformed JWS');
  const padded = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(padded), c => c.charCodeAt(0)))) as T;
}

/** The UUID the client passes to StoreKit as `appAccountToken`; ties a purchase to this Glance account. */
export async function appStoreAccountToken(env: Env, userID: number) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.SESSION_SECRET),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const bytes = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode('app-store-account:' + userID))).slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

async function apiToken(env: Env) {
  if (!env.APP_STORE_ISSUER_ID || !env.APP_STORE_KEY_ID || !env.APP_STORE_PRIVATE_KEY)
    throw new BillingError('app_store_unavailable', 'App Store purchases are not configured yet. Your purchase is kept and Glance will retry.', 503);
  const pem = env.APP_STORE_PRIVATE_KEY.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: env.APP_STORE_KEY_ID, typ: 'JWT' }));
  const claims = base64url(JSON.stringify({ iss: env.APP_STORE_ISSUER_ID, iat: now, exp: now + 600,
    aud: 'appstoreconnect-v1', bid: bundleID(env) }));
  const signature = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key,
    new TextEncoder().encode(`${header}.${claims}`)));
  return `${header}.${claims}.${base64url(signature)}`;
}

/**
 * Fetches a transaction from Apple. Production is tried first; App Review and
 * TestFlight purchases live in the sandbox. Returns null when Apple has no
 * such transaction in either environment.
 */
export async function fetchTransaction(env: Env, transactionID: string, only?: AppleEnvironment): Promise<AppleTransaction | null> {
  const token = await apiToken(env);
  for (const environment of only ? [only] : (['Production', 'Sandbox'] as const)) {
    let response: Response;
    try {
      response = await fetch(`${API_HOSTS[environment]}/inApps/v1/transactions/${transactionID}`, {
        headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000) });
    } catch {
      throw new BillingError('app_store_unavailable', 'Could not reach the App Store. Your purchase is kept and Glance will retry.', 503);
    }
    if (response.status === 404) continue;
    if (!response.ok) throw new BillingError('app_store_unavailable', 'The App Store could not confirm this purchase right now. Your purchase is kept and Glance will retry.', 503);
    const body = await response.json() as { signedTransactionInfo?: string };
    if (!body.signedTransactionInfo) throw new BillingError('app_store_unavailable', 'The App Store returned an incomplete purchase. Glance will retry.', 503);
    const transaction = jwsPayload<AppleTransaction>(body.signedTransactionInfo);
    return { ...transaction, environment: transaction.environment ?? environment };
  }
  return null;
}

/** Minor units (cents; yen for JPY) from Apple's milli-units, when the currency is one orders support. */
function orderAmount(transaction: AppleTransaction): { currency: Currency; amount: number } | null {
  const currency = transaction.currency as Currency;
  if (!CURRENCIES.includes(currency) || typeof transaction.price !== 'number' || transaction.price <= 0) return null;
  const amount = Math.round(transaction.price / (currency === 'JPY' ? 1000 : 10));
  return amount > 0 ? { currency, amount } : null;
}

/** Records a purchase the signed-in user made in the App Store build. Idempotent per transaction. */
export async function recordAppStoreTransaction(env: Env, request: Request) {
  const user = await authenticatedUser(env, request), body = await billingBody(request);
  const transactionID = String(body.transactionID ?? '');
  if (!/^\d{1,32}$/.test(transactionID)) throw new BillingError('invalid_transaction', 'A valid App Store transaction ID is required.');

  const existing = await env.DB.prepare('SELECT id,user_id FROM orders WHERE provider_order_id=?')
    .bind('apple:' + transactionID).first<{ id: string; user_id: number }>();
  if (existing) {
    if (existing.user_id !== user.id) throw new BillingError('app_store_account_mismatch',
      'This App Store purchase belongs to a different Glance account. Sign in with the account you used to buy it.', 409);
    return orderReply(env, existing.id, user.id);
  }

  const transaction = await fetchTransaction(env, transactionID);
  if (!transaction) throw new BillingError('app_store_transaction_not_found',
    'The App Store has not confirmed this purchase yet. Glance will retry automatically.', 404);
  if (transaction.bundleId !== bundleID(env)) throw new BillingError('app_store_wrong_app', 'This purchase is not for Glance.', 409);
  if (transaction.revocationDate) throw new BillingError('app_store_revoked', 'Apple refunded or revoked this purchase, so nothing was added.', 409);
  if ((transaction.appAccountToken ?? '').toLowerCase() !== await appStoreAccountToken(env, user.id))
    throw new BillingError('app_store_account_mismatch',
      'This App Store purchase belongs to a different Glance account. Sign in with the account you used to buy it.', 409);

  const prefix = bundleID(env) + '.';
  const [kind, option] = transaction.productId.startsWith(prefix) ? transaction.productId.slice(prefix.length).split('.') : [];
  const config = await readPricing(env);
  const tier = kind === 'pro' ? config.proTiers.find(t => t.id === option) : undefined;
  const pack = kind === 'credits' ? config.packs.find(p => p.id === option) : undefined;
  if (!tier && !pack) throw new BillingError('app_store_unknown_product',
    'Glance does not recognize this App Store product. Contact support with your Apple receipt.', 409);

  // Orders only hold the five billing currencies; other storefronts record the
  // configured USD list price and keep Apple's own price alongside.
  const paid = orderAmount(transaction)
    ?? { currency: 'USD' as Currency, amount: (tier ? tier.USD.amount : pack!.USD.amount) || 1 };
  const credits = pack ? (pack.USD.points ?? 0) : 0;
  if (pack && credits <= 0) throw new BillingError('app_store_unknown_product', 'This credit package has no credits configured.', 409);
  const bonusGranted = !!tier && !!await env.DB.prepare('SELECT id FROM user_credit_ledger WHERE id=?').bind('pro-bonus:' + user.id).first();
  const id = 'order_' + crypto.randomUUID(), now = isoNow();
  const paidAt = transaction.purchaseDate ? new Date(transaction.purchaseDate).toISOString() : now;
  const mode = transaction.environment === 'Production' ? 'prod' : 'test';
  try {
    // Inserted as expired and then marked paid in one transaction, so the
    // fulfil trigger runs without colliding with a pending web order.
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,
        device_limit,request_key,request_hash,checkout_expires_at,created_at,language,payment_method,billing_mode,status,
        provider_order_id,provider_payment_id,store_currency,store_price_milli)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'app_store',?,'expired',?,?,?,?)`)
        .bind(id, user.id, tier ? 'pro' : 'credits', option, paid.currency, paid.amount, credits,
          tier && !bonusGranted ? config.proBonusCredits : 0, transaction.productId, config.taxCategory, config.taxIncluded ? 1 : 0,
          tier?.deviceLimit ?? config.deviceLimit, 'app_store:' + transactionID, await sha256('app_store:' + transactionID),
          now, now, body.language === 'zh-Hans' ? 'zh-Hans' : 'en', mode, 'apple:' + transactionID,
          transaction.originalTransactionId ?? transactionID, transaction.currency ?? null, transaction.price ?? null),
      env.DB.prepare("UPDATE orders SET status='paid',paid_amount=amount,paid_at=? WHERE id=? AND status='expired'").bind(paidAt, id),
    ]);
  } catch (error) {
    if (!String(error).includes('UNIQUE')) throw error;
    // A concurrent request recorded the same transaction first.
    const winner = await env.DB.prepare('SELECT id,user_id FROM orders WHERE provider_order_id=?')
      .bind('apple:' + transactionID).first<{ id: string; user_id: number }>();
    if (!winner || winner.user_id !== user.id) throw new BillingError('app_store_account_mismatch',
      'This App Store purchase belongs to a different Glance account. Sign in with the account you used to buy it.', 409);
    return orderReply(env, winner.id, user.id);
  }
  return orderReply(env, id, user.id);
}

async function orderReply(env: Env, orderID: string, userID: number) {
  const order = (await readOrder(env, orderID, userID))!;
  const balance = (await env.DB.prepare('SELECT credits FROM users WHERE id=?').bind(userID).first<{ credits: number }>())!.credits;
  return billingReply({ order: orderPublic(order), balance });
}

/**
 * App Store Server Notifications V2. The notification only says which
 * transaction changed; its current state is fetched from Apple again, so a
 * forged notification can at most trigger a harmless re-check.
 */
export async function appStoreNotification(env: Env, request: Request) {
  const body = await billingBody(request);
  if (typeof body.signedPayload !== 'string') throw new BillingError('invalid_notification', 'signedPayload is required.');
  let payload: { notificationType?: string; subtype?: string; notificationUUID?: string;
    data?: { bundleId?: string; environment?: AppleEnvironment; signedTransactionInfo?: string } };
  let transactionID: string | undefined;
  try {
    payload = jwsPayload(body.signedPayload);
    if (payload.data?.signedTransactionInfo) transactionID = jwsPayload<AppleTransaction>(payload.data.signedTransactionInfo).transactionId;
  } catch { throw new BillingError('invalid_notification', 'Malformed notification.'); }
  if (payload.data?.bundleId && payload.data.bundleId !== bundleID(env)) return billingReply({ received: true, ignored: 'bundle' });
  if (!transactionID || !/^\d{1,32}$/.test(transactionID)) return billingReply({ received: true, ignored: 'no_transaction' });

  const order = await env.DB.prepare("SELECT id,status FROM orders WHERE provider_order_id=?")
    .bind('apple:' + transactionID).first<{ id: string; status: string }>();
  const environment = payload.data?.environment === 'Sandbox' ? 'Sandbox' : payload.data?.environment === 'Production' ? 'Production' : undefined;
  const transaction = await fetchTransaction(env, transactionID, environment);
  const now = isoNow();
  if (order && transaction?.revocationDate && ['paid', 'refund_failed'].includes(order.status)) {
    // The revoke trigger removes the credits or Pro (and its bonus) granted by this order.
    await env.DB.prepare(`UPDATE orders SET status='refunded',refunded_amount=paid_amount,refund_status='succeeded',
      refund_reason=?,refunded_at=? WHERE id=? AND status IN ('paid','refund_failed')`)
      .bind('App Store ' + (payload.notificationType ?? 'REFUND').toLowerCase(), new Date(transaction.revocationDate).toISOString(), order.id).run();
  }
  if (payload.notificationUUID) {
    await env.DB.prepare('INSERT OR IGNORE INTO app_store_notifications(id,notification_type,subtype,transaction_id,order_id,created_at) VALUES(?,?,?,?,?,?)')
      .bind(payload.notificationUUID, payload.notificationType ?? 'UNKNOWN', payload.subtype ?? null, transactionID, order?.id ?? null, now).run();
  }
  return billingReply({ received: true });
}
