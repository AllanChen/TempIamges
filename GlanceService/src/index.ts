import { OFFICIAL_MANIFESTS } from "./official";

export interface Env {
  DB: D1Database;
  BUCKET: R2Bucket;
  PUBLIC_ORIGIN: string;
  SESSION_SECRET: string;
  ADMIN_TOKEN: string;
  FLOW_TEST_TOKEN?: string;
  DEVELOPER_TEST_TOKEN?: string;
  ADMIN_USERNAME: string;
  ADMIN_PASSWORD: string;
  ADMIN_PATH: string;
  WORKER_TOKEN_PEPPER: string;
  MEDIA_SIGNING_SECRET: string;
  WORKER_AUTH_DISABLED?: string;
  ASSETS: Fetcher;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  GLANCE_SIGNING_KEY_PKCS8?: string;
}

type Manifest = {
  schemaVersion?: number; id?: string; version?: string; name?: string; summary?: string;
  author?: string; iconURL?: string; official?: boolean; execution?: { mode?: string };
  commands?: Array<{ id?: string; name?: string; description?: string; inputTypes?: string[]; inputMimeTypes?: string[]; outputs?: string[]; taskType?: string; requiresUpload?: boolean; parameterSchema?: unknown }>;
  privacy?: { uploadsMedia?: boolean; notice?: string };
  minimumGlanceVersion?: string; updatedAt?: string;
  signature?: { algorithm: string; keyID: string; value: string };
};

const MAX_BODY = 2 * 1024 * 1024;
const MAX_ASSET = 50 * 1024 * 1024;
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Widget-Id, X-Task-Claim",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  Vary: "Origin"
};

function json(data: unknown, status = 200, extra: HeadersInit = {}) {
  return new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json", ...extra } });
}
function ok(result: unknown, status = 200, extra: HeadersInit = {}) { return json({ success: true, result }, status, extra); }
function fail(code: string, message: string, status = 400) { return json({ success: false, error: { code, message } }, status); }
function now() { return new Date().toISOString(); }
function id(prefix: string) { return `${prefix}_${crypto.randomUUID()}`; }
function bearer(request: Request) { const value = request.headers.get("Authorization") || ""; return value.startsWith("Bearer ") ? value.slice(7).trim() : ""; }
function pathParts(url: URL) { return url.pathname.split("/").filter(Boolean); }
function countryName(code: unknown) {
  if (typeof code !== "string" || !/^[A-Z]{2}$/.test(code) || code === "XX") return null;
  return new Intl.DisplayNames(["en"], { type: "region" }).of(code) || null;
}
function requestCountry(request: Request) {
  return countryName(request.cf?.country) || "Unknown";
}

