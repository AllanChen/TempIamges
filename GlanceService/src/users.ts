import type { Env } from "./index";
import { BillingError, billingBody, billingReply, readPricing } from './pricing';

export type User = {
  id: number; email: string; google_id: string | null; name: string | null; avatar_url: string | null;
  auth_provider: string; status: string; credits: number; created_at: string; updated_at: string; last_login_at: string | null;
  trial_started_at: string | null; trial_voided: number; widget_notice_seen:number;
};
const stamp = () => new Date().toISOString();
const expires = (ms: number) => new Date(Date.now() + ms).toISOString();
const bearer = (r: Request) => r.headers.get("Authorization")?.match(/^Bearer (.+)$/)?.[1] || "";
const secret = () => crypto.randomUUID() + crypto.randomUUID();
async function hash(value: string) {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))), b => b.toString(16).padStart(2, "0")).join("");
}
function reply(result: unknown, status = 200) {
  return Response.json({ success: true, result }, { status, headers: { "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" } });
}
function failure(code: string, message: string, status = 400, details?:unknown) {
  return Response.json({ success: false, error: { code, message,details } }, { status, headers: { "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" } });
}
async function body(request: Request): Promise<Record<string, unknown>> {
  if (Number(request.headers.get("Content-Length") || 0) > 8192) throw new Error("Invalid JSON");
  const text = await request.text();
  if (text.length > 8192) throw new Error("Invalid JSON");
  let value: unknown;
  try { value = JSON.parse(text); } catch { throw new Error("Invalid JSON"); }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid JSON");
  return value as Record<string, unknown>;
}
function emailAddress(value: unknown) {
  const email = typeof value === "string" ? value.trim().toLowerCase() : "";
  return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}
