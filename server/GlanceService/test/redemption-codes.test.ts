import { env } from 'cloudflare:workers';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import worker, { type Env } from '../src/index';
import { USER_TOKEN } from './helpers';

const device = 'redemption-test-device-0001';
const otherToken = 'other-user-token';
let testEnv: Env;

async function call(path: string, options: {method?: string;token?: string;json?: unknown;headers?: HeadersInit} = {}) {
  const headers = new Headers(options.headers);
  headers.set('X-Glance-Device', device);
  if (options.token) headers.set('Authorization', `Bearer ${options.token}`);
  if (options.json !== undefined) headers.set('Content-Type', 'application/json');
  return worker.fetch(new Request(`https://example.com${path}`, {
    method: options.method ?? 'GET', headers,
    body: options.json === undefined ? undefined : JSON.stringify(options.json)
  }), testEnv);
}

async function seed(token = USER_TOKEN, userID = 1, credits = 500) {
  const now = new Date().toISOString();
  const digest = async (value: string) => {
    const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
    return [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, '0')).join('');
  };
  await testEnv.DB.batch([
    testEnv.DB.prepare(`INSERT INTO users(id,email,auth_provider,credits,created_at,updated_at)
      VALUES(?,?,'email',?,?,?) ON CONFLICT(id) DO UPDATE SET credits=excluded.credits,status='active',trial_voided=0`)
      .bind(userID, `redeem${userID}@example.com`, credits, now, now),
    testEnv.DB.prepare('INSERT OR REPLACE INTO user_sessions(token_hash,user_id,expires_at,created_at) VALUES(?,?,?,?)')
      .bind(await digest(token), userID, new Date(Date.now()+86400000).toISOString(), now)
  ]);
}

async function generate(kind: 'lifetime'|'one_year' = 'lifetime', quantity = 1, extra: Record<string, unknown> = {}) {
  const response = await call('/api/admin/v2/redemption-codes', {
    method: 'POST', token: env.ADMIN_TOKEN,
    json: { kind, quantity, note: 'Launch testers', deviceLimit: 1, ...extra }
  });
  const body = await response.json() as any;
  return { response, body, codes: body.result?.codes ?? [] as string[] };
}

async function redeem(code: string, token = USER_TOKEN) {
  return call('/api/v2/account/pro/redeem', { method: 'POST', token, json: { code } });
}

async function activate(token = USER_TOKEN) {
  return call('/api/v2/account/devices/activate', { method: 'POST', token, json: { name: 'Redemption Test Mac' } });
}

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']) as CryptoKeyPair;
  const bytes = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  testEnv = { ...env, WAFFO_ENVIRONMENT: 'test', GLANCE_SIGNING_KEY_PKCS8: btoa(String.fromCharCode(...bytes)) };
});

beforeEach(async () => {
  await testEnv.DB.batch([
    'DELETE FROM license_devices', 'DELETE FROM licenses', 'DELETE FROM pro_redemption_codes',
    'DELETE FROM admin_pro_grants', 'DELETE FROM team_invites', 'DELETE FROM team_members',
    'DELETE FROM refund_requests', 'DELETE FROM orders', 'DELETE FROM billing_settings'
  ].map(sql => testEnv.DB.prepare(sql)));
  await seed();
  await seed(otherToken, 2, 300);
});