async function digest(value: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function tokenHash(env: Env, token: string) { return digest(`${env.WORKER_TOKEN_PEPPER}:${token}`); }
async function developerSession(env: Env, request: Request) {
  const token = bearer(request);
  if (!token) throw new Error("Unauthorized");
  if (env.DEVELOPER_TEST_TOKEN && token === env.DEVELOPER_TEST_TOKEN) {
    return { owner_id: "mock:glance-cli", email: "mock@glance.local",
      expires_at: new Date(Date.now() + 30 * 24 * 60 * 60_000).toISOString() };
  }
  const row = await env.DB.prepare("SELECT owner_id,email,expires_at FROM developer_sessions WHERE token_hash=? AND expires_at>?")
    .bind(await digest(token), now()).first<{ owner_id: string; email: string; expires_at: string }>();
  if (!row) throw new Error("Unauthorized");
  return row;
}
async function developerAuthStart(env: Env, request: Request) {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET) return fail("auth_not_configured", "Google sign-in is not configured.", 503);
  const url = new URL(request.url);
  const redirect = url.searchParams.get("redirect_uri") || "";
  const state = url.searchParams.get("state") || "";
  const challenge = url.searchParams.get("code_challenge") || "";
  let parsed: URL;
  try { parsed = new URL(redirect); } catch { return fail("invalid_redirect", "Invalid callback URL."); }
  if (parsed.protocol !== "http:" || parsed.hostname !== "127.0.0.1" || parsed.pathname !== "/callback" || !parsed.port ||
      !/^[A-Za-z0-9_-]{24,128}$/.test(state) || !/^[A-Za-z0-9_-]{43,128}$/.test(challenge)) {
    return fail("invalid_login", "Invalid CLI login request.");
  }
  const oauthState = crypto.randomUUID() + crypto.randomUUID();
  await env.DB.prepare("INSERT INTO developer_oauth_states (state_hash,client_state,code_challenge,redirect_uri,expires_at) VALUES (?,?,?,?,?)")
    .bind(await digest(oauthState), state, challenge, redirect, new Date(Date.now() + 5 * 60_000).toISOString()).run();
  const google = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  google.searchParams.set("client_id", env.GOOGLE_CLIENT_ID);
  google.searchParams.set("redirect_uri", `${env.PUBLIC_ORIGIN}/api/v2/developer/auth/google/callback`);
  google.searchParams.set("response_type", "code");
  google.searchParams.set("scope", "openid email profile");
  google.searchParams.set("state", oauthState);
  google.searchParams.set("prompt", "select_account");
  return Response.redirect(google.toString(), 302);
}
async function developerGoogleCallback(env: Env, request: Request) {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") || "";
  const record = await env.DB.prepare("SELECT client_state,code_challenge,redirect_uri FROM developer_oauth_states WHERE state_hash=? AND expires_at>?")
    .bind(await digest(state), now()).first<{ client_state: string; code_challenge: string; redirect_uri: string }>();
  if (!record) return fail("invalid_state", "Login state expired.", 400);
  await env.DB.prepare("DELETE FROM developer_oauth_states WHERE state_hash=?").bind(await digest(state)).run();
  const redirect = new URL(record.redirect_uri);
  redirect.searchParams.set("state", record.client_state);
  const code = url.searchParams.get("code");
  if (!code) {
    redirect.searchParams.set("error", "Google sign-in was cancelled.");
    return Response.redirect(redirect.toString(), 302);
  }
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ code, client_id: env.GOOGLE_CLIENT_ID!, client_secret: env.GOOGLE_CLIENT_SECRET!,
      redirect_uri: `${env.PUBLIC_ORIGIN}/api/v2/developer/auth/google/callback`, grant_type: "authorization_code" })
  });
  if (!tokenResponse.ok) return fail("google_exchange_failed", "Could not complete Google sign-in.", 502);
  const tokens = await tokenResponse.json() as { access_token?: string };
  const userResponse = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
    headers: { Authorization: `Bearer ${tokens.access_token || ""}` }
  });
  if (!userResponse.ok) return fail("google_profile_failed", "Could not read Google profile.", 502);
  const user = await userResponse.json() as { sub?: string; email?: string; email_verified?: boolean };
  if (!user.sub || !user.email || !user.email_verified) return fail("unverified_email", "A verified Google email is required.", 403);
  const cliCode = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  await env.DB.prepare("INSERT INTO developer_auth_codes (code_hash,owner_id,email,code_challenge,expires_at) VALUES (?,?,?,?,?)")
    .bind(await digest(cliCode), `google:${user.sub}`, user.email, record.code_challenge,
      new Date(Date.now() + 60_000).toISOString()).run();
  redirect.searchParams.set("code", cliCode);
  return Response.redirect(redirect.toString(), 302);
}
async function developerExchange(env: Env, request: Request) {
  const body = await readJSON(request);
  const code = typeof body.code === "string" ? body.code : "";
  const verifier = typeof body.code_verifier === "string" ? body.code_verifier : "";
  const row = await env.DB.prepare("SELECT owner_id,email,code_challenge FROM developer_auth_codes WHERE code_hash=? AND expires_at>?")
    .bind(await digest(code), now()).first<{ owner_id: string; email: string; code_challenge: string }>();
  if (!row) return fail("invalid_code", "Login code expired.", 401);
  const verifierHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  const challenge = btoa(String.fromCharCode(...new Uint8Array(verifierHash))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  if (challenge !== row.code_challenge) return fail("invalid_verifier", "Login verifier does not match.", 401);
  await env.DB.prepare("DELETE FROM developer_auth_codes WHERE code_hash=?").bind(await digest(code)).run();
  const token = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60_000).toISOString();
  await env.DB.prepare("INSERT INTO developer_sessions(token_hash,owner_id,email,expires_at,created_at) VALUES(?,?,?,?,?)")
    .bind(await digest(token), row.owner_id, row.email, expiresAt, now()).run();
  return ok({ token, email: row.email, expiresAt }, 200, { "Cache-Control": "no-store" });
}
function isFlowTestToken(env: Env, token: string) { return !!token && !!env.FLOW_TEST_TOKEN && token === env.FLOW_TEST_TOKEN; }
function isFlowTestWorkerToken(env: Env, token: string) {
  return String(env.WORKER_AUTH_DISABLED || "").toLowerCase() === "true" && isFlowTestToken(env, token);
}
async function hmac(env: Env, value: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.MEDIA_SIGNING_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function sessionSignature(env: Env, value: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.SESSION_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function signedAssetURL(env: Env, request: Request, assetID: string, ttlSeconds = 3600) {
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  const sig = await hmac(env, `${assetID}.${exp}`);
  const url = new URL(`/api/v2/assets/${assetID}`, request.url);
  url.searchParams.set("exp", String(exp)); url.searchParams.set("sig", sig);
  return url.toString();
}
async function validAssetSignature(env: Env, assetID: string, exp: string, sig: string) {
  if (!/^\d+$/.test(exp) || Number(exp) < Math.floor(Date.now() / 1000) || !/^[a-f0-9]{64}$/.test(sig)) return false;
  const expected = await hmac(env, `${assetID}.${exp}`);
  return expected === sig;
}
async function requireUser(request: Request, env?: Env) {
  const token = bearer(request);
  if (!token) throw new Error("Unauthorized");
  return `user_${await digest(token)}`;
}
async function requireAdmin(env: Env, request: Request) {
  if (env.DEVELOPER_TEST_TOKEN && bearer(request) === env.DEVELOPER_TEST_TOKEN) throw new Error("Unauthorized");
  if (env.ADMIN_TOKEN && bearer(request) === env.ADMIN_TOKEN) return;
  const cookie = request.headers.get("Cookie") || "";
  const token = cookie.match(/(?:^|;\s*)glance_admin_session=([^;]+)/)?.[1] || "";
  const [payload, signature] = token.split(".");
  if (!payload || !signature || !/^\d+$/.test(payload.split(":")[1] || "")) throw new Error("Unauthorized");
  const expected = await sessionSignature(env, payload);
  if (signature !== expected) throw new Error("Unauthorized");
  const [username, expires] = payload.split(":");
  if (!username || Number(expires) < Math.floor(Date.now() / 1000)) throw new Error("Unauthorized");
}

async function adminLogin(env: Env, request: Request) {
  if (!env.ADMIN_USERNAME || !env.ADMIN_PASSWORD || !env.SESSION_SECRET) return fail("admin_not_configured", "Admin credentials are not configured.", 503);
  const body = await readJSON(request);
  const username = typeof body.username === "string" ? body.username : "";
  const password = typeof body.password === "string" ? body.password : "";
  const supplied = await digest(`${username}:${password}`);
  const expected = await digest(`${env.ADMIN_USERNAME}:${env.ADMIN_PASSWORD}`);
  if (supplied !== expected) return fail("invalid_credentials", "Invalid username or password.", 401);
  const payload = `${username}:${Math.floor(Date.now() / 1000) + 8 * 60 * 60}`;
  const session = `${payload}.${await sessionSignature(env, payload)}`;
  return ok({ username }, 200, {
    "Set-Cookie": `glance_admin_session=${session}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=28800`,
    "Cache-Control": "no-store"
  });
}
async function adminMe(env: Env, request: Request) {
  await requireAdmin(env, request);
  return ok({ authenticated: true }, 200, { "Cache-Control": "no-store" });
}
function adminLogout() {
  return ok({ loggedOut: true }, 200, { "Set-Cookie": "glance_admin_session=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0", "Cache-Control": "no-store" });
}
async function adminOverview(env: Env, request: Request) {
  await requireAdmin(env, request);
  const [tasks, widgets, workers] = await Promise.all([
    env.DB.prepare("SELECT status, COUNT(*) AS count FROM widget_tasks GROUP BY status").all<{ status: string; count: number }>(),
    env.DB.prepare("SELECT status, COUNT(*) AS count FROM widget_versions GROUP BY status").all<{ status: string; count: number }>(),
    env.DB.prepare("SELECT status, COUNT(*) AS count FROM widget_workers GROUP BY status").all<{ status: string; count: number }>()
  ]);
  return ok({ tasks: tasks.results, widgets: widgets.results, workers: workers.results }, 200, { "Cache-Control": "no-store" });
}
async function adminTasks(env: Env, request: Request) {
  await requireAdmin(env, request);
  const rows = await env.DB.prepare("SELECT t.id,t.widget_id,t.version_id,t.command_id,t.owner_id,t.type,t.status,t.worker_id,t.attempts,t.error_code,t.input_json,t.result_json,t.created_at,t.claimed_at,t.completed_at,w.name AS widget_name,v.version FROM widget_tasks t LEFT JOIN widgets w ON w.id=t.widget_id LEFT JOIN widget_versions v ON v.id=t.version_id ORDER BY t.created_at DESC LIMIT 100").all<Record<string, unknown>>();
  return ok(await Promise.all(rows.results.map(async (row) => ({ ...row,
    input: row.input_json ? JSON.parse(String(row.input_json)) : null,
    result: row.result_json ? await publicTaskArtifacts(env, request, JSON.parse(String(row.result_json))) : null,
    input_json: undefined, result_json: undefined }))), 200, { "Cache-Control": "no-store" });
}
async function adminWidgets(env: Env, request: Request) {
  await requireAdmin(env, request);
  const rows = await env.DB.prepare("SELECT v.id AS version_id,v.widget_id,v.version,v.status,v.manifest_json,v.created_at,v.updated_at,w.name,w.author,w.owner_id FROM widget_versions v JOIN widgets w ON w.id=v.widget_id ORDER BY v.updated_at DESC LIMIT 100").all<Record<string, unknown>>();
  return ok(rows.results.map((row) => ({ ...row, manifest: JSON.parse(String(row.manifest_json)), manifest_json: undefined })), 200, { "Cache-Control": "no-store" });
}

async function adminAllWidgets(env: Env, request: Request) {
  await requireAdmin(env, request);
  await ensureOfficialWidgets(env);
  const rows = await env.DB.prepare(
    "SELECT w.id AS widget_id,w.name,w.summary,w.author,w.icon_url,w.current_version,w.status,w.created_at,w.updated_at,v.id AS version_id,v.manifest_json,v.status AS version_status FROM widgets w LEFT JOIN widget_versions v ON v.widget_id=w.id AND v.version=w.current_version ORDER BY w.updated_at DESC"
  ).all<Record<string, unknown>>();
  return ok({ widgets: rows.results.map((row) => ({
    widgetId: row.widget_id,
    name: row.name,
    summary: row.summary,
    author: row.author,
    iconURL: row.icon_url,
    currentVersion: row.current_version,
    status: row.status,
    versionId: row.version_id,
    versionStatus: row.version_status,
    manifest: row.manifest_json ? JSON.parse(String(row.manifest_json)) : null,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  })) }, 200, { "Cache-Control": "no-store" });
}
function validationIssues(manifest: Manifest) {
  const issues: string[] = [];
  if (manifest.schemaVersion !== 1) issues.push("schemaVersion must be 1");
  if (typeof manifest.id !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$/.test(manifest.id)) issues.push("invalid widget id");
  for (const field of ["version", "name", "summary", "author"] as const) if (typeof manifest[field] !== "string" || !manifest[field]?.trim()) issues.push(`${field} is required`);
  if (manifest.execution?.mode !== "cloud") issues.push("execution.mode must be cloud");
  if (!Array.isArray(manifest.commands) || manifest.commands.length === 0) issues.push("at least one command is required");
  const commands = Array.isArray(manifest.commands) ? manifest.commands : [];
  const commandIDs = new Set<string>();
  for (const command of commands) {
    if (!command || typeof command !== "object") { issues.push("invalid command"); continue; }
    if (!command.id || commandIDs.has(command.id)) issues.push(`duplicate or missing command id: ${command.id || "unknown"}`);
    if (command.id) commandIDs.add(command.id);
    if (typeof command.name !== "string" || !command.name.trim() || typeof command.description !== "string" || !command.description.trim()) issues.push(`command ${command.id || "unknown"} needs name and description`);
    if (!Array.isArray(command.inputTypes) || command.inputTypes.length === 0) issues.push(`command ${command.id || "unknown"} needs inputTypes`);
    if (!Array.isArray(command.inputMimeTypes) || command.inputMimeTypes.length === 0) issues.push(`command ${command.id || "unknown"} needs inputMimeTypes`);
    if (!Array.isArray(command.outputs) || command.outputs.length === 0) issues.push(`command ${command.id || "unknown"} needs outputs`);
    if (typeof command.taskType !== "string" || !command.taskType.trim()) issues.push(`command ${command.id || "unknown"} needs taskType`);
    if (typeof command.requiresUpload !== "boolean" || !command.parameterSchema || typeof command.parameterSchema !== "object" || Array.isArray(command.parameterSchema)) issues.push(`command ${command.id || "unknown"} needs requiresUpload and parameterSchema`);
  }
  if (typeof manifest.privacy?.notice !== "string" || !manifest.privacy.notice.trim()) issues.push("privacy.notice is required");
  for (const command of commands) {
    if (!command || typeof command !== "object") continue;
    if (!Array.isArray(command.outputs) || command.outputs.some((value) => !["text", "image", "video", "audio"].includes(value))) issues.push(`command ${command.id || "unknown"} has invalid outputs`);
  }
  return issues;
}
function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>).filter(([, item]) => item !== undefined).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonicalJSON(item)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
async function signDeveloperManifest(env: Env, manifest: Manifest): Promise<Manifest> {
  if (!env.GLANCE_SIGNING_KEY_PKCS8) throw new Error("Signing key is not configured");
  const bytes = Uint8Array.from(atob(env.GLANCE_SIGNING_KEY_PKCS8), (char) => char.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", bytes, "Ed25519", false, ["sign"]);
  const unsigned = { ...manifest, official: false, updatedAt: now() } as Record<string, unknown>;
  delete unsigned.signature;
  const signature = new Uint8Array(await crypto.subtle.sign("Ed25519", key, new TextEncoder().encode(canonicalJSON(unsigned))));
  const encoded = btoa(String.fromCharCode(...signature)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return { ...unsigned, signature: { algorithm: "Ed25519", keyID: "glance-market-2026-02", value: encoded } } as Manifest;
}
function widgetManifestWithID(input: unknown, widgetID: string, existingCommands: Manifest["commands"] = []): Manifest {
  const fields = input && typeof input === "object" && !Array.isArray(input) ? input as Manifest : {};
  const retainedIDs = new Set<string>();
  const commands = Array.isArray(fields.commands) ? fields.commands.map((command, index) => {
    const matching = existingCommands?.find((entry) => entry.id && entry.id === command.id && !retainedIDs.has(entry.id));
    const indexed = existingCommands?.[index];
    const previous = matching || (indexed?.id && !retainedIDs.has(indexed.id) ? indexed : undefined);
    if (previous?.id) retainedIDs.add(previous.id);
    const commandID = previous?.id || crypto.randomUUID();
    return {
      ...command,
      id: commandID,
      taskType: previous?.taskType || `widget.${widgetID}.${commandID}`
    };
  }) : fields.commands;
  return {
    ...fields,
    id: widgetID,
    commands
  };
}
function newWidgetManifest(input: unknown): Manifest {
  return widgetManifestWithID(input, crypto.randomUUID());
}
async function readJSON(request: Request) {
  const length = Number(request.headers.get("content-length") || 0);
  if (length > MAX_BODY) throw new Error("Request body is too large");
  return await request.json() as Record<string, unknown>;
}
async function audit(env: Env, widgetID: string, versionID: string | null, actor: string, action: string, previous: string | null, next: string | null, note: string | null) {
  await env.DB.prepare("INSERT INTO widget_audit_logs (id,widget_id,version_id,actor_id,action,previous_status,next_status,note,created_at) VALUES (?,?,?,?,?,?,?,?,?)")
    .bind(id("audit"), widgetID, versionID, actor, action, previous, next, note, now()).run();
}
function publicManifest(row: { manifest_json: string }) { return JSON.parse(row.manifest_json); }

async function ensureOfficialWidgets(env: Env) {
  const timestamp = now();
  for (const manifest of OFFICIAL_MANIFESTS) {
    const exists = await env.DB.prepare("SELECT id FROM widget_versions WHERE widget_id=? AND version=?").bind(manifest.id, manifest.version).first();
    if (exists) {
      // Keep the catalog manifest in sync when a widget row was migrated from
      // a legacy string ID to its immutable UUID.
      await env.DB.batch([
        env.DB.prepare("UPDATE widget_versions SET manifest_json=?,status='published',updated_at=? WHERE widget_id=? AND version=?")
          .bind(JSON.stringify(manifest), timestamp, manifest.id, manifest.version),
        env.DB.prepare("UPDATE widgets SET name=?,summary=?,author=?,icon_url=?,current_version=?,status='published',updated_at=? WHERE id=?")
          .bind(manifest.name, manifest.summary, manifest.author, manifest.iconURL, manifest.version, timestamp, manifest.id)
      ]);
      continue;
    }
    const versionID = id("version");
    await env.DB.batch([
      env.DB.prepare("INSERT OR IGNORE INTO widgets (id,owner_id,name,summary,author,icon_url,current_version,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)").bind(manifest.id, "glance-official", manifest.name, manifest.summary, manifest.author, manifest.iconURL, manifest.version, "published", timestamp, timestamp),
      env.DB.prepare("INSERT OR IGNORE INTO widget_versions (id,widget_id,version,manifest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)").bind(versionID, manifest.id, manifest.version, JSON.stringify(manifest), "published", timestamp, timestamp)
    ]);
  }
}

/// Admin-side widget creation: same manifest validation and storage shape as
/// the client submission flow, but authorized by the Ops Console session and
/// allowing the admin to choose the initial lifecycle status.
async function adminCreateWidget(env: Env, request: Request) {
  await requireAdmin(env, request);
  const body = await readJSON(request);
  const manifest = newWidgetManifest(body.manifest);
  const issues = validationIssues(manifest);
  if (issues.length) return fail("invalid_manifest", issues.join("; "), 422);
  // Widgets created from the authenticated Admin Console are part of the
  // trusted Glance catalog. Third-party manifests use the signed submission API.
  const storedManifest = { ...manifest, official: true };
  const widgetID = manifest.id!;
  const status = body.status === "gray_release" ? "gray_release" : body.status === "published" ? "published" : "manual_review";
  const versionID = id("version");
  const workerID = id("worker");
  const workerToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const timestamp = now();
  try {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO widgets (id,owner_id,name,summary,author,icon_url,current_version,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)").bind(widgetID, "admin", manifest.name, manifest.summary, manifest.author, manifest.iconURL || null, manifest.version, status, timestamp, timestamp),
      env.DB.prepare("INSERT INTO widget_versions (id,widget_id,version,manifest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)").bind(versionID, widgetID, manifest.version, JSON.stringify(storedManifest), status, timestamp, timestamp),
      env.DB.prepare("INSERT INTO widget_workers (id,widget_id,owner_id,token_hash,status,created_at) VALUES (?,?,?,?,?,?)").bind(workerID, widgetID, "admin", await tokenHash(env, workerToken), "active", timestamp),
      env.DB.prepare("INSERT INTO widget_audit_logs (id,widget_id,version_id,actor_id,action,previous_status,next_status,note,created_at) VALUES (?,?,?,?,?,?,?,?,?)").bind(id("audit"), widgetID, versionID, "admin", "admin_create", null, status, typeof body.note === "string" ? body.note : null, timestamp)
    ]);
  } catch (error) {
    const message = error instanceof Error && error.message.includes("UNIQUE")
      ? "Widget version already exists."
      : "Unable to create Widget.";
    return fail("create_failed", message, 409);
  }
  return ok({ widgetId: widgetID, commandIds: manifest.commands?.map((command) => command.id), versionId: versionID, version: manifest.version, workerToken, status }, 201, { "Cache-Control": "no-store" });
}

async function adminUpdateWidget(env: Env, request: Request, widgetID: string) {
  await requireAdmin(env, request);
  const body = await readJSON(request);
  const existing = await env.DB.prepare("SELECT id,current_version,status FROM widgets WHERE id=?")
    .bind(widgetID).first<{ id: string; current_version: string; status: string }>();
  if (!existing) return fail("widget_not_found", "Widget not found.", 404);
  const current = await env.DB.prepare("SELECT id,manifest_json FROM widget_versions WHERE widget_id=? AND version=?")
    .bind(widgetID, existing.current_version).first<{ id: string; manifest_json: string }>();
  if (!current) return fail("version_missing", "Current Widget version is missing.", 409);
  const previousManifest = JSON.parse(current.manifest_json) as Manifest;
  const manifest = widgetManifestWithID(body.manifest, widgetID, previousManifest.commands);
  const issues = validationIssues(manifest);
  if (issues.length) return fail("invalid_manifest", issues.join("; "), 422);

  const status = body.status === "gray_release" ? "gray_release"
    : body.status === "published" ? "published"
    : body.status === "rejected" ? "rejected"
    : body.status === "suspended" ? "suspended"
    : "manual_review";
  const storedManifest = { ...manifest, official: true };
  const timestamp = now();
  let versionID: string;
  try {
    if (manifest.version === existing.current_version) {
      versionID = current.id;
      await env.DB.batch([
        env.DB.prepare("UPDATE widgets SET name=?,summary=?,author=?,icon_url=?,status=?,updated_at=? WHERE id=?")
          .bind(manifest.name, manifest.summary, manifest.author, manifest.iconURL || null, status, timestamp, widgetID),
        env.DB.prepare("UPDATE widget_versions SET manifest_json=?,status=?,updated_at=? WHERE id=?")
          .bind(JSON.stringify(storedManifest), status, timestamp, versionID),
        env.DB.prepare("INSERT INTO widget_audit_logs (id,widget_id,version_id,actor_id,action,previous_status,next_status,note,created_at) VALUES (?,?,?,?,?,?,?,?,?)")
          .bind(id("audit"), widgetID, versionID, "admin", "admin_edit", existing.status, status, typeof body.note === "string" ? body.note : null, timestamp)
      ]);
    } else {
      versionID = id("version");
      await env.DB.batch([
        env.DB.prepare("UPDATE widgets SET name=?,summary=?,author=?,icon_url=?,current_version=?,status=?,updated_at=? WHERE id=?")
          .bind(manifest.name, manifest.summary, manifest.author, manifest.iconURL || null, manifest.version, status, timestamp, widgetID),
        env.DB.prepare("INSERT INTO widget_versions (id,widget_id,version,manifest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)")
          .bind(versionID, widgetID, manifest.version, JSON.stringify(storedManifest), status, timestamp, timestamp),
        env.DB.prepare("INSERT INTO widget_audit_logs (id,widget_id,version_id,actor_id,action,previous_status,next_status,note,created_at) VALUES (?,?,?,?,?,?,?,?,?)")
          .bind(id("audit"), widgetID, versionID, "admin", "admin_new_version", existing.status, status, typeof body.note === "string" ? body.note : null, timestamp)
      ]);
    }
  } catch (error) {
    const message = error instanceof Error && error.message.includes("UNIQUE")
      ? "Widget version already exists."
      : "Unable to update Widget.";
    return fail("update_failed", message, 409);
  }
  return ok({ widgetId: widgetID, commandIds: manifest.commands?.map((command) => command.id), versionId: versionID, version: manifest.version, status }, 200, { "Cache-Control": "no-store" });
}

async function createSubmission(env: Env, request: Request) {
  const owner = (await developerSession(env, request)).owner_id;
  const body = await readJSON(request);
  const input = body.manifest && typeof body.manifest === "object" && !Array.isArray(body.manifest) ? body.manifest as Manifest : {};
  const manifest = { ...input, official: false, updatedAt: now() };
  const issues = validationIssues(manifest);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(manifest.id || "")) issues.push("developer Widget ID must be a UUID");
  if (!manifest.minimumGlanceVersion) issues.push("minimumGlanceVersion is required");
  if (issues.length) return fail("invalid_manifest", issues.join("; "), 422);
  const widgetID = manifest.id!;
  const versionID = id("version");
  const timestamp = now();
  const existing = await env.DB.prepare("SELECT owner_id,status FROM widgets WHERE id=?").bind(widgetID).first<{ owner_id: string; status: string }>();
  if (existing && existing.owner_id !== owner) return fail("widget_owned", "This Widget ID belongs to another developer.", 403);
  if (existing?.status === "archived") return fail("widget_archived", "Archived Widgets cannot accept versions.", 409);
  try {
    await env.DB.batch([
      ...(existing ? [] : [env.DB.prepare("INSERT INTO widgets (id,owner_id,name,summary,author,icon_url,current_version,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)")
        .bind(widgetID, owner, manifest.name, manifest.summary, manifest.author, manifest.iconURL || null, manifest.version, "manual_review", timestamp, timestamp)]),
      ...(existing?.status === "suspended" ? [env.DB.prepare("UPDATE widgets SET status='manual_review',updated_at=? WHERE id=? AND owner_id=?")
        .bind(timestamp, widgetID, owner)] : []),
      env.DB.prepare("INSERT INTO widget_versions (id,widget_id,version,manifest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)").bind(versionID, widgetID, manifest.version, JSON.stringify(manifest), "manual_review", timestamp, timestamp),
      env.DB.prepare("INSERT INTO widget_audit_logs (id,widget_id,version_id,actor_id,action,previous_status,next_status,note,created_at) VALUES (?,?,?,?,?,?,?,?,?)").bind(id("audit"), widgetID, versionID, owner, "submit", null, "manual_review", null, timestamp)
    ]);
  } catch (error) {
    const message = error instanceof Error && error.message.includes("UNIQUE") ? "Widget version already exists." : "Unable to save submission.";
    return fail("submission_failed", message, 409);
  }
  return ok({ submissionId: versionID, widgetId: widgetID, commandIds: manifest.commands?.map((command) => command.id), version: manifest.version, status: "manual_review" }, 201, { "Cache-Control": "no-store" });
}