export async function authenticatedUser(env: Env, request: Request): Promise<User> {
  const token = bearer(request);
  if (!token) throw new Error("Unauthorized");
  const user = await env.DB.prepare(`SELECT u.* FROM users u JOIN user_sessions s ON s.user_id=u.id
    WHERE s.token_hash=? AND s.expires_at>? AND u.status='active'`).bind(await hash(token), stamp()).first<User>();
  if (!user) throw new Error("Unauthorized");
  return user;
}
async function upsertUser(env: Env, email: string, google?: { sub: string; name?: string; picture?: string }, deviceHash?: string | null) {
  const t = stamp();
  const config=await readPricing(env);
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO users(email,google_id,name,avatar_url,auth_provider,created_at,updated_at,last_login_at)
      VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(email) DO UPDATE SET
      google_id=COALESCE(excluded.google_id,users.google_id),name=COALESCE(excluded.name,users.name),
      avatar_url=COALESCE(excluded.avatar_url,users.avatar_url),updated_at=excluded.updated_at,last_login_at=excluded.last_login_at`)
      .bind(email, google?.sub ?? null, google?.name ?? null, google?.picture ?? null, google ? "google" : "email", t, t, t),
    ...(deviceHash ? [
      env.DB.prepare(`INSERT OR IGNORE INTO signup_devices(device_hash,user_id,created_at)
        SELECT ?,id,? FROM users WHERE email=? AND status='active'
        AND NOT EXISTS(SELECT 1 FROM user_credit_ledger WHERE id='signup:'||users.id)`)
        .bind(deviceHash,t,email),
      env.DB.prepare(`INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at)
        SELECT 'signup:'||u.id,u.id,?,'signup_bonus','system',? FROM users u
        JOIN signup_devices d ON d.user_id=u.id AND d.device_hash=? WHERE u.email=? AND u.status='active'`)
        .bind(config.signupCredits,t,deviceHash,email)
    ] : [])
  ]);
  return (await env.DB.prepare("SELECT * FROM users WHERE email=?").bind(email).first<User>())!;
}
async function session(env: Env, user: User) {
  if (user.status !== "active") return failure("account_disabled", "This account is disabled.", 403);
  const token = secret(), expiresAt = expires(30 * 86400000);
  await env.DB.prepare("INSERT INTO user_sessions(token_hash,user_id,expires_at,created_at) VALUES(?,?,?,?)")
    .bind(await hash(token), user.id, expiresAt, stamp()).run();
  return reply({ user: { ...user, role: "user", email_verified: true }, token, expires_at: expiresAt });
}
async function rateLimit(env: Env, request: Request) {
  const key = await hash(`email:${request.headers.get("CF-Connecting-IP") || "unknown"}`);
  const window = Math.floor(Date.now() / 3600000);
  const row = await env.DB.prepare(`INSERT INTO user_auth_limits(key,count,window_start) VALUES(?,1,?)
    ON CONFLICT(key) DO UPDATE SET count=CASE WHEN window_start=excluded.window_start THEN count+1 ELSE 1 END,
    window_start=excluded.window_start WHERE window_start!=excluded.window_start OR count<20 RETURNING count`)
    .bind(key, window).first();
  return !!row;
}
async function sendEmailCode(env: Env, request: Request) {
  const data = await body(request), email = emailAddress(data.email);
  if (!email) return failure("invalid_email", "Enter a valid email address.");
  if (!env.RESEND_API_KEY || !env.AUTH_EMAIL_FROM) return failure("email_not_configured", "Email sign-in is not configured.", 503);
  if (!await rateLimit(env, request)) return failure("rate_limited", "Too many requests. Please try again later.", 429);
  // Rejection sampling avoids modulo bias in a six-digit code.
  let n: number;
  do { n = crypto.getRandomValues(new Uint32Array(1))[0]; } while (n >= 4294000000);
  const code = String(n % 1000000).padStart(6, "0"), expiry = expires(10 * 60000), sent = stamp();
  const codeHash = await hash(`${env.SESSION_SECRET}:${email}:${code}`);
  const inserted = await env.DB.prepare(`INSERT INTO user_email_codes(email,code_hash,expires_at,sent_at) VALUES(?,?,?,?)
    ON CONFLICT(email) DO UPDATE SET code_hash=excluded.code_hash,attempts=0,expires_at=excluded.expires_at,sent_at=excluded.sent_at
    WHERE sent_at<? RETURNING email`).bind(email, codeHash, expiry, sent, new Date(Date.now() - 60000).toISOString()).first();
  if (!inserted) return failure("rate_limited", "Wait a minute before requesting another code.", 429);
  let delivered = false;
  try {
    delivered = (await fetch("https://api.resend.com/emails", { method: "POST",
      headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: env.AUTH_EMAIL_FROM, to: [email], subject: "Your Glance sign-in code",
        text: `Your Glance sign-in code is ${code}. It expires in 10 minutes. If you did not request this code, ignore this email.` }) })).ok;
  } catch { /* Return a safe delivery error without provider details. */ }
  if (!delivered) {
    await env.DB.prepare("DELETE FROM user_email_codes WHERE email=? AND code_hash=?").bind(email, codeHash).run();
    return failure("email_delivery_failed", "Could not send the sign-in email. Please try again later.", 502);
  }
  return reply({ email, expires_at: expiry });
}
async function verifyEmailCode(env: Env, request: Request) {
  const data = await body(request), email = emailAddress(data.email), code = data.code;
  if (!email || typeof code !== "string" || !/^\d{6}$/.test(code)) return failure("invalid_code", "Enter your email and six-digit code.");
  const attempt = await env.DB.prepare(`UPDATE user_email_codes SET attempts=attempts+1
    WHERE email=? AND expires_at>? AND attempts<5 RETURNING code_hash,attempts`)
    .bind(email, stamp()).first<{ code_hash: string;attempts:number }>();
  const codeHash = await hash(`${env.SESSION_SECRET}:${email}:${code}`);
  if (!attempt || (attempt.code_hash!==codeHash && attempt.attempts>=5)) return failure("code_unavailable", "Request a new code. This code expired or has no attempts left.", 401);
  if (attempt.code_hash !== codeHash) return failure("invalid_code", "The code is incorrect. Please try again.", 401,{attemptsRemaining:5-attempt.attempts});
  const consumed = await env.DB.prepare("DELETE FROM user_email_codes WHERE email=? AND code_hash=? AND expires_at>? RETURNING email")
    .bind(email, codeHash, stamp()).first();
  if (!consumed) return failure("invalid_code", "The code is invalid or expired.", 401);
  const device=typeof data.deviceID==='string'?data.deviceID:request.headers.get('X-Glance-Device');
  const deviceHash=device && /^[A-Za-z0-9_-]{16,128}$/.test(device)?await hash(device):null;
  return session(env, await upsertUser(env, email,undefined,deviceHash));
}
async function googleStart(env: Env, request: Request) {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET) return failure("auth_not_configured", "Google sign-in is not configured.", 503);
  const url = new URL(request.url), state = url.searchParams.get("state") || "", challenge = url.searchParams.get("code_challenge") || "";
  if (!/^[A-Za-z0-9_-]{24,128}$/.test(state) || !/^[A-Za-z0-9_-]{43}$/.test(challenge)) return failure("invalid_login", "Invalid sign-in request.");
  const oauthState = secret();
  const device=url.searchParams.get('device_id');
  await env.DB.prepare("INSERT INTO user_oauth_states(state_hash,client_state,code_challenge,expires_at,device_hash) VALUES(?,?,?,?,?)")
    .bind(await hash(oauthState), state, challenge, expires(5 * 60000),device && /^[A-Za-z0-9_-]{16,128}$/.test(device)?await hash(device):null).run();
  const google = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  google.search = new URLSearchParams({ client_id: env.GOOGLE_CLIENT_ID, redirect_uri: env.GOOGLE_REDIRECT_URI || `${env.PUBLIC_ORIGIN}/auth/google/callback`,
    response_type: "code", scope: "openid email profile", state: oauthState, prompt: "select_account" }).toString();
  return Response.redirect(google.toString(), 302);
}
async function googleCallback(env: Env, request: Request) {
  const url = new URL(request.url);
  const record = await env.DB.prepare(`DELETE FROM user_oauth_states WHERE state_hash=? AND expires_at>?
    RETURNING client_state,code_challenge,device_hash`).bind(await hash(url.searchParams.get("state") || ""), stamp())
    .first<{ client_state: string; code_challenge: string;device_hash:string|null }>();
  if (!record) return failure("invalid_state", "The sign-in request expired.");
  const callback = new URL("glance://auth/callback");
  callback.searchParams.set("state", record.client_state);
  const code = url.searchParams.get("code");
  if (!code) { callback.searchParams.set("error", "Google sign-in was cancelled."); return Response.redirect(callback.toString(), 302); }
  const response = await fetch("https://oauth2.googleapis.com/token", { method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ code,
      client_id: env.GOOGLE_CLIENT_ID!, client_secret: env.GOOGLE_CLIENT_SECRET!,
      redirect_uri: env.GOOGLE_REDIRECT_URI || `${env.PUBLIC_ORIGIN}/auth/google/callback`, grant_type: "authorization_code" }) });
  if (!response.ok) return failure("google_exchange_failed", "Could not complete Google sign-in.", 502);
  const tokens = await response.json() as { access_token?: string };
  const profile = await fetch("https://openidconnect.googleapis.com/v1/userinfo", { headers: { Authorization: `Bearer ${tokens.access_token || ""}` } });
  if (!profile.ok) return failure("google_profile_failed", "Could not verify your Google account.", 502);
  const info = await profile.json() as { sub?: string; email?: string; email_verified?: boolean; name?: string; picture?: string };
  const email = emailAddress(info.email);
  if (!email || !info.sub || info.email_verified !== true) return failure("email_not_verified", "A verified Google email is required.", 403);
  const user = await upsertUser(env, email, { sub: info.sub, name: info.name, picture: info.picture },record.device_hash);
  if (user.status !== "active") return failure("account_disabled", "This account is disabled.", 403);
  const nativeCode = secret();
  await env.DB.prepare("INSERT INTO user_auth_codes(code_hash,user_id,code_challenge,expires_at) VALUES(?,?,?,?)")
    .bind(await hash(nativeCode), user.id, record.code_challenge, expires(60000)).run();
  callback.searchParams.set("code", nativeCode);
  return Response.redirect(callback.toString(), 302);
}
async function exchangeCode(env: Env, request: Request) {
  const data = await body(request);
  if (typeof data.code !== "string" || typeof data.code_verifier !== "string" || !/^[A-Za-z0-9_-]{43,128}$/.test(data.code_verifier)) return failure("invalid_code", "Invalid sign-in code.");
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(data.code_verifier)));
  const challenge = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const code = await env.DB.prepare(`DELETE FROM user_auth_codes WHERE code_hash=? AND code_challenge=? AND expires_at>? RETURNING user_id`)
    .bind(await hash(data.code), challenge, stamp()).first<{ user_id: number }>();
  if (!code) return failure("invalid_code", "The sign-in code is invalid or expired.", 401);
  const user = await env.DB.prepare("SELECT * FROM users WHERE id=?").bind(code.user_id).first<User>();
  if (!user) return failure("invalid_code", "Account not found.", 401);
  return session(env, user);
}
export async function userRoutes(env: Env, request: Request): Promise<Response | undefined> {
  const url = new URL(request.url), path = url.pathname, method = request.method;
  if (method === "GET" && path === "/auth/google") return googleStart(env, request);
  if (method === "GET" && path === "/auth/google/callback") return googleCallback(env, request);
  if (method === "POST" && path === "/auth/email/send-code") return sendEmailCode(env, request);
  if (method === "POST" && path === "/auth/email/verify-code") return verifyEmailCode(env, request);
  if (method === "POST" && path === "/auth/native/exchange") return exchangeCode(env, request);
  if (method === "POST" && path === "/auth/logout") {
    await env.DB.prepare("DELETE FROM user_sessions WHERE token_hash=?").bind(await hash(bearer(request))).run();
    return reply({ signed_out: true });
  }
  if (method === "GET" && path === "/auth/me") {
    const user = await authenticatedUser(env, request);
    return reply({ user: { ...user, role: "user", email_verified: true } });
  }
  if (method === "GET" && path === "/api/v2/account/credits") {
    const user = await authenticatedUser(env, request);
    const ledger = await env.DB.prepare("SELECT id,amount,reason,task_id,created_at FROM user_credit_ledger WHERE user_id=? ORDER BY created_at DESC,id DESC LIMIT 100").bind(user.id).all();
    return reply({ balance: user.credits, transactions: ledger.results });
  }
}

// Called only after the main router has authenticated an administrator.
export async function adminUsers(env: Env, request: Request, userID?: number) {
  if (request.method === "GET" && !userID) {
    const users = await env.DB.prepare(`SELECT u.id,u.email,u.name,u.status,u.credits,u.auth_provider,u.created_at,u.last_login_at,
      COALESCE(l.status,'free') license_status,l.updates_until,
      CASE WHEN l.source_order IS NOT NULL THEN 'purchase' WHEN l.source_admin_grant IS NOT NULL THEN 'admin' ELSE NULL END license_source
      FROM users u LEFT JOIN licenses l ON l.user_id=u.id ORDER BY u.id DESC LIMIT 100`).all();
    return reply({ users: users.results });
  }
  if (!userID || request.method !== "POST") return failure("not_found", "Not found.", 404);
  const data = await body(request), amount = data.amount, note = data.note, key = request.headers.get("Idempotency-Key") || "";
  if (!Number.isSafeInteger(amount) || (amount as number) < 1 || (amount as number) > 1000000000 ||
      typeof note !== "string" || !note.trim() || note.length > 500 || !/^[A-Za-z0-9_-]{16,128}$/.test(key)) {
    return failure("invalid_credit_grant", "A positive integer amount, note, and Idempotency-Key are required.");
  }
  const user = await env.DB.prepare("SELECT id FROM users WHERE id=?").bind(userID).first();
  if (!user) return failure("user_not_found", "User not found.", 404);
  const grantID = `admin:${key}`;
  const previous = await env.DB.prepare("SELECT user_id,amount,reason,note FROM user_credit_ledger WHERE id=?").bind(grantID).first<{ user_id: number; amount: number; reason: string; note:string|null }>();
  if (previous && (previous.user_id !== userID || previous.amount !== amount || (previous.note??previous.reason)!==note.trim())) return failure("idempotency_conflict", "This request key was already used.", 409);
  await env.DB.prepare("INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,note) VALUES(?,?,?,'admin_adjust','admin',?,?)")
    .bind(grantID, userID, amount, stamp(),note.trim()).run();
  const saved = await env.DB.prepare("SELECT user_id,amount,reason,note FROM user_credit_ledger WHERE id=?").bind(grantID).first<{ user_id: number; amount: number; reason: string;note:string|null }>();
  if (!saved || saved.user_id !== userID || saved.amount !== amount || (saved.note??saved.reason)!==note.trim()) return failure("idempotency_conflict", "This request key was already used.", 409);
  const balance = await env.DB.prepare("SELECT credits FROM users WHERE id=?").bind(userID).first<{ credits: number }>();
  return reply({ userID, balance: balance!.credits });
}

// Main router authenticates the administrator before entering this handler.
export async function adminGrantPro(env: Env, request: Request, userID: number) {
  const data=await billingBody(request), key=request.headers.get('Idempotency-Key')||'';
  if (!Number.isSafeInteger(userID) || userID<1 || !/^[A-Za-z0-9_-]{16,128}$/.test(key) ||
      typeof data.note!=='string' || !data.note.trim() || data.note.length>500) {
    throw new BillingError('invalid_pro_grant','A note and Idempotency-Key are required.');
  }
  const id='admin-pro:'+key, note=data.note.trim();
  const user=await env.DB.prepare('SELECT status FROM users WHERE id=?').bind(userID).first<{status:string}>();
  if (!user) throw new BillingError('user_not_found','User not found.',404);
  const config=await readPricing(env);
  try {
    await env.DB.prepare(`INSERT OR IGNORE INTO admin_pro_grants(id,user_id,note,actor_id,created_at,updates_months)
      VALUES(?,?,?,'admin',?,?)`).bind(id,userID,note,stamp(),config.updatesMonths).run();
  } catch (error) {
    const message=String(error);
    if (message.includes('already_pro')) throw new BillingError('already_pro','This user already has Pro.',409);
    if (message.includes('account_disabled')) throw new BillingError('account_disabled','This account is disabled.',409);
    throw error;
  }
  const grant=await env.DB.prepare('SELECT user_id,note,created_at,updates_months FROM admin_pro_grants WHERE id=?')
    .bind(id).first<{user_id:number;note:string;created_at:string;updates_months:number}>();
  if (!grant || grant.user_id!==userID || grant.note!==note) throw new BillingError('idempotency_conflict','This request key was already used.',409);
  const license=await env.DB.prepare('SELECT status,purchased_at,updates_until FROM licenses WHERE user_id=?').bind(userID).first();
  return billingReply({userID,grantID:id,license,grant});
}
