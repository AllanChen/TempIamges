import { OFFICIAL_MANIFESTS } from "./official";

export interface Env {
  DB: D1Database;
  BUCKET: R2Bucket;
  PUBLIC_ORIGIN: string;
  SESSION_SECRET: string;
  ADMIN_TOKEN: string;
  ADMIN_USERNAME: string;
  ADMIN_PASSWORD: string;
  ADMIN_PATH: string;
  WORKER_TOKEN_PEPPER: string;
  MEDIA_SIGNING_SECRET: string;
  WORKER_AUTH_DISABLED?: string;
  ASSETS: Fetcher;
}

type Manifest = {
  schemaVersion?: number; id?: string; version?: string; name?: string; summary?: string;
  author?: string; iconURL?: string; execution?: { mode?: string };
  commands?: Array<{ id?: string; name?: string; inputTypes?: string[]; outputs?: string[]; taskType?: string; parameterSchema?: unknown }>;
  privacy?: { uploadsMedia?: boolean; notice?: string };
};

const MAX_BODY = 2 * 1024 * 1024;
const MAX_ASSET = 50 * 1024 * 1024;
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Widget-Id",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
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

async function digest(value: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function tokenHash(env: Env, token: string) { return digest(`${env.WORKER_TOKEN_PEPPER}:${token}`); }
// TEMPORARY dev switch: when "true", worker endpoints skip token verification
// so the pull/heartbeat/result flow can be tested end-to-end before auth is wired.
function workerAuthDisabled(env: Env) { return String(env.WORKER_AUTH_DISABLED || "").toLowerCase() === "true"; }
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
async function requireUser(request: Request) {
  const token = bearer(request);
  if (!token) throw new Error("Unauthorized");
  return `user_${await digest(token)}`;
}
async function requireAdmin(env: Env, request: Request) {
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
  const rows = await env.DB.prepare("SELECT t.id,t.widget_id,t.version_id,t.command_id,t.owner_id,t.type,t.status,t.worker_id,t.attempts,t.error_code,t.result_json,t.created_at,t.claimed_at,t.completed_at,w.name AS widget_name,v.version FROM widget_tasks t LEFT JOIN widgets w ON w.id=t.widget_id LEFT JOIN widget_versions v ON v.id=t.version_id ORDER BY t.created_at DESC LIMIT 100").all<Record<string, unknown>>();
  return ok(rows.results.map((row) => ({ ...row, result: row.result_json ? JSON.parse(String(row.result_json)) : null, result_json: undefined })), 200, { "Cache-Control": "no-store" });
}
async function adminWidgets(env: Env, request: Request) {
  await requireAdmin(env, request);
  const rows = await env.DB.prepare("SELECT v.id AS version_id,v.widget_id,v.version,v.status,v.manifest_json,v.created_at,v.updated_at,w.name,w.author,w.owner_id FROM widget_versions v JOIN widgets w ON w.id=v.widget_id ORDER BY v.updated_at DESC LIMIT 100").all<Record<string, unknown>>();
  return ok(rows.results.map((row) => ({ ...row, manifest: JSON.parse(String(row.manifest_json)), manifest_json: undefined })), 200, { "Cache-Control": "no-store" });
}
function validationIssues(manifest: Manifest) {
  const issues: string[] = [];
  if (manifest.schemaVersion !== 1) issues.push("schemaVersion must be 1");
  if (!manifest.id || !/^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$/.test(manifest.id)) issues.push("invalid widget id");
  for (const field of ["version", "name", "summary", "author"] as const) if (!manifest[field]?.trim()) issues.push(`${field} is required`);
  if (manifest.execution?.mode !== "cloud") issues.push("execution.mode must be cloud");
  if (!Array.isArray(manifest.commands) || manifest.commands.length === 0) issues.push("at least one command is required");
  const commandIDs = new Set<string>();
  for (const command of manifest.commands || []) {
    if (!command.id || commandIDs.has(command.id)) issues.push(`duplicate or missing command id: ${command.id || "unknown"}`);
    if (command.id) commandIDs.add(command.id);
    if (!Array.isArray(command.inputTypes) || command.inputTypes.length === 0) issues.push(`command ${command.id || "unknown"} needs inputTypes`);
    if (!Array.isArray(command.outputs) || command.outputs.length === 0) issues.push(`command ${command.id || "unknown"} needs outputs`);
    if (!command.taskType?.trim()) issues.push(`command ${command.id || "unknown"} needs taskType`);
  }
  if (!manifest.privacy?.notice?.trim()) issues.push("privacy.notice is required");
  return issues;
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
    if (exists) continue;
    const versionID = id("version");
    await env.DB.batch([
      env.DB.prepare("INSERT OR IGNORE INTO widgets (id,owner_id,name,summary,author,icon_url,current_version,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)").bind(manifest.id, "glance-official", manifest.name, manifest.summary, manifest.author, manifest.iconURL, manifest.version, "published", timestamp, timestamp),
      env.DB.prepare("INSERT OR IGNORE INTO widget_versions (id,widget_id,version,manifest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)").bind(versionID, manifest.id, manifest.version, JSON.stringify(manifest), "published", timestamp, timestamp)
    ]);
  }
}

