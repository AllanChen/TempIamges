import type { Env } from "./index";

const noStore = { "Cache-Control": "no-store", "Content-Type": "application/json" };
const respond = (result: unknown, status = 200) => new Response(JSON.stringify({ success: true, result }), { status, headers: noStore });
const error = (code: string, message: string, status: number) => new Response(JSON.stringify({ success: false, error: { code, message } }), { status, headers: noStore });
const timestamp = () => new Date().toISOString();
const expiry = (minutes: number) => new Date(Date.now() + minutes * 60_000).toISOString();
const authToken = (request: Request) => request.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1] || "";
export async function readSmallJSON(request: Request): Promise<Record<string, unknown> | null> {
  if (Number(request.headers.get("Content-Length") || 0) > 16_384) return null;
  const reader = request.body?.getReader();
  if (!reader) return null;
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > 16_384) { await reader.cancel(); return null; }
    chunks.push(value);
  }
  const body = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
  try {
    const parsed = JSON.parse(new TextDecoder().decode(body)) as unknown;
    return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : null;
  } catch { return null; }
}
async function hash(value: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
const tokenHash = (env: Env, token: string) => hash(`${env.SESSION_SECRET}:${token}`);
type User = { id: number; email: string; google_id: string | null; name: string | null; avatar_url: string | null;
  auth_provider: string; status: string; created_at: string; updated_at: string; last_login_at: string | null };

export async function requireAppUser(env: Env, request: Request): Promise<User> {
  const token = authToken(request);
  if (!token) throw new Error("Unauthorized");
  const user = await env.DB.prepare(`SELECT u.* FROM app_sessions s JOIN app_users u ON u.id=s.user_id
    WHERE s.token_hash=? AND s.expires_at>? AND u.status='active'`)
    .bind(await tokenHash(env, token), timestamp()).first<User>();
  if (!user) throw new Error("Unauthorized");
  return user;
}

function publicUser(user: User) {
  return { id: user.id, email: user.email, google_id: user.google_id, name: user.name,
    avatar_url: user.avatar_url, role: "user", auth_provider: user.auth_provider,
    email_verified: true, status: user.status, created_at: user.created_at,
    updated_at: user.updated_at, last_login_at: user.last_login_at };
}

async function issueSession(env: Env, userID: number) {
  const user = await env.DB.prepare("SELECT * FROM app_users WHERE id=?").bind(userID).first<User>();
  if (!user) throw new Error("User missing");
  const token = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const expiresAt = expiry(60 * 24 * 30);
  await env.DB.prepare("INSERT INTO app_sessions(token_hash,user_id,expires_at,created_at) VALUES(?,?,?,?)")
    .bind(await tokenHash(env, token), userID, expiresAt, timestamp()).run();
  return { user: publicUser(user), token, expires_at: expiresAt };
}

async function upsertUser(env: Env, email: string, provider: "google" | "email", profile?: { sub: string; name?: string; picture?: string }) {
  const at = timestamp();
  const existing = await env.DB.prepare("SELECT id,google_id FROM app_users WHERE email=?")
    .bind(email).first<{ id: number; google_id: string | null }>();
  if (existing?.google_id && profile && existing.google_id !== profile.sub) throw new Error("Google account mismatch");
  if (existing) {
    await env.DB.prepare(`UPDATE app_users SET google_id=COALESCE(google_id,?), name=COALESCE(?,name),
      avatar_url=COALESCE(?,avatar_url),updated_at=?,last_login_at=? WHERE id=?`)
      .bind(profile?.sub || null, profile?.name || null, profile?.picture || null, at, at, existing.id).run();
    return existing.id;
  }
  const inserted = await env.DB.prepare(`INSERT INTO app_users(email,google_id,name,avatar_url,auth_provider,created_at,updated_at,last_login_at)
    VALUES(?,?,?,?,?,?,?,?) RETURNING id`)
    .bind(email, profile?.sub || null, profile?.name || null, profile?.picture || null, provider, at, at, at)
    .first<{ id: number }>();
  if (!inserted) throw new Error("User creation failed");
  return inserted.id;
}

function nativeRedirect(params: Record<string, string>) {
  const url = new URL("glance://auth/callback");
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  return Response.redirect(url.toString(), 302);
}

async function googleStart(env: Env) {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET) return error("auth_not_configured", "Google sign-in is not configured.", 503);
  const state = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  await env.DB.prepare("INSERT INTO app_oauth_states(state_hash,expires_at) VALUES(?,?)")
    .bind(await hash(state), expiry(5)).run();
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", env.GOOGLE_CLIENT_ID);
  url.searchParams.set("redirect_uri", `${env.PUBLIC_ORIGIN}/auth/google/callback`);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", "openid email profile");
  url.searchParams.set("state", state);
  url.searchParams.set("prompt", "select_account");
  return Response.redirect(url.toString(), 302);
}

