import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { USER_TOKEN, api, claimTask, createTask, seedWidget, taskStatus, WIDGET_ID } from "./helpers";

beforeEach(async () => {
  await seedWidget();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM widget_tasks"),
    env.DB.prepare("DELETE FROM widget_workers"),
    env.DB.prepare("DELETE FROM service_settings WHERE key='task_queue_limit'")
  ]);
});

function setQueueLimit(value: string) {
  return env.DB.prepare("INSERT INTO service_settings (key,value,updated_at) VALUES ('task_queue_limit',?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
    .bind(value, new Date().toISOString()).run();
}

// Inserts finished/active rows directly so the estimate has history to work from.
function seedTask(id: string, fields: { status: string; widgetID?: string; claimedAt?: string; completedAt?: string | null; createdAt?: string }) {
  return env.DB.prepare("INSERT INTO widget_tasks (id,widget_id,version_id,command_id,owner_id,type,input_json,parameters_json,status,created_at,claimed_at,completed_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)")
    .bind(id, fields.widgetID ?? WIDGET_ID, "version_test", "run", "seed", "production", "{}", "{}", fields.status,
      fields.createdAt ?? fields.claimedAt ?? new Date().toISOString(), fields.claimedAt ?? null, fields.completedAt ?? null).run();
}

const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();

describe("queue limit", () => {
  it("returns 429 queue_full with Retry-After once the configured limit is reached", async () => {
    await setQueueLimit("2");
    expect((await createTask()).response.status).toBe(202);
    expect((await createTask()).response.status).toBe(202);

    const third = await api("/api/v2/tasks", { method: "POST", token: USER_TOKEN, json: { widgetID: WIDGET_ID, commandID: "run", input: { url: "https://example.com/a.png" } } });
    expect(third.status).toBe(429);
    expect(third.headers.get("Retry-After")).toBe("60");
    expect(await third.json()).toMatchObject({ error: { code: "queue_full" } });
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM widget_tasks").first<{ n: number }>())?.n).toBe(2);

    // Only queued tasks count: claiming one frees a slot.
    await claimTask();
    expect((await createTask()).response.status).toBe(202);
  });

  it("defaults to 300 across all Widgets when the setting is missing or invalid", async () => {
    await setQueueLimit("not-a-number");
    const statements = [];
    for (let i = 0; i < 300; i++) statements.push(env.DB.prepare("INSERT INTO widget_tasks (id,widget_id,version_id,command_id,owner_id,type,input_json,parameters_json,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)")
      .bind(`task_seed_${i}`, "other-widget", "v", "run", "seed", "production", "{}", "{}", "queued", iso(-1000)));
    await env.DB.batch(statements);
    expect((await createTask()).response.status).toBe(429);

    await env.DB.prepare("DELETE FROM widget_tasks WHERE id='task_seed_0'").run();
    expect((await createTask()).response.status).toBe(202);
  });
});

describe("queue position", () => {
  it("numbers queued tasks per Widget and exposes the position on the status endpoint", async () => {
    const first = await createTask();
    const second = await createTask();
    const third = await createTask();
    expect([first, second, third].map(({ body }) => body?.queuePosition)).toEqual([1, 2, 3]);

    expect((await taskStatus(third.taskID!)).body).toMatchObject({ status: "queued", queuePosition: 3, pollAfterMs: 3000 });

    // The first task leaves the queue, so the others move up; claimed tasks carry no position.
    const claimed = await claimTask();
    expect(claimed.taskId).toBe(first.taskID);
    expect((await taskStatus(first.taskID!)).body).not.toHaveProperty("queuePosition");
    expect((await taskStatus(second.taskID!)).body.queuePosition).toBe(1);
    expect((await taskStatus(third.taskID!)).body.queuePosition).toBe(2);

    // Another Widget's queue does not affect this one.
    await seedTask("task_other", { status: "queued", widgetID: "other-widget", createdAt: iso(-60_000) });
    expect((await taskStatus(second.taskID!)).body.queuePosition).toBe(1);
  });
});

describe("estimated wait", () => {
  it("is omitted when the Widget has no successful history", async () => {
    const { body, taskID } = await createTask();
    expect(body?.queuePosition).toBe(1);
    expect(body).not.toHaveProperty("estimatedWaitSeconds");

    // Failed runs do not count as history either.
    await seedTask("task_failed", { status: "failed", claimedAt: iso(-120_000), completedAt: iso(-60_000) });
    const { body: status } = await taskStatus(taskID!);
    expect(status).not.toHaveProperty("estimatedWaitSeconds");
  });

  it("uses position × mean duration of recent successes ÷ observed concurrency", async () => {
    // Two old successes (60 s and 120 s) → mean 90 s; well outside the 10-minute concurrency window.
    await seedTask("task_ok_1", { status: "succeeded", claimedAt: iso(-3_600_000), completedAt: iso(-3_540_000) });
    await seedTask("task_ok_2", { status: "succeeded", claimedAt: iso(-3_000_000), completedAt: iso(-2_880_000) });

    const first = await createTask();
    const second = await createTask();
    expect(first.body).toMatchObject({ queuePosition: 1, estimatedWaitSeconds: 90 });
    expect(second.body).toMatchObject({ queuePosition: 2, estimatedWaitSeconds: 180 });
    expect((await taskStatus(second.taskID!)).body).toMatchObject({ queuePosition: 2, estimatedWaitSeconds: 180 });

    // Two tasks that overlapped within the last 10 minutes → concurrency 2 halves the estimate.
    // task_run_2 is a 90 s success, so the mean of the three successes stays at 90 s.
    await seedTask("task_run_1", { status: "running", claimedAt: iso(-30_000), completedAt: null });
    await seedTask("task_run_2", { status: "succeeded", claimedAt: iso(-100_000), completedAt: iso(-10_000) });
    expect((await taskStatus(second.taskID!)).body.estimatedWaitSeconds).toBe(90);
  });
});

describe("response compatibility", () => {
  it("keeps the existing 202 fields", async () => {
    const { response, body } = await createTask();
    expect(response.status).toBe(202);
    expect(body).toMatchObject({ status: "queued", processCount: 0, pollAfterMs: 1000, queuePosition: 1 });
    expect((await api("/api/v2/tasks/nope", { token: USER_TOKEN })).status).toBe(404);
  });
});