async function createSubmission(env: Env, request: Request) {
  const owner = await requireUser(request);
  const body = await readJSON(request);
  const manifest = body.manifest as Manifest;
  const issues = validationIssues(manifest || {});
  if (issues.length) return fail("invalid_manifest", issues.join("; "), 422);
  const widgetID = manifest.id!;
  const versionID = id("version");
  const submissionID = id("submission");
  const workerToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const workerID = id("worker");
  const timestamp = now();
  try {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO widgets (id,owner_id,name,summary,author,icon_url,current_version,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,summary=excluded.summary,author=excluded.author,icon_url=excluded.icon_url,updated_at=excluded.updated_at").bind(widgetID, owner, manifest.name, manifest.summary, manifest.author, manifest.iconURL || null, manifest.version, "manual_review", timestamp, timestamp),
      env.DB.prepare("INSERT INTO widget_versions (id,widget_id,version,manifest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)").bind(versionID, widgetID, manifest.version, JSON.stringify(manifest), "manual_review", timestamp, timestamp),
      env.DB.prepare("INSERT INTO widget_workers (id,widget_id,owner_id,token_hash,status,created_at) VALUES (?,?,?,?,?,?)").bind(workerID, widgetID, owner, await tokenHash(env, workerToken), "active", timestamp),
      env.DB.prepare("INSERT INTO widget_audit_logs (id,widget_id,version_id,actor_id,action,previous_status,next_status,note,created_at) VALUES (?,?,?,?,?,?,?,?,?)").bind(id("audit"), widgetID, versionID, owner, "submit", null, "manual_review", null, timestamp)
    ]);
  } catch (error) {
    const message = error instanceof Error && error.message.includes("UNIQUE") ? "Widget version already exists." : "Unable to save submission.";
    return fail("submission_failed", message, 409);
  }
  return ok({ submissionId: versionID, widgetId: widgetID, version: manifest.version, workerToken, status: "manual_review" }, 201, { "Cache-Control": "no-store" });
}

async function listWidgets(env: Env) {
  await ensureOfficialWidgets(env);
  const rows = await env.DB.prepare("SELECT manifest_json FROM widget_versions WHERE status IN ('published','gray_release') ORDER BY updated_at DESC").all<{ manifest_json: string }>();
  return ok({ widgets: rows.results.map(publicManifest), pagination: { page: 1, limit: rows.results.length, total: rows.results.length, totalPages: rows.results.length ? 1 : 0 } }, 200, { "Cache-Control": "public, max-age=60" });
}

async function widgetDetail(env: Env, widgetID: string) {
  await ensureOfficialWidgets(env);
  const row = await env.DB.prepare("SELECT manifest_json FROM widget_versions WHERE widget_id=? AND status IN ('published','gray_release') ORDER BY updated_at DESC LIMIT 1").bind(widgetID).first<{ manifest_json: string }>();
  return row ? ok(publicManifest(row), 200, { "Cache-Control": "public, max-age=60" }) : fail("widget_not_found", "Widget not found.", 404);
}

async function taskStatus(env: Env, request: Request, taskID: string) {
  const actor = await requireUser(request);
  const row = await env.DB.prepare("SELECT id,owner_id,status,result_json,error_code,attempts FROM widget_tasks WHERE id=? AND owner_id=?").bind(taskID, actor).first<Record<string, unknown>>();
  if (!row) return fail("task_not_found", "Task not found.", 404);
  const result: Record<string, unknown> = { taskID: row.id, status: row.status === "succeeded" ? "completed" : row.status, processCount: row.status === "succeeded" ? 100 : 0, attempts: row.attempts };
  if (row.result_json) {
    const artifacts = JSON.parse(String(row.result_json));
    result.result = artifacts;
    if (Array.isArray(artifacts) && typeof artifacts[0]?.url === "string") result.resultURL = artifacts[0].url;
  }
  if (row.error_code) result.error = row.error_code;
  return ok(result, 200, { "Cache-Control": "no-store" });
}