async function googleCallback(env: Env, request: Request) {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") || "";
  const consumed = await env.DB.prepare("DELETE FROM app_oauth_states WHERE state_hash=? AND expires_at>? RETURNING state_hash")
    .bind(await hash(state), timestamp()).first();
  if (!consumed) return nativeRedirect({ error: "Sign-in expired. Please try again." });
  const code = url.searchParams.get("code");
  if (!code) return nativeRedirect({ error: "Google sign-in was cancelled." });
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ code, client_id: env.GOOGLE_CLIENT_ID!, client_secret: env.GOOGLE_CLIENT_SECRET!,
      redirect_uri: `${env.PUBLIC_ORIGIN}/auth/google/callback`, grant_type: "authorization_code" })
  });
  if (!response.ok) return nativeRedirect({ error: "Google sign-in failed." });
  const tokens = await response.json() as { access_token?: string };
  if (!tokens.access_token) return nativeRedirect({ error: "Google sign-in failed." });
  const profileResponse = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
    headers: { Authorization: `Bearer ${tokens.access_token}` }
  });
  if (!profileResponse.ok) return nativeRedirect({ error: "Google profile could not be read." });
  const profile = await profileResponse.json() as { sub?: string; email?: string; email_verified?: boolean; name?: string; picture?: string };
  if (!profile.sub || !profile.email || !profile.email_verified) return nativeRedirect({ error: "A verified Google email is required." });
  const userID = await upsertUser(env, profile.email, "google", { sub: profile.sub, name: profile.name, picture: profile.picture });
  const nativeCode = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  await env.DB.prepare("INSERT INTO app_auth_codes(code_hash,user_id,expires_at) VALUES(?,?,?)")
    .bind(await hash(nativeCode), userID, expiry(1)).run();
  return nativeRedirect({ code: nativeCode });
}

async function sendEmailCode(env: Env, request: Request) {
  if (!env.RESEND_API_KEY || !env.AUTH_EMAIL_FROM) return error("email_not_configured", "Email sign-in is not configured.", 503);
  const body = await readSmallJSON(request);
  if (!body) return error("invalid_json", "A JSON object is required.", 400);
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return error("invalid_email", "Enter a valid email address.", 400);
  const previous = await env.DB.prepare("SELECT sent_at FROM app_email_codes WHERE email=?").bind(email).first<{ sent_at: string }>();
  if (previous && Date.now() - Date.parse(previous.sent_at) < 60_000) return error("rate_limited", "Wait a minute before requesting another code.", 429);
  const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
  const expiresAt = expiry(10);
  const sentAt = timestamp();
  await env.DB.prepare(`INSERT INTO app_email_codes(email,code_hash,expires_at,attempts,sent_at) VALUES(?,?,?,?,?)
    ON CONFLICT(email) DO UPDATE SET code_hash=excluded.code_hash,expires_at=excluded.expires_at,attempts=0,sent_at=excluded.sent_at`)
    .bind(email, await hash(`${env.SESSION_SECRET}:${email}:${code}`), expiresAt, 0, sentAt).run();
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: env.AUTH_EMAIL_FROM, to: [email], subject: "Glance sign-in code", text: `Your Glance sign-in code is ${code}. It expires in 10 minutes.` })
  });
  if (!response.ok) {
    await env.DB.prepare("DELETE FROM app_email_codes WHERE email=? AND sent_at=?").bind(email, sentAt).run();
    return error("email_delivery_failed", "Could not send the sign-in code.", 502);
  }
  return respond({ email, expires_at: expiresAt });
}

async function verifyEmailCode(env: Env, request: Request) {
  const body = await readSmallJSON(request);
  if (!body) return error("invalid_json", "A JSON object is required.", 400);
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const code = typeof body.code === "string" ? body.code.trim() : "";
  if (!/^[0-9]{6}$/.test(code) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return error("invalid_code", "Invalid or expired code.", 401);
  const row = await env.DB.prepare("SELECT code_hash,attempts FROM app_email_codes WHERE email=? AND expires_at>?")
    .bind(email, timestamp()).first<{ code_hash: string; attempts: number }>();
  if (!row || row.attempts >= 5) return error("invalid_code", "Invalid or expired code.", 401);
  if (row.code_hash !== await hash(`${env.SESSION_SECRET}:${email}:${code}`)) {
    await env.DB.prepare("UPDATE app_email_codes SET attempts=attempts+1 WHERE email=?").bind(email).run();
    return error("invalid_code", "Invalid or expired code.", 401);
  }
  const deleted = await env.DB.prepare("DELETE FROM app_email_codes WHERE email=? AND code_hash=? RETURNING email")
    .bind(email, row.code_hash).first();
  if (!deleted) return error("invalid_code", "Invalid or expired code.", 401);
  const userID = await upsertUser(env, email, "email");
  return respond(await issueSession(env, userID));
}

export async function handleAuthRoute(env: Env, request: Request): Promise<Response | null> {
  const path = new URL(request.url).pathname;
  if (request.method === "GET" && path === "/auth/google") return googleStart(env);
  if (request.method === "GET" && path === "/auth/google/callback") return googleCallback(env, request);
  if (request.method === "POST" && path === "/auth/email/send-code") return sendEmailCode(env, request);
  if (request.method === "POST" && path === "/auth/email/verify-code") return verifyEmailCode(env, request);
  if (request.method === "POST" && path === "/auth/native/exchange") {
    const body = await readSmallJSON(request);
    if (!body) return error("invalid_json", "A JSON object is required.", 400);
    const code = typeof body.code === "string" ? body.code : "";
    const consumed = await env.DB.prepare("DELETE FROM app_auth_codes WHERE code_hash=? AND expires_at>? RETURNING user_id")
      .bind(await hash(code), timestamp()).first<{ user_id: number }>();
    return consumed ? respond(await issueSession(env, consumed.user_id)) : error("invalid_code", "Sign-in code expired.", 401);
  }
  if (request.method === "GET" && path === "/auth/me") return respond(publicUser(await requireAppUser(env, request)));
  if (request.method === "POST" && path === "/auth/logout") {
    await requireAppUser(env, request);
    await env.DB.prepare("DELETE FROM app_sessions WHERE token_hash=?").bind(await tokenHash(env, authToken(request))).run();
    return respond({ logged_out: true });
  }
  return null;
}