async function developerWidget(env: Env, request: Request, widgetID: string) {
  const owner = (await developerSession(env, request)).owner_id;
  const widget = await env.DB.prepare(`SELECT id,name,current_version,status FROM widgets WHERE id=? AND
    (owner_id=? OR EXISTS (SELECT 1 FROM widget_worker_grants WHERE widget_id=widgets.id AND developer_id=?))`)
    .bind(widgetID, owner, owner).first<{ id: string; name: string; current_version: string; status: string }>();
  if (!widget) return fail("widget_not_found", "Widget not found.", 404);
  const versions = await env.DB.prepare("SELECT id,version,status,created_at,updated_at FROM widget_versions WHERE widget_id=? ORDER BY created_at DESC")
    .bind(widgetID).all();
  return ok({ widgetId: widget.id, name: widget.name, currentVersion: widget.current_version,
    status: widget.status, versions: versions.results }, 200, { "Cache-Control": "no-store" });
}

async function developerWidgetAction(env: Env, request: Request, widgetID: string, action: string) {
  const owner = (await developerSession(env, request)).owner_id;
  const widget = await env.DB.prepare("SELECT current_version,status FROM widgets WHERE id=? AND owner_id=?")
    .bind(widgetID, owner).first<{ current_version: string; status: string }>();
  if (!widget) return fail("widget_not_found", "Widget not found.", 404);
  const status = action === "unpublish" ? "suspended" : action === "archive" ? "archived" : null;
  if (!status) return fail("unknown_action", "Unknown developer action.", 400);
  if (widget.status === "archived") return fail("widget_archived", "Archived Widgets cannot be changed.", 409);
  await env.DB.batch([
    env.DB.prepare("UPDATE widgets SET status=?,updated_at=? WHERE id=? AND owner_id=?").bind(status, now(), widgetID, owner),
    env.DB.prepare("INSERT INTO widget_audit_logs(id,widget_id,version_id,actor_id,action,previous_status,next_status,note,created_at) VALUES(?,?,?,?,?,?,?,?,?)")
      .bind(id("audit"), widgetID, null, owner, action, widget.status, status, null, now())
  ]);
  return ok({ widgetId: widgetID, status }, 200, { "Cache-Control": "no-store" });
}