async function uploadAsset(env: Env, request: Request) {
  const owner = await requireUser(request);
  const form = await request.formData();
  const file = form.get("file");
  if (!(file instanceof File)) return fail("file_required", "A media file is required.", 400);
  const allowed = new Set(["image/jpeg", "image/png", "image/webp", "image/gif", "image/heic", "image/heif", "video/mp4", "video/quicktime", "video/webm"]);
  if (!allowed.has(file.type)) return fail("unsupported_media", "Unsupported media type.", 400);
  if (file.size > MAX_ASSET) return fail("file_too_large", "Media must be 50 MB or smaller.", 413);
  const assetID = id("asset"); const key = `glance/${owner}/${assetID}`; const created = now();
  await env.BUCKET.put(key, file.stream(), { httpMetadata: { contentType: file.type, cacheControl: "private, max-age=300" } });
  await env.DB.prepare("INSERT INTO widget_assets (id,owner_id,object_key,mime_type,size_bytes,created_at) VALUES (?,?,?,?,?,?)").bind(assetID, owner, key, file.type, file.size, created).run();
  return ok({ assetID, url: await signedAssetURL(env, request, assetID) }, 201, { "Cache-Control": "no-store" });
}

async function assetDownload(env: Env, request: Request, assetID: string) {
  const signed = await validAssetSignature(env, assetID, new URL(request.url).searchParams.get("exp") || "", new URL(request.url).searchParams.get("sig") || "");
  const owner = signed ? null : await requireUser(request);
  const row = owner
    ? await env.DB.prepare("SELECT object_key,mime_type FROM widget_assets WHERE id=? AND owner_id=?").bind(assetID, owner).first<{ object_key: string; mime_type: string }>()
    : await env.DB.prepare("SELECT object_key,mime_type FROM widget_assets WHERE id=?").bind(assetID).first<{ object_key: string; mime_type: string }>();
  if (!row) return fail("asset_not_found", "Asset not found.", 404);
  const object = await env.BUCKET.get(row.object_key);
  if (!object) return fail("asset_not_found", "Asset not found.", 404);
  return new Response(object.body, { headers: { ...CORS, "Content-Type": row.mime_type, "Cache-Control": "private, max-age=300" } });
}

async function createTask(env: Env, request: Request, admin = false) {
  const actor = admin ? "admin" : await requireUser(request);
  await ensureOfficialWidgets(env);
  const body = await readJSON(request);
  const widgetID = typeof body.widgetID === "string" ? body.widgetID : typeof body.widget_id === "string" ? body.widget_id : "";
  const commandID = typeof body.commandID === "string" ? body.commandID : typeof body.command_id === "string" ? body.command_id : "";
  const widget = await env.DB.prepare("SELECT id,owner_id,current_version,status FROM widgets WHERE id=?").bind(widgetID).first<{ id: string; owner_id: string; current_version: string; status: string }>();
  if (!widget || (!admin && widget.status !== "published" && widget.status !== "gray_release")) return fail("widget_unavailable", "Widget is not available.", 404);
  const version = await env.DB.prepare("SELECT id,manifest_json FROM widget_versions WHERE widget_id=? AND version=?").bind(widgetID, widget.current_version).first<{ id: string; manifest_json: string }>();
  if (!version) return fail("version_missing", "Widget version is missing.", 409);
  const manifest = JSON.parse(version.manifest_json) as Manifest;
  const command = manifest.commands?.find((entry) => entry.id === commandID);
  if (!command) return fail("unknown_command", "Unknown Widget command.", 400);
  const taskID = id("task");
  const type = admin ? "review_test" : "production";
  const input = (body.input && typeof body.input === "object") ? body.input : { url: (body.taskParams as Record<string, unknown> | undefined)?.url || body.url || null };
  await env.DB.prepare("INSERT INTO widget_tasks (id,widget_id,version_id,command_id,owner_id,type,input_json,parameters_json,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)")
    .bind(taskID, widgetID, version.id, commandID, admin ? widget.owner_id : actor, type, JSON.stringify(input), JSON.stringify(body.parameters || body.taskParams || {}), "queued", now()).run();
  return ok({ taskID, status: "queued", processCount: 0, pollAfterMs: 1000 }, 202, { "Cache-Control": "no-store" });
}

