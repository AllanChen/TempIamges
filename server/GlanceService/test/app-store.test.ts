import { env } from 'cloudflare:workers';
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import worker, { type Env } from '../src/index';
import { appStoreAccountToken, type AppleTransaction } from '../src/app-store';
import { seedUser, USER_TOKEN } from './helpers';

const device = 'app-store-test-device-01';
let storeEnv: Env;
let transactions: Record<string, { environment: 'Production' | 'Sandbox'; transaction: AppleTransaction }>;
let appleCalls: string[];

const b64url = (value: string) => btoa(value).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const fakeJWS = (payload: unknown) => `${b64url('{"alg":"ES256"}')}.${b64url(JSON.stringify(payload))}.sig`;

beforeAll(async () => {
  const key = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  const pkcs8 = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey('pkcs8', key.privateKey))));
  storeEnv = { ...env, APP_STORE_ISSUER_ID: 'issuer-1', APP_STORE_KEY_ID: 'KEY123',
    APP_STORE_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----` };
});

beforeEach(async () => {
  await env.DB.batch(['DELETE FROM app_store_notifications', 'DELETE FROM licenses', 'DELETE FROM orders',
    'DELETE FROM license_devices', 'DELETE FROM billing_settings', 'DELETE FROM user_credit_ledger'].map(sql => env.DB.prepare(sql)));
  await seedUser(USER_TOKEN, 100, 1);
  await seedUser('other-user', 100, 2);
  await env.DB.prepare('UPDATE users SET trial_started_at=NULL,trial_voided=0 WHERE id IN (1,2)').run();
  transactions = {}; appleCalls = [];
  vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    appleCalls.push(url);
    expect(new Headers(init?.headers).get('Authorization')).toMatch(/^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    const id = url.split('/').pop()!;
    const entry = transactions[id];
    const sandbox = url.includes('sandbox');
    if (!entry || (entry.environment === 'Sandbox') !== sandbox) return new Response('{}', { status: 404 });
    return Response.json({ signedTransactionInfo: fakeJWS(entry.transaction) });
  }));
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

async function call(path: string, body?: unknown, token = USER_TOKEN, environment = storeEnv) {
  return worker.fetch(new Request('https://example.com' + path, { method: body === undefined ? 'GET' : 'POST',
    headers: { Authorization: 'Bearer ' + token, 'X-Glance-Device': device, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body) }), environment);
}
async function credits(userID = 1) {
  return (await env.DB.prepare('SELECT credits FROM users WHERE id=?').bind(userID).first<{ credits: number }>())!.credits;
}
async function purchase(id: string, productId: string, extra: Partial<AppleTransaction> = {}, environment: 'Production' | 'Sandbox' = 'Production') {
  transactions[id] = { environment, transaction: { transactionId: id, originalTransactionId: id, bundleId: 'com.glance.app', productId,
    purchaseDate: Date.now(), appAccountToken: await appStoreAccountToken(storeEnv, 1), environment, price: 2990, currency: 'USD', ...extra } };
}

describe('App Store purchases', () => {
  it('grants a credit pack once, however often the transaction is replayed', async () => {
    await purchase('1001', 'com.glance.app.credits.small');
    const first = await call('/api/v2/app-store/transactions', { transactionID: '1001' });
    expect(first.status).toBe(200);
    const body = await first.json() as { result: { order: { status: string; store: string; credits: number }; balance: number } };
    expect(body.result.order).toMatchObject({ status: 'paid', store: 'app_store', credits: 600 });
    expect(body.result.balance).toBe(700);
    for (let i = 0; i < 3; i++) expect((await call('/api/v2/app-store/transactions', { transactionID: '1001' })).status).toBe(200);
    expect(await credits()).toBe(700);
    expect(await env.DB.prepare("SELECT COUNT(*) n FROM orders WHERE provider_order_id='apple:1001'").first('n')).toBe(1);
  });

  it('rejects a purchase made for another Glance account and grants nothing', async () => {
    await purchase('1002', 'com.glance.app.credits.small', { appAccountToken: await appStoreAccountToken(storeEnv, 2) });
    const response = await call('/api/v2/app-store/transactions', { transactionID: '1002' });
    expect(response.status).toBe(409);
    expect((await response.json() as { error: { code: string } }).error.code).toBe('app_store_account_mismatch');
    expect(await credits()).toBe(100);
  });

  it('refuses a recorded transaction submitted by a different user', async () => {
    await purchase('1003', 'com.glance.app.credits.small');
    expect((await call('/api/v2/app-store/transactions', { transactionID: '1003' })).status).toBe(200);
    const replay = await call('/api/v2/app-store/transactions', { transactionID: '1003' }, 'other-user');
    expect(replay.status).toBe(409);
    expect(await credits(2)).toBe(100);
  });

  it('does not grant a revoked purchase', async () => {
    await purchase('1004', 'com.glance.app.credits.small', { revocationDate: Date.now() });
    const response = await call('/api/v2/app-store/transactions', { transactionID: '1004' });
    expect((await response.json() as { error: { code: string } }).error.code).toBe('app_store_revoked');
    expect(await credits()).toBe(100);
  });

  it('keeps the purchase retryable when Apple has no record yet', async () => {
    const response = await call('/api/v2/app-store/transactions', { transactionID: '1005' });
    expect(response.status).toBe(404);
    expect(appleCalls.some(url => url.includes('sandbox'))).toBe(true);
  });

  it('accepts sandbox purchases as test orders', async () => {
    await purchase('1006', 'com.glance.app.credits.small', {}, 'Sandbox');
    expect((await call('/api/v2/app-store/transactions', { transactionID: '1006' })).status).toBe(200);
    expect(await env.DB.prepare("SELECT billing_mode FROM orders WHERE provider_order_id='apple:1006'").first('billing_mode')).toBe('test');
  });

  it('activates Pro and revokes it with its bonus when Apple refunds', async () => {
    await purchase('1007', 'com.glance.app.pro.personal', { price: 9990 });
    expect((await call('/api/v2/app-store/transactions', { transactionID: '1007' })).status).toBe(200);
    expect(await env.DB.prepare('SELECT status FROM licenses WHERE user_id=1').first('status')).toBe('active');
    expect(await credits()).toBe(200);

    transactions['1007'].transaction.revocationDate = Date.now();
    const notification = { signedPayload: fakeJWS({ notificationType: 'REFUND', notificationUUID: 'n-1',
      data: { bundleId: 'com.glance.app', environment: 'Production', signedTransactionInfo: fakeJWS({ transactionId: '1007' }) } }) };
    for (let i = 0; i < 2; i++) expect((await call('/api/v2/app-store/notifications', notification)).status).toBe(200);
    expect(await env.DB.prepare('SELECT status FROM licenses WHERE user_id=1').first('status')).toBe('refunded');
    expect(await credits()).toBe(100);
  });

  it('ignores a forged refund notification for a purchase Apple has not revoked', async () => {
    await purchase('1008', 'com.glance.app.credits.small');
    await call('/api/v2/app-store/transactions', { transactionID: '1008' });
    const forged = { signedPayload: fakeJWS({ notificationType: 'REFUND', notificationUUID: 'n-2',
      data: { bundleId: 'com.glance.app', signedTransactionInfo: fakeJWS({ transactionId: '1008' }) } }) };
    expect((await call('/api/v2/app-store/notifications', forged)).status).toBe(200);
    expect(await credits()).toBe(700);
  });

  it('sends App Store refund requests to Apple', async () => {
    await purchase('1009', 'com.glance.app.credits.small');
    const order = (await (await call('/api/v2/app-store/transactions', { transactionID: '1009' })).json() as { result: { order: { id: string } } }).result.order;
    const refund = await call(`/api/v2/orders/${order.id}/refund`, { reason: 'Changed my mind' });
    expect((await refund.json() as { error: { code: string } }).error.code).toBe('app_store_refund');
  });

  it('reports an unconfigured App Store connection as retryable', async () => {
    await purchase('1010', 'com.glance.app.credits.small');
    const response = await call('/api/v2/app-store/transactions', { transactionID: '1010' }, USER_TOKEN, { ...storeEnv, APP_STORE_PRIVATE_KEY: undefined });
    expect(response.status).toBe(503);
    expect(await credits()).toBe(100);
  });

  it('tells the client which account token to attach to purchases', async () => {
    const response = await call('/api/v2/account/entitlements');
    const body = await response.json() as { result: { appStoreAccountToken: string } };
    expect(body.result.appStoreAccountToken).toBe(await appStoreAccountToken(storeEnv, 1));
  });
});