async function listWidgets(env: Env) {
  await ensureOfficialWidgets(env);
  const rows = await env.DB.prepare("SELECT v.manifest_json FROM widget_versions v JOIN widgets w ON w.id=v.widget_id AND w.current_version=v.version WHERE w.status='published' AND v.status='published' ORDER BY v.updated_at DESC").all<{ manifest_json: string }>();
  return ok({ widgets: rows.results.map(publicManifest), pagination: { page: 1, limit: rows.results.length, total: rows.results.length, totalPages: rows.results.length ? 1 : 0 } }, 200, { "Cache-Control": "public, max-age=60" });
}

async function widgetDetail(env: Env, widgetID: string) {
  await ensureOfficialWidgets(env);
  const row = await env.DB.prepare("SELECT v.manifest_json FROM widget_versions v JOIN widgets w ON w.id=v.widget_id AND w.current_version=v.version WHERE v.widget_id=? AND w.status='published' AND v.status='published' LIMIT 1").bind(widgetID).first<{ manifest_json: string }>();
  return row ? ok(publicManifest(row), 200, { "Cache-Control": "public, max-age=60" }) : fail("widget_not_found", "Widget not found.", 404);
}

async function taskStatus(env: Env, request: Request, taskID: string) {
  const actor = await requireUser(request, env);
  const row = isFlowTestToken(env, bearer(request))
    ? await env.DB.prepare("SELECT id,owner_id,status,result_json,error_code,attempts FROM widget_tasks WHERE id=?").bind(taskID).first<Record<string, unknown>>()
    : await env.DB.prepare("SELECT id,owner_id,status,result_json,error_code,attempts FROM widget_tasks WHERE id=? AND owner_id=?").bind(taskID, actor).first<Record<string, unknown>>();
  if (!row) return fail("task_not_found", "Task not found.", 404);
  const result: Record<string, unknown> = { taskID: row.id, status: row.status === "succeeded" ? "completed" : row.status, processCount: row.status === "succeeded" ? 100 : 0, attempts: row.attempts };
  if (row.result_json) {
    const artifacts = await publicTaskArtifacts(env, request, JSON.parse(String(row.result_json)));
    result.result = artifacts;
    if (Array.isArray(artifacts) && typeof artifacts[0]?.url === "string") result.resultURL = artifacts[0].url;
  }
  if (row.error_code) result.error = row.error_code;
  return ok(result, 200, { "Cache-Control": "no-store" });
}

