import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { USER_TOKEN, api, claimTask, createTask, seedWidget, sha256Hex, taskStatus, WIDGET_ID } from "./helpers";

beforeEach(async () => {
  await seedWidget();
  await env.DB.batch([env.DB.prepare("DELETE FROM widget_tasks"), env.DB.prepare("DELETE FROM widget_workers")]);
});

const DEV = () => env.DEVELOPER_TEST_TOKEN!;

describe("task cancellation lifecycle", () => {
  it("cancels a claimed task and rejects heartbeat/result/second cancel", async () => {
    const { response, taskID } = await createTask();
    expect(response.status).toBe(202);
    const task = await claimTask();
    expect(task.taskId).toBe(taskID);

    const beat = await api(`/api/v2/widget-tasks/${taskID}/heartbeat`, { method: "POST", token: DEV(), claim: task.claimToken });
    expect(beat.status).toBe(200);
    const beatBody = await beat.json() as { result: { status: string; leaseExpiresAt: string } };
    expect(beatBody.result.status).toBe("running");
    expect(Number.isNaN(Date.parse(beatBody.result.leaseExpiresAt))).toBe(false);

    const cancel = await api(`/api/v2/tasks/${taskID}`, { method: "DELETE", token: USER_TOKEN });
    expect(cancel.status).toBe(200);
    expect(await cancel.json()).toMatchObject({ result: { taskID, status: "cancelled" } });
    const row = await env.DB.prepare("SELECT lease_expires_at,claim_token_hash FROM widget_tasks WHERE id=?").bind(taskID).first();
    expect(row).toEqual({ lease_expires_at: null, claim_token_hash: null });

    const beat2 = await api(`/api/v2/widget-tasks/${taskID}/heartbeat`, { method: "POST", token: DEV(), claim: task.claimToken });
    expect(beat2.status).toBe(409);
    expect(await beat2.json()).toMatchObject({ error: { code: "task_not_active" }, status: "cancelled" });

    const result = await api(`/api/v2/widget-tasks/${taskID}/result`, { method: "POST", token: DEV(), claim: task.claimToken, json: { status: "failed" } });
    expect(result.status).toBe(409);
    expect(await result.json()).toMatchObject({ error: { code: "task_not_active" }, status: "cancelled" });

    const again = await api(`/api/v2/tasks/${taskID}`, { method: "DELETE", token: USER_TOKEN });
    expect(again.status).toBe(409);
    expect(await again.json()).toMatchObject({ error: { code: "task_not_active" }, status: "cancelled" });
  });

  it("returns 404 when cancelling someone else's or an unknown task", async () => {
    const { taskID } = await createTask();
    expect((await api(`/api/v2/tasks/${taskID}`, { method: "DELETE", token: "other-user" })).status).toBe(401);
    expect((await api("/api/v2/tasks/nope", { method: "DELETE", token: USER_TOKEN })).status).toBe(404);
  });

  it("legacy worker-token heartbeat/result honour cancellation and revoked workers", async () => {
    const { taskID } = await createTask();
    const workerToken = "legacy-worker-token";
    const hash = await sha256Hex(`${env.WORKER_TOKEN_PEPPER}:${workerToken}`);
    await env.DB.prepare("INSERT INTO widget_workers (id,widget_id,owner_id,token_hash,status,created_at) VALUES (?,?,?,?,?,?)")
      .bind("worker_legacy", WIDGET_ID, "admin", hash, "active", new Date().toISOString()).run();
    await env.DB.prepare("UPDATE widget_tasks SET status='claimed',worker_id='worker_legacy',lease_expires_at=? WHERE id=?")
      .bind(new Date(Date.now() + 60_000).toISOString(), taskID).run();
    const beat = () => api(`/api/v2/widget-tasks/${taskID}/heartbeat`, { method: "POST", token: workerToken });

    expect((await beat()).status).toBe(200);

    await env.DB.prepare("UPDATE widget_workers SET status='revoked' WHERE id='worker_legacy'").run();
    expect((await beat()).status).toBe(404);
    expect((await api(`/api/v2/widget-tasks/${taskID}/result`, { method: "POST", token: workerToken, json: { status: "failed" } })).status).toBe(404);

    await env.DB.prepare("UPDATE widget_workers SET status='active' WHERE id='worker_legacy'").run();
    await api(`/api/v2/tasks/${taskID}`, { method: "DELETE", token: USER_TOKEN });
    const after = await beat();
    expect(after.status).toBe(409);
    expect(await after.json()).toMatchObject({ status: "cancelled" });
    expect((await api(`/api/v2/widget-tasks/${taskID}/result`, { method: "POST", token: workerToken, json: { status: "failed" } })).status).toBe(409);
  });
});

describe("progress and polling interval", () => {
  it("reports progress, phase and pollAfterMs", async () => {
    const { taskID } = await createTask();
    const queued = await taskStatus(taskID!);
    expect(queued.body.status).toBe("queued");
    expect(queued.body.pollAfterMs).toBe(3000);
    expect(queued.body).not.toHaveProperty("progress");

    const task = await claimTask();
    const claimed = await taskStatus(taskID!);
    expect(claimed.body.status).toBe("claimed");
    expect(claimed.body.pollAfterMs).toBe(2000);

    const beat = await api(`/api/v2/widget-tasks/${taskID}/heartbeat`, { method: "POST", token: DEV(), claim: task.claimToken, json: { progress: 42, phase: "processing" } });
    expect(beat.status).toBe(200);
    const running = await taskStatus(taskID!);
    expect(running.body).toMatchObject({ status: "running", progress: 42, phase: "processing", pollAfterMs: 2000 });

    // Clamping, truncation, and tolerance for empty/invalid bodies.
    await api(`/api/v2/widget-tasks/${taskID}/heartbeat`, { method: "POST", token: DEV(), claim: task.claimToken, json: { progress: 250.4, phase: "x".repeat(80) } });
    const clamped = await taskStatus(taskID!);
    expect(clamped.body.progress).toBe(100);
    expect(String(clamped.body.phase)).toHaveLength(40);
    const bad = await api(`/api/v2/widget-tasks/${taskID}/heartbeat`, { method: "POST", token: DEV(), claim: task.claimToken, body: "{not json", headers: { "Content-Type": "application/json" } });
    expect(bad.status).toBe(200);

    const done = await api(`/api/v2/widget-tasks/${taskID}/result`, { method: "POST", token: DEV(), claim: task.claimToken, json: { status: "failed", errorCode: "boom" } });
    expect(done.status).toBe(200);
    const final = await taskStatus(taskID!);
    expect(final.body).not.toHaveProperty("pollAfterMs");
  });
});

describe("error responses", () => {
  it("returns 400 invalid_json for malformed task bodies", async () => {
    const response = await api("/api/v2/tasks", { method: "POST", token: USER_TOKEN, body: "{oops", headers: { "Content-Type": "application/json" } });
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: { code: "invalid_json" } });
  });

  it("returns 401 without a token and does not leak internals for unexpected errors", async () => {
    expect((await api("/api/v2/tasks", { method: "POST", json: {} })).status).toBe(401);
    await env.DB.prepare("ALTER TABLE widget_tasks RENAME TO widget_tasks_hidden").run();
    let response: Response;
    try {
      response = await api("/api/v2/tasks/abc", { token: USER_TOKEN });
    } finally {
      await env.DB.prepare("ALTER TABLE widget_tasks_hidden RENAME TO widget_tasks").run();
    }
    expect(response.status).toBe(500);
    const body = await response.json() as { error: { code: string; message: string } };
    expect(body.error).toEqual({ code: "internal_error", message: "Internal server error." });
  });
});