async function pullTask(env: Env, request: Request, url: URL) {
  const token = bearer(request);
  const widgetID = url.searchParams.get("widget_id") || "";
  const bypass = workerAuthDisabled(env);
  if (!widgetID || (!bypass && !token)) return fail("worker_auth_required", "Widget ID and Worker token are required.", 401);
  let workerID = "dev-worker";
  if (!bypass) {
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

async function taskResult(env: Env, request: Request, taskID: string) {
  const token = bearer(request);
  const task = workerAuthDisabled(env)
    ? await env.DB.prepare("SELECT * FROM widget_tasks WHERE id=?").bind(taskID).first<Record<string, unknown>>()
    : await env.DB.prepare("SELECT t.*, w.widget_id FROM widget_tasks t JOIN widget_workers w ON w.id=t.worker_id WHERE t.id=? AND w.token_hash=?").bind(taskID, await tokenHash(env, token)).first<Record<string, unknown>>();
  if (!task) return fail("task_not_found", "Task not found or Worker is not authorized.", 404);
  const body = await readJSON(request);
  const status = body.status === "succeeded" ? "succeeded" : body.status === "failed" ? "failed" : "failed";
  await env.DB.prepare("UPDATE widget_tasks SET status=?,result_json=?,error_code=?,completed_at=?,lease_expires_at=NULL WHERE id=? AND status IN ('claimed','running')").bind(status, JSON.stringify(body.artifacts || body.result || null), typeof body.errorCode === "string" ? body.errorCode : null, now(), taskID).run();
  if (status === "succeeded" && task.type === "review_test") await env.DB.prepare("UPDATE widget_versions SET status='test_passed',updated_at=? WHERE id=?").bind(now(), task.version_id).run();
  return ok({ taskID, status }, 200, { "Cache-Control": "no-store" });
}

async function taskHeartbeat(env: Env, request: Request, taskID: string) {
  const token = bearer(request);
  const bypass = workerAuthDisabled(env);
  if (!bypass && !token) return fail("worker_auth_required", "Worker token is required.", 401);
  const task = bypass
    ? await env.DB.prepare("SELECT id,worker_id FROM widget_tasks WHERE id=?").bind(taskID).first<{ id: string; worker_id: string | null }>()
    : await env.DB.prepare("SELECT t.id,t.worker_id FROM widget_tasks t JOIN widget_workers w ON w.id=t.worker_id WHERE t.id=? AND w.token_hash=?").bind(taskID, await tokenHash(env, token)).first<{ id: string; worker_id: string }>();
  if (!task) return fail("task_not_found", "Task not found or Worker is not authorized.", 404);
  await env.DB.prepare("UPDATE widget_tasks SET status='running',lease_expires_at=? WHERE id=? AND status IN ('claimed','running')").bind(new Date(Date.now() + 120_000).toISOString(), taskID).run();
  if (task.worker_id) await env.DB.prepare("UPDATE widget_workers SET last_seen_at=? WHERE id=?").bind(now(), task.worker_id).run();
  return ok({ taskID, status: "running" }, 200, { "Cache-Control": "no-store" });
}

async function submissionDetail(env: Env, request: Request, submissionID: string) {
  const actor = await requireUser(request);
  const row = await env.DB.prepare("SELECT v.id,v.widget_id,v.version,v.manifest_json,v.status,v.created_at,v.updated_at,w.owner_id FROM widget_versions v JOIN widgets w ON w.id=v.widget_id WHERE v.id=? AND w.owner_id=?").bind(submissionID, actor).first<Record<string, unknown>>();
  if (!row) return fail("submission_not_found", "Submission not found.", 404);
  return ok({ submissionId: row.id, widgetId: row.widget_id, version: row.version, status: row.status, manifest: JSON.parse(String(row.manifest_json)), createdAt: row.created_at, updatedAt: row.updated_at }, 200, { "Cache-Control": "no-store" });
}

async function adminAction(env: Env, request: Request, submissionID: string, action: string) {
  await requireAdmin(env, request);
  const row = await env.DB.prepare("SELECT v.id AS version_id,v.widget_id,v.status FROM widget_versions v WHERE v.id=? OR v.widget_id=? ORDER BY v.updated_at DESC LIMIT 1").bind(submissionID, submissionID).first<{ version_id: string; widget_id: string; status: string }>();
  if (!row) return fail("submission_not_found", "Submission not found.", 404);
  const body = await readJSON(request).catch(() => ({} as Record<string, unknown>));
  if (action === "test") {
    const manifest = await env.DB.prepare("SELECT manifest_json FROM widget_versions WHERE id=?").bind(row.version_id).first<{ manifest_json: string }>();
    const body = await readJSON(request).catch(() => ({} as Record<string, unknown>));
    const parsed = manifest ? JSON.parse(manifest.manifest_json) as Manifest : null;
    const commandID = typeof body.commandID === "string" ? body.commandID : parsed?.commands?.[0]?.id || "";
    const input = body.input && typeof body.input === "object" ? body.input : { url: body.url || null };
    const taskID = id("task");
    await env.DB.prepare("INSERT INTO widget_tasks (id,widget_id,version_id,command_id,owner_id,type,input_json,parameters_json,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)")
      .bind(taskID, row.widget_id, row.version_id, commandID, "admin", "review_test", JSON.stringify(input), JSON.stringify(body.parameters || {}), "queued", now()).run();
    return ok({ taskID, status: "queued", processCount: 0 }, 202, { "Cache-Control": "no-store" });
  }
  const next = action === "approve" ? "gray_release" : action === "reject" ? "rejected" : action === "suspend" ? "suspended" : null;
  if (!next) return fail("unknown_action", "Unknown review action.", 400);
  await env.DB.batch([
    env.DB.prepare("UPDATE widget_versions SET status=?,updated_at=? WHERE id=?").bind(next, now(), row.version_id),
    env.DB.prepare("UPDATE widgets SET status=?,updated_at=? WHERE id=?").bind(next, now(), row.widget_id),
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
      if (request.method === "POST" && url.pathname === "/api/admin/auth/login") return adminLogin(env, request);
      if (request.method === "POST" && url.pathname === "/api/admin/auth/logout") return adminLogout();
      if (request.method === "GET" && url.pathname === "/api/admin/auth/me") return adminMe(env, request);
      if (request.method === "GET" && url.pathname === "/api/admin/v2/overview") return adminOverview(env, request);
      if (request.method === "GET" && url.pathname === "/api/admin/v2/tasks") return adminTasks(env, request);
      if (request.method === "GET" && url.pathname === "/api/admin/v2/widgets") return adminWidgets(env, request);
      if (request.method === "GET" && url.pathname === "/health") return ok({ service: "glance-service", time: now() });
      if (request.method === "GET" && url.pathname === "/api/v2/widgets") return listWidgets(env);
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widgets" && parts[3]) return widgetDetail(env, parts[3]);
      if (request.method === "POST" && url.pathname === "/api/v2/widget-submissions") return createSubmission(env, request);
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widget-submissions" && parts[3]) return submissionDetail(env, request, parts[3]);
      if (request.method === "POST" && url.pathname === "/api/v2/widget-jobs") return createTask(env, request);
      if (request.method === "POST" && url.pathname === "/api/v2/tasks") return createTask(env, request);
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && (parts[2] === "tasks" || parts[2] === "widget-jobs") && parts[3]) return taskStatus(env, request, parts[3]);
      if (request.method === "DELETE" && parts[0] === "api" && parts[1] === "v2" && (parts[2] === "tasks" || parts[2] === "widget-jobs") && parts[3]) {
        const actor = await requireUser(request);
        const cancelled = await env.DB.prepare("UPDATE widget_tasks SET status='cancelled',completed_at=? WHERE id=? AND owner_id=? AND status IN ('queued','claimed','running')").bind(now(), parts[3], actor).run();
        return cancelled.meta.changes ? ok({ taskID: parts[3], status: "cancelled" }) : fail("task_not_found", "Task not found or cannot be cancelled.", 404);
      }
      if (request.method === "POST" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "uploads") return uploadAsset(env, request);
      if (request.method === "GET" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "assets" && parts[3]) return assetDownload(env, request, parts[3]);
      if (request.method === "GET" && url.pathname === "/api/v2/widget-tasks/pull") return pullTask(env, request, url);
      if (request.method === "POST" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widget-tasks" && parts[4] === "result") return taskResult(env, request, parts[3]);
      if (request.method === "POST" && parts[0] === "api" && parts[1] === "v2" && parts[2] === "widget-tasks" && parts[4] === "heartbeat") return taskHeartbeat(env, request, parts[3]);
      if (parts[0] === "api" && parts[1] === "admin" && parts[2] === "v2" && parts[3] === "widget-submissions" && parts[5]) return adminAction(env, request, parts[4], parts[5].replace("-", "_"));
      if (parts[0] === "api" && parts[1] === "admin" && parts[2] === "v2" && parts[3] === "widget-submissions" && request.method === "GET") { await requireAdmin(env, request); const rows = await env.DB.prepare("SELECT * FROM widget_versions ORDER BY updated_at DESC").all(); return ok(rows.results); }
      return fail("not_found", "Not found.", 404);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Request failed.";
      return fail(message === "Unauthorized" ? "unauthorized" : "request_failed", message, message === "Unauthorized" ? 401 : 500);
    }
  }
};