const GLANCE_CONFIG_SETTING = "glance_config";

function isChinaLocation(location: unknown) {
  return typeof location === "string" && ["CN", "CHINA"].includes(location.trim().toUpperCase());
}

async function readGlanceConfig(env: Env): Promise<Record<string, unknown> & { locationBasedUpload: boolean }> {
  const row = await env.DB.prepare("SELECT value FROM service_settings WHERE key=?")
    .bind(GLANCE_CONFIG_SETTING).first<{ value: string }>();
  if (row) {
    try {
      const value = JSON.parse(row.value) as unknown;
      if (value && typeof value === "object" && !Array.isArray(value) &&
          typeof (value as Record<string, unknown>).locationBasedUpload === "boolean") {
        return value as Record<string, unknown> & { locationBasedUpload: boolean };
      }
    } catch { /* Invalid stored config falls back to the legacy setting. */ }
  }
  const legacy = await env.DB.prepare("SELECT value FROM service_settings WHERE key='location_upload_routing'")
    .first<{ value: string }>();
  return { locationBasedUpload: legacy?.value !== "0" };
}

async function saveGlanceConfig(env: Env, config: Record<string, unknown>) {
  await env.DB.prepare("INSERT INTO service_settings (key,value,updated_at) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at")
    .bind(GLANCE_CONFIG_SETTING, JSON.stringify(config), now()).run();
}

async function glanceConfig(env: Env) {
  return ok(await readGlanceConfig(env), 200, { "Cache-Control": "no-store" });
}

async function adminGlanceConfig(env: Env, request: Request) {
  await requireAdmin(env, request);
  if (request.method === "PUT") {
    const config = await readJSON(request);
    if (!config || typeof config !== "object" || Array.isArray(config) ||
        typeof config.locationBasedUpload !== "boolean") {
      return fail("invalid_config", "glance_config must be a JSON object with a boolean locationBasedUpload field.", 400);
    }
    if (Object.keys(config).length > 100 || new TextEncoder().encode(JSON.stringify(config)).length > 16_384 ||
        ["__proto__", "constructor", "prototype"].some((key) => Object.hasOwn(config, key))) {
      return fail("invalid_config", "glance_config exceeds the limit or contains a reserved field.", 400);
    }
    await saveGlanceConfig(env, config);
  }
  return ok(await readGlanceConfig(env), 200, { "Cache-Control": "no-store" });
}

async function adminUploadSettings(env: Env, request: Request) {
  await requireAdmin(env, request);
  const config = await readGlanceConfig(env);
  if (request.method === "PUT") {
    const body = await readJSON(request);
    if (typeof body.locationBasedUpload !== "boolean") return fail("invalid_setting", "locationBasedUpload must be a boolean.", 400);
    config.locationBasedUpload = body.locationBasedUpload;
    await saveGlanceConfig(env, config);
  }
  return ok({ locationBasedUpload: config.locationBasedUpload },
    200, { "Cache-Control": "no-store" });
}

async function uploadAsset(env: Env, request: Request) {
  const owner = await requireUser(request, env);
  const form = await request.formData();
  const file = form.get("file");
  if (!(file instanceof File)) return fail("file_required", "A media file is required.", 400);
  const allowed = new Set(["image/jpeg", "image/png", "image/webp", "image/gif", "image/heic", "image/heif", "video/mp4", "video/quicktime", "video/webm"]);
  if (!allowed.has(file.type)) return fail("unsupported_media", "Unsupported media type.", 400);
  if (file.size > MAX_ASSET) return fail("file_too_large", "Media must be 50 MB or smaller.", 413);
  const assetID = id("asset"); const key = `glance/${owner}/${assetID}`; const created = now();
  await env.BUCKET.put(key, file.stream(), { httpMetadata: { contentType: file.type, cacheControl: "private, max-age=300" } });
  await env.DB.prepare("INSERT INTO widget_assets (id,owner_id,object_key,mime_type,size_bytes,created_at) VALUES (?,?,?,?,?,?)").bind(assetID, owner, key, file.type, file.size, created).run();
  return ok({ assetID, url: await signedAssetURL(env, request, assetID), provider: "r2" }, 201, { "Cache-Control": "no-store" });
}

async function assetDownload(env: Env, request: Request, assetID: string) {
  const signed = await validAssetSignature(env, assetID, new URL(request.url).searchParams.get("exp") || "", new URL(request.url).searchParams.get("sig") || "");
  const owner = signed || isFlowTestToken(env, bearer(request)) ? null : await requireUser(request, env);
  const row = owner
    ? await env.DB.prepare("SELECT object_key,mime_type FROM widget_assets WHERE id=? AND owner_id=?").bind(assetID, owner).first<{ object_key: string; mime_type: string }>()
    : await env.DB.prepare("SELECT object_key,mime_type FROM widget_assets WHERE id=?").bind(assetID).first<{ object_key: string; mime_type: string }>();
  if (!row) return fail("asset_not_found", "Asset not found.", 404);
  const object = await env.BUCKET.get(row.object_key);
  if (!object) return fail("asset_not_found", "Asset not found.", 404);
  return new Response(object.body, { headers: { ...CORS, "Content-Type": row.mime_type, "Cache-Control": "private, max-age=300" } });
}

async function createTask(env: Env, request: Request, admin = false) {
  const actor = admin ? "admin" : await requireUser(request, env);
  await ensureOfficialWidgets(env);
  const body = await readJSON(request);
  const widgetID = typeof body.widgetID === "string" ? body.widgetID : typeof body.widget_id === "string" ? body.widget_id : "";
  const commandID = typeof body.commandID === "string" ? body.commandID : typeof body.command_id === "string" ? body.command_id : "";
  const widget = await env.DB.prepare("SELECT id,owner_id,current_version,status FROM widgets WHERE id=?").bind(widgetID).first<{ id: string; owner_id: string; current_version: string; status: string }>();
  if (!widget || (!admin && widget.status !== "published")) return fail("widget_unavailable", "Widget is not available.", 404);
  const version = await env.DB.prepare("SELECT id,manifest_json FROM widget_versions WHERE widget_id=? AND version=?").bind(widgetID, widget.current_version).first<{ id: string; manifest_json: string }>();
  if (!version) return fail("version_missing", "Widget version is missing.", 409);
  const manifest = JSON.parse(version.manifest_json) as Manifest;
  const command = manifest.commands?.find((entry) => entry.id === commandID);
  if (!command) return fail("unknown_command", "Unknown Widget command.", 400);
  const taskID = id("task");
  const type = admin ? "review_test" : "production";
  const supplied = body.parameters || body.taskParams;
  const taskParams: Record<string, unknown> = supplied && typeof supplied === "object" && !Array.isArray(supplied)
    ? { ...supplied as Record<string, unknown> } : {};
  if (!("prompt" in taskParams)) taskParams.prompt = "";
  if (!("mask" in taskParams)) taskParams.mask = null;
  taskParams.location = isChinaLocation(taskParams.location) ? "China" : countryName(taskParams.location) || requestCountry(request);
  const input = (body.input && typeof body.input === "object") ? body.input : { url: taskParams.url || body.url || null };
  await env.DB.prepare("INSERT INTO widget_tasks (id,widget_id,version_id,command_id,owner_id,type,input_json,parameters_json,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)")
    .bind(taskID, widgetID, version.id, commandID, admin ? widget.owner_id : actor, type, JSON.stringify(input), JSON.stringify(taskParams), "queued", now()).run();
  return ok({ taskID, status: "queued", processCount: 0, pollAfterMs: 1000 }, 202, { "Cache-Control": "no-store" });
}