describe('redemption code administration', () => {
  it('requires admin auth, validates batches and never returns plaintext after creation', async () => {
    expect((await call('/api/admin/v2/redemption-codes')).status).toBe(401);
    expect((await generate('lifetime', 0)).response.status).toBe(400);
    const { response, body, codes } = await generate('lifetime', 2);
    expect(response.status).toBe(201);
    expect(codes).toHaveLength(2);
    expect(codes[0]).toMatch(/^GLG-(?:[A-HJ-NP-Z2-9]{4}-){3}[A-HJ-NP-Z2-9]{4}$/);
    expect(body.result.batch.billingMode).toBe('test');
    const listed = await call('/api/admin/v2/redemption-codes', { token: env.ADMIN_TOKEN });
    const text = await listed.text();
    expect(text).not.toContain(codes[0]);
    expect(text).not.toContain('code_hash');
    const data = JSON.parse(text);
    expect(data.result.batches[0]).toMatchObject({ issued: 2, redeemed: 0, revoked: 0, kind: 'lifetime' });
  });

  it('revokes only unused codes and enforces code expiry and environment isolation', async () => {
    const batch = await generate('lifetime', 2);
    const batchID = batch.body.result.batch.id;
    const revoked = await call(`/api/admin/v2/redemption-codes/${batchID}/revoke`, { method: 'POST', token: env.ADMIN_TOKEN });
    expect((await revoked.json() as any).result.revoked).toBe(2);
    expect((await redeem(batch.codes[0])).status).toBe(409);
    const expired = await generate('one_year');
    await testEnv.DB.prepare("UPDATE pro_redemption_codes SET expires_at='2000-01-01T00:00:00.000Z'").run();
    expect((await redeem(expired.codes[0])).status).toBe(410);
    const isolated = await generate();
    await testEnv.DB.prepare("UPDATE pro_redemption_codes SET billing_mode='prod'").run();
    expect((await redeem(isolated.codes[0])).status).toBe(404);
    expect(await testEnv.DB.prepare('SELECT redeemed_by FROM pro_redemption_codes').first<any>()).toEqual({ redeemed_by: null });
  });
});

