import { env } from "cloudflare:workers";
import { SELF } from "cloudflare:test";

export const USER_TOKEN = "user-token-a";
export const WIDGET_ID = "11111111-1111-4111-8111-111111111111";
const COMMAND_ID = "run";

export function api(path: string, init: RequestInit & { token?: string; claim?: string; json?: unknown } = {}) {
  const headers = new Headers(init.headers);
  if (init.token) headers.set("Authorization", `Bearer ${init.token}`);
  if (init.claim) headers.set("X-Task-Claim", init.claim);
  let body = init.body;
  if (init.json !== undefined) {
    headers.set("Content-Type", "application/json");
    body = JSON.stringify(init.json);
  }
  return SELF.fetch(`https://example.com${path}`, { ...init, headers, body });
}

export async function sha256Hex(value: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Published Widget owned by "admin" and granted to the mock developer token.
export async function seedWidget() {
  const manifest = { schemaVersion: 1, id: WIDGET_ID, version: "1.0.0", name: "Test", commands: [{ id: COMMAND_ID, name: "Run" }] };
  const t = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare("INSERT OR IGNORE INTO widgets (id,owner_id,name,summary,author,icon_url,current_version,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)")
      .bind(WIDGET_ID, "admin", "Test", "Test", "Test", null, "1.0.0", "published", t, t),
    env.DB.prepare("INSERT OR IGNORE INTO widget_versions (id,widget_id,version,manifest_json,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?)")
      .bind("version_test", WIDGET_ID, "1.0.0", JSON.stringify(manifest), "published", t, t),
    env.DB.prepare("INSERT OR IGNORE INTO widget_worker_grants (widget_id,developer_id) VALUES (?,?)").bind(WIDGET_ID, "mock:glance-cli")
  ]);
}

export async function createTask(token = USER_TOKEN) {
  const response = await api("/api/v2/tasks", { method: "POST", token, json: { widgetID: WIDGET_ID, commandID: COMMAND_ID, input: { url: "https://example.com/a.png" } } });
  const body = await response.json() as { result?: Record<string, unknown> & { taskID: string } };
  return { response, taskID: body.result?.taskID, body: body.result };
}

export async function claimTask() {
  const response = await api("/api/v2/widget-tasks/pull-batch", { method: "POST", token: env.DEVELOPER_TEST_TOKEN, json: { widgets: [{ widgetId: WIDGET_ID }] } });
  const body = await response.json() as { result: { task: { taskId: string; claimToken: string } | null } };
  return body.result.task!;
}

export async function taskStatus(taskID: string, token = USER_TOKEN) {
  const response = await api(`/api/v2/tasks/${taskID}`, { token });
  return { response, body: (await response.json() as { result: Record<string, unknown> }).result };
}