async function pullTask(env: Env, request: Request, url: URL) {
  const token = bearer(request);
  const widgetID = url.searchParams.get("widget_id") || "";
  if (!widgetID || !token) return fail("worker_auth_required", "Widget ID and Worker token are required.", 401);
  let workerID = "flow-test-worker";
  if (!isFlowTestWorkerToken(env, token)) {
    const worker = await env.DB.prepare("SELECT id,widget_id FROM widget_workers WHERE widget_id=? AND token_hash=? AND status='active'").bind(widgetID, await tokenHash(env, token)).first<{ id: string; widget_id: string }>();
    if (!worker) return fail("worker_unauthorized", "Worker is not authorized for this Widget.", 403);
    workerID = worker.id;
  }
  const wait = Math.min(25, Math.max(0, Number(url.searchParams.get("wait") || 0)));
  const deadline = Date.now() + wait * 1000;
  let task: Record<string, unknown> | null = null;
  while (!task && Date.now() <= deadline) {
    await env.DB.prepare("UPDATE widget_tasks SET status='queued',worker_id=NULL,lease_expires_at=NULL WHERE widget_id=? AND status IN ('claimed','running') AND lease_expires_at IS NOT NULL AND lease_expires_at<?").bind(widgetID, now()).run();
    const row = await env.DB.prepare("SELECT * FROM widget_tasks WHERE widget_id=? AND status='queued' ORDER BY created_at LIMIT 1").bind(widgetID).first<Record<string, unknown>>();
    if (row) {
      const lease = new Date(Date.now() + 120_000).toISOString();
      const claimed = await env.DB.prepare("UPDATE widget_tasks SET status='claimed',worker_id=?,lease_expires_at=?,claimed_at=?,attempts=attempts+1 WHERE id=? AND status='queued'").bind(workerID, lease, now(), row.id).run();
      if (claimed.meta.changes === 1) {
        await env.DB.prepare("UPDATE widget_workers SET last_seen_at=? WHERE id=?").bind(now(), workerID).run();
        task = { taskId: row.id, widgetId: row.widget_id, versionId: row.version_id, commandId: row.command_id, type: row.type, input: JSON.parse(String(row.input_json)), parameters: JSON.parse(String(row.parameters_json)), leaseExpiresAt: lease };
      }
    }
    if (!task && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return ok({ task }, 200, { "Cache-Control": "no-store" });
}

async function pullBatch(env: Env, request: Request) {
  const actor = await developerSession(env, request);
  const body = await readJSON(request);
  const raw = Array.isArray(body.widgets) ? body.widgets : [];
  if (raw.length === 0 || raw.length > 50) return fail("invalid_widgets", "Supply 1–50 Widget versions.", 400);
  const requested: Array<{ widgetId: string; version: string; versionId: string }> = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") return fail("invalid_widgets", "Invalid Widget list.", 400);
    const fields = item as Record<string, unknown>;
    if (typeof fields.widgetId !== "string" || typeof fields.version !== "string") return fail("invalid_widgets", "Widget ID and version are required.", 400);
    const row = await env.DB.prepare(`SELECT v.id,v.status,w.status AS widget_status FROM widget_versions v JOIN widgets w ON w.id=v.widget_id
      WHERE v.widget_id=? AND v.version=? AND (w.owner_id=? OR EXISTS
      (SELECT 1 FROM widget_worker_grants g WHERE g.widget_id=w.id AND g.developer_id=?))`)
      .bind(fields.widgetId, fields.version, actor.owner_id, actor.owner_id).first<{ id: string; status: string; widget_status: string }>();
    if (!row) return fail("worker_unauthorized", "Widget version is not owned by this developer.", 403);
    if (!["manual_review", "test_passed", "gray_release", "published"].includes(row.status) || ["suspended", "archived"].includes(row.widget_status)) continue;
    requested.push({ widgetId: fields.widgetId, version: fields.version, versionId: row.id });
  }
  const wait = Math.min(25, Math.max(0, Number(body.wait) || 0));
  const deadline = Date.now() + wait * 1000;
  if (!requested.length) return ok({ task: null }, 200, { "Cache-Control": "no-store" });
  const placeholders = requested.map(() => "?").join(",");
  const versionIDs = requested.map((item) => item.versionId);
  do {
    await env.DB.prepare(`UPDATE widget_tasks SET status='queued',worker_id=NULL,lease_expires_at=NULL,claim_token_hash=NULL WHERE version_id IN (${placeholders}) AND status IN ('claimed','running') AND lease_expires_at IS NOT NULL AND lease_expires_at<?`)
      .bind(...versionIDs, now()).run();
    const row = await env.DB.prepare(`SELECT * FROM widget_tasks WHERE version_id IN (${placeholders}) AND status='queued' ORDER BY created_at LIMIT 1`)
      .bind(...versionIDs).first<Record<string, unknown>>();
    if (row) {
      const item = requested.find((entry) => entry.versionId === row.version_id)!;
      const lease = new Date(Date.now() + 120_000).toISOString();
      const claimToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
      const claim = await env.DB.prepare("UPDATE widget_tasks SET status='claimed',lease_expires_at=?,claim_token_hash=?,claimed_at=?,attempts=attempts+1 WHERE id=? AND status='queued'")
        .bind(lease, await digest(claimToken), now(), row.id).run();
      if (claim.meta.changes === 1) return ok({ task: {
        taskId: row.id, widgetId: item.widgetId, version: item.version, versionId: item.versionId,
        commandId: row.command_id, type: row.type, input: JSON.parse(String(row.input_json)),
        parameters: JSON.parse(String(row.parameters_json)), leaseExpiresAt: lease, claimToken
      } }, 200, { "Cache-Control": "no-store" });
    }
    if (Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 500));
  } while (Date.now() < deadline);
  return ok({ task: null }, 200, { "Cache-Control": "no-store" });
}

async function taskForDeveloper(env: Env, request: Request, taskID: string) {
  const actor = await developerSession(env, request);
  const claimToken = request.headers.get("X-Task-Claim") || "";
  if (!claimToken) return null;
  return env.DB.prepare(`SELECT t.* FROM widget_tasks t JOIN widgets w ON w.id=t.widget_id WHERE t.id=?
    AND (w.owner_id=? OR EXISTS (SELECT 1 FROM widget_worker_grants g WHERE g.widget_id=w.id AND g.developer_id=?))
    AND t.claim_token_hash=? AND t.lease_expires_at>? AND t.status IN ('claimed','running')`)
    .bind(taskID, actor.owner_id, actor.owner_id, await digest(claimToken), now()).first<Record<string, unknown>>();
}

