import { env } from "cloudflare:workers";
import { beforeEach, expect, it } from "vitest";
import { api, createTask, seedWidget, sha256Hex, taskStatus, WIDGET_ID } from "./helpers";

const machine = { name: "Allan 的 Mac mini", platform: "Darwin", cliVersion: "0.1.0" };
const pull = (info?: unknown, token = env.DEVELOPER_TEST_TOKEN) => api("/api/v2/widget-tasks/pull-batch", {
  method: "POST", token, json: { widgets: [{ widgetId: WIDGET_ID }], machine: info }
});
const snapshot = (id: string) => env.DB.prepare("SELECT machine_name,machine_platform,machine_cli_version FROM widget_tasks WHERE id=?").bind(id).first();
const expireLease = (id: string) => env.DB.prepare("UPDATE widget_tasks SET lease_expires_at=? WHERE id=?")
  .bind(new Date(Date.now() - 1000).toISOString(), id).run();

beforeEach(async () => {
  await seedWidget();
  await env.DB.prepare("DELETE FROM widget_tasks").run();
});

it("persists the claiming machine, exposes it to admins, and retains it after failure", async () => {
  const { taskID } = await createTask();
  const response = await pull(machine);
  expect(response.status).toBe(200);
  const { result: { task } } = await response.json() as { result: { task: { claimToken: string } } };
  const expected = { machine_name: machine.name, machine_platform: "Darwin", machine_cli_version: "0.1.0" };
  expect(await snapshot(taskID!)).toEqual(expected);
  const admin = await api("/api/admin/v2/tasks", { token: env.ADMIN_TOKEN });
  expect(await admin.json()).toMatchObject({ result: [expected] });
  expect((await api("/api/admin/v2/tasks")).status).toBe(401);
  expect((await taskStatus(taskID!)).body).not.toHaveProperty("machine_name");
  expect((await api(`/api/v2/widget-tasks/${taskID}/result`, { method: "POST", token: env.DEVELOPER_TEST_TOKEN,
    claim: task.claimToken, json: { status: "failed", errorCode: "worker_error" } })).status).toBe(200);
  expect(await snapshot(taskID!)).toEqual(expected);
});

it("only records the winning claimant when two machines compete", async () => {
  const { taskID } = await createTask();
  const names = ["Mac-A", "Mac-B"];
  const responses = await Promise.all(names.map(name => pull({ name })));
  const claims = await Promise.all(responses.map(r => r.json() as Promise<{ result: { task: unknown } }>));
  expect(claims.filter(c => c.result.task)).toHaveLength(1);
  expect(await snapshot(taskID!)).toMatchObject({ machine_name: names[claims.findIndex(c => c.result.task)] });
});

it("updates the machine on reallocation and clears it for older batch clients", async () => {
  const { taskID } = await createTask();
  await pull(machine);
  await expireLease(taskID!);
  expect((await pull({ name: "Linux-worker" })).status).toBe(200);
  expect(await snapshot(taskID!)).toEqual({ machine_name: "Linux-worker", machine_platform: null, machine_cli_version: null });
  await expireLease(taskID!);
  expect((await pull()).status).toBe(200);
  expect(await snapshot(taskID!)).toEqual({ machine_name: null, machine_platform: null, machine_cli_version: null });
});

it("clears a previous machine when a legacy token worker reclaims the task", async () => {
  const { taskID } = await createTask();
  await pull(machine);
  await expireLease(taskID!);
  const token = "machine-test-legacy";
  await env.DB.prepare("INSERT INTO widget_workers (id,widget_id,owner_id,token_hash,status,created_at) VALUES (?,?,?,?,?,?)")
    .bind("machine-test-legacy", WIDGET_ID, "admin", await sha256Hex(`${env.WORKER_TOKEN_PEPPER}:${token}`), "active", new Date().toISOString()).run();
  const result = await api(`/api/v2/widget-tasks/pull?widget_id=${WIDGET_ID}&wait=1`, { token });
  expect(await result.json()).toMatchObject({ result: { task: { taskId: taskID } } });
  expect(await snapshot(taskID!)).toEqual({ machine_name: null, machine_platform: null, machine_cli_version: null });
});

it.each([null, [], "Mac", {}, { name: " " }, { name: 123 }, { name: "a".repeat(256) },
  { name: "Mac\nspoof" }, { name: "Mac", platform: false }, { name: "Mac", cliVersion: "a".repeat(65) }])(
  "rejects invalid machine metadata before claiming: %j", async info => {
    const { taskID } = await createTask();
    const response = await pull(info);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: { code: "invalid_machine" } });
    expect((await taskStatus(taskID!)).body.status).toBe("queued");
  }
);

it("machine information does not authorize an unauthenticated worker", async () => {
  const { taskID } = await createTask();
  expect((await pull(machine, "invalid-token")).status).toBe(401);
  expect((await taskStatus(taskID!)).body.status).toBe("queued");
});
