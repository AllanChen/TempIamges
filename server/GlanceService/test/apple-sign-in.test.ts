import { env } from 'cloudflare:workers';
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import worker from '../src/index';
import { seedUser } from './helpers';

let signingKey: CryptoKey;
let run = 0;  // Each test signs in a different Apple user.
let publicJWK: JsonWebKey;
const b64url = (bytes: Uint8Array | string) =>
  btoa(typeof bytes === 'string' ? bytes : String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
async function sha256Hex(value: string) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(b => b.toString(16).padStart(2, '0')).join('');
}
async function identityToken(claims: Record<string, unknown>, kid = 'apple-key-1') {
  const header = b64url(JSON.stringify({ alg: 'RS256', kid }));
  const payload = b64url(JSON.stringify(claims));
  const signature = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', signingKey, new TextEncoder().encode(`${header}.${payload}`)));
  return `${header}.${payload}.${b64url(signature)}`;
}
async function claims(nonce: string, extra: Record<string, unknown> = {}) {
  return { iss: 'https://appleid.apple.com', aud: 'com.glance.app', exp: Math.floor(Date.now() / 1000) + 600,
    sub: `apple-user-${run}`, nonce: await sha256Hex(nonce), email: `user${run}@privaterelay.appleid.com`, email_verified: 'true', ...extra };
}
async function signIn(token: string, nonce: string) {
  const response = await worker.fetch(new Request('https://example.com/auth/apple', { method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ identityToken: token, nonce, deviceID: 'apple-sign-in-device-01' }) }), env);
  return { status: response.status, body: await response.json() as { result?: { token: string; user: { id: number; email: string } }; error?: { code: string } } };
}

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify']) as CryptoKeyPair;
  signingKey = pair.privateKey;
  publicJWK = { ...await crypto.subtle.exportKey('jwk', pair.publicKey) as JsonWebKey, kid: 'apple-key-1', use: 'sig', alg: 'RS256' } as JsonWebKey;
});
beforeEach(async () => {
  run = Date.now() * 100 + Math.floor(Math.random() * 100);
  vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request) => {
    expect(String(input)).toBe('https://appleid.apple.com/auth/keys');
    return Response.json({ keys: [publicJWK] });
  }));
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

describe('Sign in with Apple', () => {
  it('creates an account on first sign-in and returns the same account afterwards', async () => {
    const first = await signIn(await identityToken(await claims('nonce-value-0000001')), 'nonce-value-0000001');
    expect(first.status).toBe(200);
    expect(first.body.result!.user.email).toBe(`user${run}@privaterelay.appleid.com`);
    const row = await env.DB.prepare('SELECT apple_id,auth_provider FROM users WHERE id=?').bind(first.body.result!.user.id).first();
    expect(row).toEqual({ apple_id: `apple-user-${run}`, auth_provider: 'apple' });
    // Later tokens may omit the email; the Apple user ID still finds the account.
    const again = await signIn(await identityToken(await claims('nonce-value-0000002', { email: undefined })), 'nonce-value-0000002');
    expect(again.body.result!.user.id).toBe(first.body.result!.user.id);
  });

  it('links an existing account with the same verified email', async () => {
    await seedUser('existing-token', 50, 40);
    await env.DB.prepare('UPDATE users SET email=? WHERE id=40').bind(`user${run}@privaterelay.appleid.com`).run();
    const result = await signIn(await identityToken(await claims('nonce-value-0000003')), 'nonce-value-0000003');
    expect(result.body.result!.user.id).toBe(40);
  });

  it('rejects a token issued for another sign-in attempt', async () => {
    const result = await signIn(await identityToken(await claims('nonce-value-0000004')), 'nonce-value-different');
    expect(result.status).toBe(401);
  });

  it('rejects a token for another app', async () => {
    const result = await signIn(await identityToken(await claims('nonce-value-0000005', { aud: 'com.example.other' })), 'nonce-value-0000005');
    expect(result.status).toBe(401);
  });

  it('rejects a token not signed by Apple', async () => {
    const token = await identityToken(await claims('nonce-value-0000006'));
    const [header, payload] = token.split('.');
    const forged = `${header}.${payload}.${b64url('not-a-signature')}`;
    expect((await signIn(forged, 'nonce-value-0000006')).status).toBe(401);
  });

  it('explains when Apple shares no email for a new account', async () => {
    const result = await signIn(await identityToken(await claims('nonce-value-0000007', { email: undefined, sub: 'new-sub' })), 'nonce-value-0000007');
    expect(result.status).toBe(403);
    expect(result.body.error!.code).toBe('apple_email_missing');
  });
});