async function uploadTaskArtifact(env: Env, request: Request, taskID: string) {
  const task = await taskForDeveloper(env, request, taskID);
  if (!task) return fail("task_not_found", "Task is not assigned to this developer.", 404);
  const form = await request.formData();
  const file = form.get("file");
  if (!(file instanceof File)) return fail("file_required", "A result file is required.", 400);
  if (file.size > MAX_ASSET) return fail("file_too_large", "Result file must be 50 MB or smaller.", 413);
  if (!/^(image|video|audio)\//.test(file.type)) return fail("unsupported_media", "Only image, video, or audio results are supported.", 400);
  const assetID = id("asset");
  const objectKey = `results/${taskID}/${assetID}`;
  await env.BUCKET.put(objectKey, file.stream(), { httpMetadata: { contentType: file.type } });
  await env.DB.prepare("INSERT INTO widget_assets(id,widget_id,owner_id,object_key,mime_type,size_bytes,created_at) VALUES(?,?,?,?,?,?,?)")
    .bind(assetID, task.widget_id, task.owner_id, objectKey, file.type, file.size, now()).run();
  return ok({ assetID, type: file.type }, 201, { "Cache-Control": "no-store" });
}

async function publicTaskArtifacts(env: Env, request: Request, data: unknown) {
  if (!Array.isArray(data)) return data;
  return await Promise.all(data.map(async (entry: unknown) => {
    if (!entry || typeof entry !== "object") return entry;
    const artifact = entry as Record<string, unknown>;
    if (typeof artifact.assetID !== "string") return artifact;
    const url = await signedAssetURL(env, request, artifact.assetID, 3600);
    return artifact.type === "text" ? { ...artifact, text: url } : { ...artifact, url };
  }));
}

async function taskResult(env: Env, request: Request, taskID: string) {
  const token = bearer(request);
  if (!token) return fail("worker_auth_required", "Worker token is required.", 401);
  const developerTask = await taskForDeveloper(env, request, taskID).catch(() => null);
  const task = developerTask || (isFlowTestWorkerToken(env, token)
    ? await env.DB.prepare("SELECT * FROM widget_tasks WHERE id=?").bind(taskID).first<Record<string, unknown>>()
    : await env.DB.prepare("SELECT t.*, w.widget_id FROM widget_tasks t JOIN widget_workers w ON w.id=t.worker_id WHERE t.id=? AND w.token_hash=?").bind(taskID, await tokenHash(env, token)).first<Record<string, unknown>>());
  if (!task) return fail("task_not_found", "Task not found or Worker is not authorized.", 404);
  const body = await readJSON(request);
  const status = body.status === "succeeded" ? "succeeded" : body.status === "failed" ? "failed" : "failed";
  const artifacts = Array.isArray(body.artifacts) ? body.artifacts : Array.isArray(body.result) ? body.result : [];
  if (developerTask && status === "succeeded" && artifacts.length === 0) return fail("empty_result", "Successful tasks need an output.", 422);
  for (const value of developerTask ? artifacts : []) {
    if (!value || typeof value !== "object") return fail("invalid_result", "Invalid output.", 422);
    const artifact = value as Record<string, unknown>;
    if (artifact.type === "text") {
      if (typeof artifact.assetID === "string") {
        const asset = await env.DB.prepare("SELECT mime_type FROM widget_assets WHERE id=? AND widget_id=? AND owner_id=? AND object_key=?")
          .bind(artifact.assetID, task.widget_id, task.owner_id, `results/${taskID}/${artifact.assetID}`).first<{ mime_type: string }>();
        if (!asset?.mime_type.startsWith("image/")) return fail("invalid_asset", "Output asset does not match this task and type.", 403);
      } else if (typeof artifact.text !== "string" || artifact.text.length > 1024 * 1024) {
        return fail("invalid_text", "Invalid text output.", 422);
      }
    } else if (["image", "video", "audio"].includes(String(artifact.type))) {
      if (typeof artifact.assetID !== "string") return fail("invalid_asset", "Output asset is required.", 422);
      const asset = await env.DB.prepare("SELECT mime_type FROM widget_assets WHERE id=? AND widget_id=? AND owner_id=? AND object_key=?")
        .bind(artifact.assetID, task.widget_id, task.owner_id, `results/${taskID}/${artifact.assetID}`).first<{ mime_type: string }>();
      if (!asset || !asset.mime_type.startsWith(`${artifact.type}/`)) return fail("invalid_asset", "Output asset does not match this task and type.", 403);
    } else return fail("invalid_result", "Unsupported output type.", 422);
  }
  const updated = await env.DB.prepare("UPDATE widget_tasks SET status=?,result_json=?,error_code=?,completed_at=?,lease_expires_at=NULL WHERE id=? AND status IN ('claimed','running')")
    .bind(status, JSON.stringify(artifacts), typeof body.errorCode === "string" ? body.errorCode : null, now(), taskID).run();
  if (!updated.meta.changes) return fail("task_not_active", "Task is not active.", 409);
  if (task.type === "review_test") {
    await env.DB.prepare("INSERT INTO widget_review_results(id,task_id,widget_id,version_id,status,result_json,created_at) VALUES(?,?,?,?,?,?,?)")
      .bind(id("review"), taskID, task.widget_id, task.version_id, status, JSON.stringify(artifacts), now()).run();
  }
  return ok({ taskID, status }, 200, { "Cache-Control": "no-store" });
}

async function taskHeartbeat(env: Env, request: Request, taskID: string) {
  const token = bearer(request);
  if (!token) return fail("worker_auth_required", "Worker token is required.", 401);
  const developerTask = await taskForDeveloper(env, request, taskID).catch(() => null);
  const task = developerTask || (isFlowTestWorkerToken(env, token)
    ? await env.DB.prepare("SELECT id,worker_id FROM widget_tasks WHERE id=?").bind(taskID).first<{ id: string; worker_id: string | null }>()
    : await env.DB.prepare("SELECT t.id,t.worker_id FROM widget_tasks t JOIN widget_workers w ON w.id=t.worker_id WHERE t.id=? AND w.token_hash=?").bind(taskID, await tokenHash(env, token)).first<{ id: string; worker_id: string }>());
  if (!task) return fail("task_not_found", "Task not found or Worker is not authorized.", 404);
  await env.DB.prepare("UPDATE widget_tasks SET status='running',lease_expires_at=? WHERE id=? AND status IN ('claimed','running')").bind(new Date(Date.now() + 120_000).toISOString(), taskID).run();
  if (task.worker_id) await env.DB.prepare("UPDATE widget_workers SET last_seen_at=? WHERE id=?").bind(now(), task.worker_id).run();
  return ok({ taskID, status: "running" }, 200, { "Cache-Control": "no-store" });
}

async function submissionDetail(env: Env, request: Request, submissionID: string) {
  const actor = (await developerSession(env, request)).owner_id;
  const global = isFlowTestToken(env, bearer(request));
  const row = await env.DB.prepare(`SELECT v.id,v.widget_id,v.version,v.manifest_json,v.status,v.created_at,v.updated_at,w.owner_id FROM widget_versions v JOIN widgets w ON w.id=v.widget_id WHERE v.id=?${global ? "" : " AND w.owner_id=?"}`)
    .bind(...(global ? [submissionID] : [submissionID, actor])).first<Record<string, unknown>>();
  if (!row) return fail("submission_not_found", "Submission not found.", 404);
  return ok({ submissionId: row.id, widgetId: row.widget_id, version: row.version, status: row.status, manifest: JSON.parse(String(row.manifest_json)), createdAt: row.created_at, updatedAt: row.updated_at }, 200, { "Cache-Control": "no-store" });
}

async function adminAction(env: Env, request: Request, submissionID: string, action: string) {
  await requireAdmin(env, request);
  const row = await env.DB.prepare("SELECT v.id AS version_id,v.widget_id,v.version,v.status,v.manifest_json,w.owner_id FROM widget_versions v JOIN widgets w ON w.id=v.widget_id WHERE v.id=? OR v.widget_id=? ORDER BY v.updated_at DESC LIMIT 1")
    .bind(submissionID, submissionID).first<{ version_id: string; widget_id: string; version: string; status: string; manifest_json: string; owner_id: string }>();
  if (!row) return fail("submission_not_found", "Submission not found.", 404);
  const body = await readJSON(request).catch(() => ({} as Record<string, unknown>));
  if (action === "test") {
    if (!["manual_review", "test_passed"].includes(row.status)) return fail("not_reviewable", "Only pending versions can be tested.", 409);
    const manifest = await env.DB.prepare("SELECT manifest_json FROM widget_versions WHERE id=?").bind(row.version_id).first<{ manifest_json: string }>();
    const parsed = manifest ? JSON.parse(manifest.manifest_json) as Manifest : null;
    const commandID = typeof body.commandID === "string" ? body.commandID : parsed?.commands?.[0]?.id || "";
    const input = body.input && typeof body.input === "object" ? body.input : { url: body.url || null };
    if (typeof (input as { url?: unknown }).url === "string" && !String((input as { url?: unknown }).url).startsWith("https://")) return fail("invalid_test_url", "Test input must use HTTPS.", 422);
    const taskID = id("task");
    await env.DB.prepare("INSERT INTO widget_tasks (id,widget_id,version_id,command_id,owner_id,type,input_json,parameters_json,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)")
      .bind(taskID, row.widget_id, row.version_id, commandID, "admin", "review_test", JSON.stringify(input), JSON.stringify(body.parameters || {}), "queued", now()).run();
    return ok({ taskID, status: "queued", processCount: 0 }, 202, { "Cache-Control": "no-store" });
  }
  const next = action === "approve" ? "gray_release" : action === "promote" ? "published" : action === "reject" ? "rejected" : action === "suspend" ? "suspended" : null;
  if (!next) return fail("unknown_action", "Unknown review action.", 400);
  if (action === "approve" && !["manual_review", "test_passed"].includes(row.status)) return fail("not_reviewable", "Only pending versions can be approved.", 409);
  if (action === "reject" && !["manual_review", "test_passed"].includes(row.status)) return fail("not_reviewable", "Only pending versions can be rejected.", 409);
  const widgetState = await env.DB.prepare("SELECT status,current_version FROM widgets WHERE id=?")
    .bind(row.widget_id).first<{ status: string; current_version: string }>();
  if (!widgetState) return fail("widget_not_found", "Widget not found.", 404);
  if (action === "approve") {
    const test = await env.DB.prepare("SELECT id FROM widget_review_results WHERE version_id=? AND status='succeeded' ORDER BY created_at DESC LIMIT 1")
      .bind(row.version_id).first();
    const legacyTest = test ? test : await env.DB.prepare("SELECT id FROM widget_tasks WHERE version_id=? AND type='review_test' AND status='succeeded' ORDER BY completed_at DESC LIMIT 1")
      .bind(row.version_id).first();
    if (!legacyTest) return fail("test_required", "A successful test result is required before approval.", 409);
  }
  if (action === "promote" && row.status !== "gray_release") return fail("not_gray", "Only gray releases can be published.", 409);
  let signedManifest = row.manifest_json;
  if (action === "approve" && row.owner_id.startsWith("google:")) {
    if (!env.GLANCE_SIGNING_KEY_PKCS8) return fail("signing_unavailable", "Platform signing key is not configured.", 503);
    signedManifest = JSON.stringify(await signDeveloperManifest(env, JSON.parse(row.manifest_json) as Manifest));
  }
  const shouldChangeWidget = action === "promote" || action === "suspend" ||
    ((action === "approve" || action === "reject") && widgetState.status !== "published");
  await env.DB.batch([
    env.DB.prepare("UPDATE widget_versions SET status=?,manifest_json=?,updated_at=? WHERE id=?").bind(next, signedManifest, now(), row.version_id),
    ...(shouldChangeWidget ? [env.DB.prepare("UPDATE widgets SET status=?,current_version=?,updated_at=? WHERE id=?")
      .bind(next, action === "promote" || widgetState.status !== "published" ? row.version : widgetState.current_version, now(), row.widget_id)] : []),
    env.DB.prepare("INSERT INTO widget_audit_logs (id,widget_id,version_id,actor_id,action,previous_status,next_status,note,created_at) VALUES (?,?,?,?,?,?,?,?,?)").bind(id("audit"), row.widget_id, row.version_id, "admin", action, row.status, next, typeof body.note === "string" ? body.note : null, now())
  ]);
  return ok({ widgetId: row.widget_id, versionId: row.version_id, status: next });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    const url = new URL(request.url); const parts = pathParts(url);
    try {
      if (env.ADMIN_PATH && request.method === "GET" && (url.pathname === `/${env.ADMIN_PATH}` || url.pathname === `/${env.ADMIN_PATH}/`)) {
        return env.ASSETS.fetch(new Request(new URL("/admin/index.html", request.url), request));
      }
      if (url.pathname === "/admin" || url.pathname === "/admin/" || url.pathname === "/admin/index.html") return fail("not_found", "Not found.", 404);
      if (!url.pathname.startsWith("/api/") && url.pathname !== "/health") return env.ASSETS.fetch(request);
      if (request.method === "POST" && url.pathname === "/api/admin/auth/login") return await adminLogin(env, request);
      if (request.method === "POST" && url.pathname === "/api/admin/auth/logout") return adminLogout();
      if (request.method === "GET" && url.pathname === "/api/admin/auth/me") return await adminMe(env, request);
      if (request.method === "GET" && url.pathname === "/api/admin/v2/overview") return await adminOverview(env, request);
      if ((request.method === "GET" || request.method === "PUT") && url.pathname === "/api/admin/v2/glance-config") return await adminGlanceConfig(env, request);
      if ((request.method === "GET" || request.method === "PUT") && url.pathname === "/api/admin/v2/upload-settings") return await adminUploadSettings(env, request);
      if (request.method === "GET" && url.pathname === "/api/admin/v2/tasks") return await adminTasks(env, request);
      if (request.method === "GET" && url.pathname === "/api/admin/v2/widgets") return await adminAllWidgets(env, request);
      if (request.method === "GET" && url.pathname === "/api/admin/v2/widget-versions") return await adminWidgets(env, request);
      if (request.method === "POST" && url.pathname === "/api/admin/v2/widgets") return await adminCreateWidget(env, request);
      if (request.method === "PUT" && parts[0] === "api" && parts[1] === "admin" && parts[2] === "v2" && parts[3] === "widgets" && parts[4]) return await adminUpdateWidget(env, request, parts[4]);
      if (request.method === "GET" && url.pathname === "/health") return ok({ service: "glance-service", time: now() });
      if (request.method === "GET" && url.pathname === "/api/v2/glance_config") return await glanceConfig(env);
      if (request.method === "GET" && url.pathname === "/api/v2/widgets") return await listWidgets(env);
      if (request.method === "GET" && url.pathname === "/api/v2/location") {
        await requireUser(request, env);
        return ok({ location: requestCountry(request) }, 200, { "Cache-Control": "no-store" });
      }
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widgets" && parts[3]) return await widgetDetail(env, parts[3]);
      if (request.method === "POST" && url.pathname === "/api/v2/widget-submissions") return await createSubmission(env, request);
      if (request.method === "GET" && url.pathname === "/api/v2/developer/auth/start") return await developerAuthStart(env, request);
      if (request.method === "GET" && url.pathname === "/api/v2/developer/auth/google/callback") return await developerGoogleCallback(env, request);
      if (request.method === "POST" && url.pathname === "/api/v2/developer/auth/exchange") return await developerExchange(env, request);
      if (request.method === "GET" && url.pathname === "/api/v2/developer/auth/me") {
        const actor = await developerSession(env, request);
        return ok({ email: actor.email, ownerId: actor.owner_id, expiresAt: actor.expires_at }, 200, { "Cache-Control": "no-store" });
      }
      if (request.method === "POST" && url.pathname === "/api/v2/developer/auth/logout") {
        await developerSession(env, request);
        if (bearer(request) !== env.DEVELOPER_TEST_TOKEN) {
          await env.DB.prepare("DELETE FROM developer_sessions WHERE token_hash=?").bind(await digest(bearer(request))).run();
        }
        return ok({ loggedOut: true }, 200, { "Cache-Control": "no-store" });
      }
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "developer" && parts[3] === "widgets" && parts[4] && !parts[5]) return await developerWidget(env, request, parts[4]);
      if (request.method === "POST" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "developer" && parts[3] === "widgets" && parts[4] && parts[5]) return await developerWidgetAction(env, request, parts[4], parts[5]);
      if (request.method === "POST" && url.pathname === "/api/v2/widget-tasks/pull-batch") return await pullBatch(env, request);
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widget-submissions" && parts[3]) return await submissionDetail(env, request, parts[3]);
      if (request.method === "POST" && url.pathname === "/api/v2/widget-jobs") return await createTask(env, request);
      if (request.method === "POST" && url.pathname === "/api/v2/tasks") return await createTask(env, request);
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && (parts[2] === "tasks" || parts[2] === "widget-jobs") && parts[3]) return await taskStatus(env, request, parts[3]);
      if (request.method === "DELETE" && parts[0] === "api" && parts[1] === "v2" && (parts[2] === "tasks" || parts[2] === "widget-jobs") && parts[3]) {
        const actor = await requireUser(request, env);
        const global = isFlowTestToken(env, bearer(request));
        const cancelled = await env.DB.prepare(`UPDATE widget_tasks SET status='cancelled',completed_at=? WHERE id=?${global ? "" : " AND owner_id=?"} AND status IN ('queued','claimed','running')`)
          .bind(...(global ? [now(), parts[3]] : [now(), parts[3], actor])).run();
        return cancelled.meta.changes ? ok({ taskID: parts[3], status: "cancelled" }) : fail("task_not_found", "Task not found or cannot be cancelled.", 404);
      }
      if (request.method === "POST" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "uploads") return await uploadAsset(env, request);
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "assets" && parts[3]) return await assetDownload(env, request, parts[3]);
      if (request.method === "GET" && url.pathname === "/api/v2/widget-tasks/pull") return await pullTask(env, request, url);
      if (request.method === "POST" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widget-tasks" && parts[4] === "result") return await taskResult(env, request, parts[3]);
      if (request.method === "POST" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widget-tasks" && parts[4] === "artifacts") return await uploadTaskArtifact(env, request, parts[3]);
      if (request.method === "POST" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widget-tasks" && parts[4] === "heartbeat") return await taskHeartbeat(env, request, parts[3]);
      if (parts[0] === "api" && parts[1] === "admin" && parts[2] === "v2" && parts[3] === "widget-submissions" && parts[5]) return await adminAction(env, request, parts[4], parts[5].replace("-", "_"));
      if (parts[0] === "api" && parts[1] === "admin" && parts[2] === "v2" && parts[3] === "widget-submissions" && request.method === "GET") { await requireAdmin(env, request); const rows = await env.DB.prepare("SELECT * FROM widget_versions ORDER BY updated_at DESC").all(); return ok(rows.results); }
      return fail("not_found", "Not found.", 404);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Request failed.";
      return fail(message === "Unauthorized" ? "unauthorized" : "request_failed", message, message === "Unauthorized" ? 401 : 500);
    }
  }
};