describe('redeemed Pro licenses', () => {
  it('redeems lifetime Pro without payment or credits, activates and reports it once', async () => {
    const { codes } = await generate();
    const response = await redeem(codes[0]);
    expect(response.status).toBe(200);
    expect((await response.json() as any).result).toMatchObject({ licenseStatus: 'active', pro: false, accessExpiresAt: null });
    const activated = await activate();
    const entitlement = (await activated.json() as any).result;
    expect(entitlement.pro).toBe(true);
    expect(entitlement.credential).toBeTruthy();
    expect(JSON.parse(atob(entitlement.credential.payload)).accessExpiresAt).toBeNull();
    const repeated = await redeem(codes[0]);
    expect(repeated.status).toBe(200);
    expect((await redeem(codes[0], otherToken)).status).toBe(409);
    const license = await testEnv.DB.prepare('SELECT * FROM licenses WHERE user_id=1').first<any>();
    expect(license).toMatchObject({ status: 'active', updates_until: '9999-12-31T00:00:00.000Z', access_expires_at: null, device_limit: 1 });
    expect(license.source_redemption_code).toBeTruthy();
    expect(license.source_order).toBeNull();
    expect((await testEnv.DB.prepare('SELECT COUNT(*) n FROM orders').first<any>()).n).toBe(0);
    expect((await testEnv.DB.prepare('SELECT credits FROM users WHERE id=1').first<any>()).credits).toBe(500);
    expect((await testEnv.DB.prepare('SELECT COUNT(*) n FROM pro_redemption_codes WHERE redeemed_by=1').first<any>()).n).toBe(1);
    const metrics = await call('/api/admin/v2/billing/metrics?days=30', { token: env.ADMIN_TOKEN });
    const report = (await metrics.json() as any).result.launch.redemptions;
    expect(report).toEqual([expect.objectContaining({ kind: 'lifetime', issued: 1, redeemed: 1, active: 1, activated: 1, expired: 0 })]);
  });

  it('expires one-year Pro online and in signed credentials, then allows a new grant', async () => {
    const { codes } = await generate('one_year');
    expect((await redeem(codes[0])).status).toBe(200);
    const activated = await activate();
    const entitlement = (await activated.json() as any).result;
    const accessExpiresAt = entitlement.accessExpiresAt;
    expect(Date.parse(accessExpiresAt)).toBeGreaterThan(Date.now()+300*86400000);
    const claims = JSON.parse(atob(entitlement.credential.payload));
    expect(claims.accessExpiresAt).toBe(accessExpiresAt);
    expect(Date.parse(claims.expiresAt)).toBeLessThanOrEqual(Date.parse(accessExpiresAt));
    await testEnv.DB.batch([
      testEnv.DB.prepare("UPDATE licenses SET access_expires_at='2000-01-01T00:00:00.000Z'").bind(),
      testEnv.DB.prepare("UPDATE pro_redemption_codes SET access_expires_at='2000-01-01T00:00:00.000Z'").bind()
    ]);
    const expired = await call('/api/v2/account/entitlements', { token: USER_TOKEN });
    expect((await expired.json() as any).result).toMatchObject({ licenseStatus: 'expired', pro: false, credential: null });
    expect((await testEnv.DB.prepare('SELECT COUNT(*) n FROM license_devices WHERE released_at IS NULL').first<any>()).n).toBe(0);
    const next = await generate('lifetime');
    expect((await redeem(next.codes[0])).status).toBe(200);
    expect((await activate()).status).toBe(200);
    expect((await testEnv.DB.prepare('SELECT source_redemption_code,access_expires_at FROM licenses WHERE user_id=1').first<any>())).toEqual({
      source_redemption_code: expect.any(String), access_expires_at: null
    });
  });

  it('does not consume a code when the account already has Pro', async () => {
    const { codes } = await generate();
    const granted = await call('/api/admin/v2/users/1/pro', {
      method: 'POST', token: env.ADMIN_TOKEN,
      headers: { 'Idempotency-Key': crypto.randomUUID() }, json: { note: 'Existing Pro' }
    });
    expect(granted.status).toBe(200);
    expect((await redeem(codes[0])).status).toBe(409);
    expect(await testEnv.DB.prepare('SELECT redeemed_by FROM pro_redemption_codes').first<any>()).toEqual({ redeemed_by: null });
    expect((await testEnv.DB.prepare('SELECT source_admin_grant,source_redemption_code FROM licenses WHERE user_id=1').first<any>())).toEqual({
      source_admin_grant: expect.any(String), source_redemption_code: null
    });
  });

  it('clears redemption expiry when a paid team upgrade becomes the license source', async () => {
    const { codes } = await generate('one_year');
    expect((await redeem(codes[0])).status).toBe(200);
    const now = new Date().toISOString();
    await testEnv.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,
      product_id,tax_category,tax_included,updates_months,request_key,request_hash,checkout_expires_at,created_at,billing_mode,device_limit)
      VALUES('redemption-upgrade-order',1,'pro','team','USD',1999,0,0,'PROD_team','software',1,12,
        'redemption-upgrade-request','hash',?,?, 'test',1)`)
      .bind(new Date(Date.now()+86400000).toISOString(), now).run();
    await testEnv.DB.prepare("UPDATE orders SET status='paid',paid_at=? WHERE id='redemption-upgrade-order'").bind(now).run();
    expect(await testEnv.DB.prepare(`SELECT source_order,source_redemption_code,access_expires_at,tier_id
      FROM licenses WHERE user_id=1`).first<any>()).toEqual({
      source_order: 'redemption-upgrade-order', source_redemption_code: null, access_expires_at: null, tier_id: 'team'
    });
  });

  it('atomically allows only one redemption under concurrency', async () => {
    const shared = await generate();
    const attempts = await Promise.all([redeem(shared.codes[0]), redeem(shared.codes[0], otherToken)]);
    expect(attempts.map(response => response.status).sort()).toEqual([200, 409]);
    expect((await testEnv.DB.prepare('SELECT COUNT(*) n FROM licenses').first<any>()).n).toBe(1);
    const active = await testEnv.DB.prepare('SELECT user_id FROM licenses').first<any>();
    const token = active.user_id === 1 ? otherToken : USER_TOKEN;
    const twoCodes = await generate('lifetime', 2);
    const sameAccount = await Promise.all(twoCodes.codes.map((code: string) => redeem(code, token)));
    expect(sameAccount.map(response => response.status).sort()).toEqual([200, 409]);
    expect((await testEnv.DB.prepare('SELECT COUNT(*) n FROM pro_redemption_codes WHERE redeemed_at IS NOT NULL AND batch_id=?')
      .bind(twoCodes.body.result.batch.id).first<any>()).n).toBe(1);
  });
});
