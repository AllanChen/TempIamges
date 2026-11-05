import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, createTask, seedWidget, sha256Hex, USER_TOKEN, WIDGET_ID } from "./helpers";
import { userRoutes } from "../src/users";
import { OFFICIAL_MANIFESTS } from "../src/official";

beforeEach(async () => {
  await seedWidget();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM billing_events"),env.DB.prepare("DELETE FROM billing_trials"),
    env.DB.prepare("DELETE FROM widget_tasks"), env.DB.prepare("DELETE FROM user_credit_ledger"),env.DB.prepare('DELETE FROM signup_devices'),
    env.DB.prepare("DELETE FROM user_email_codes"), env.DB.prepare("DELETE FROM user_auth_limits"),
    env.DB.prepare("DELETE FROM user_auth_codes"), env.DB.prepare("DELETE FROM user_oauth_states"),
    env.DB.prepare("DELETE FROM user_sessions WHERE user_id>3"), env.DB.prepare("DELETE FROM users WHERE id>3"),
    env.DB.prepare("DELETE FROM service_settings WHERE key='task_queue_limit'")
  ]);
});
afterEach(() => { vi.restoreAllMocks(); });

async function emailCode(email = "member@example.com", code = "123456") {
  await env.DB.prepare("INSERT OR REPLACE INTO user_email_codes(email,code_hash,attempts,expires_at,sent_at) VALUES(?,?,0,?,?)")
    .bind(email, await sha256Hex(`${env.SESSION_SECRET}:${email}:${code}`), new Date(Date.now()+600000).toISOString(), new Date().toISOString()).run();
}
const verify = (code = "123456", email = "member@example.com") => api("/auth/email/verify-code", { method: "POST", headers:{'X-Glance-Device':'test-signup-device-001'},json: { email, code } });
async function balance() {
  return (await env.DB.prepare("SELECT credits FROM users WHERE id=1").first<{ credits: number }>())!.credits;
}
async function price(credits: number) {
  const row = await env.DB.prepare("SELECT manifest_json FROM widget_versions WHERE id='version_test'").first<{ manifest_json: string }>();
  const manifest = { ...JSON.parse(row!.manifest_json), creditCost: credits };
  await env.DB.prepare("UPDATE widget_versions SET manifest_json=? WHERE id='version_test'").bind(JSON.stringify(manifest)).run();
}
const submit = (key = crypto.randomUUID(), extra: Record<string, unknown> = {}) => api("/api/v2/widget-jobs", {
  method: "POST", token: USER_TOKEN, headers: { "Idempotency-Key": key },
  json: { widgetID: WIDGET_ID, commandID: "run", input: { url: "https://example.com/a.png" }, ...extra }
});

describe("user authentication", () => {
  it("rejects arbitrary, developer, expired and revoked bearer tokens", async () => {
    for (const token of ["made-up-token", env.DEVELOPER_TEST_TOKEN, env.FLOW_TEST_TOKEN]) {
      expect((await api("/auth/me", { token })).status).toBe(401);
      expect((await api("/api/v2/tasks", { method: "POST", token, json: {} })).status).toBe(401);
    }
    expect((await api("/auth/me", { token: USER_TOKEN })).status).toBe(200);
    await env.DB.prepare("UPDATE user_sessions SET expires_at='2000-01-01T00:00:00Z' WHERE user_id=1").run();
    expect((await api("/auth/me", { token: USER_TOKEN })).status).toBe(401);
  });

  it("verifies an email once, stores only a token hash, and revokes logout on the server", async () => {
    await emailCode();
    const response = await verify();
    expect(response.status).toBe(200);
    const { result } = await response.json() as { result: { token: string; user: { id: number; credits: number } } };
    expect(result.user.credits).toBe(100);
    expect(await env.DB.prepare("SELECT token_hash FROM user_sessions WHERE token_hash=?").bind(result.token).first()).toBeNull();
    expect((await api("/auth/me", { token: result.token })).status).toBe(200);
    expect((await verify()).status).toBe(401);
    expect((await api("/auth/logout", { method: "POST", token: result.token })).status).toBe(200);
    expect((await api("/auth/me", { token: result.token })).status).toBe(401);
  });

  it("grants signup credits only once across subsequent logins", async () => {
    await emailCode(); await verify();
    await emailCode();
    const result = await (await verify()).json() as { result: { user: { credits: number } } };
    expect(result.result.user.credits).toBe(100);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM user_credit_ledger WHERE reason='signup_bonus'").first<{ n: number }>())!.n).toBe(1);
  });

  it("keeps tasks and credits on the same user when a new login issues a different token", async () => {
    await emailCode();
    const first = await (await verify()).json() as { result: { token: string; user: { id: number } } };
    const taskResponse = await api("/api/v2/tasks", { method: "POST", token: first.result.token,
      json: { widgetID: WIDGET_ID, commandID: "run", input: { url: "https://example.com/a.png" } } });
    const task = await taskResponse.json() as { result: { taskID: string } };
    expect(taskResponse.status).toBe(202);
    await emailCode();
    const second = await (await verify()).json() as { result: { token: string; user: { id: number; credits: number } } };
    expect(second.result.token).not.toBe(first.result.token);
    expect(second.result.user.id).toBe(first.result.user.id);
    expect(second.result.user.credits).toBe(99);
    expect((await api(`/api/v2/tasks/${task.result.taskID}`, { token: second.result.token })).status).toBe(200);
  });

  it("honors zero signup credits without granting a later bonus", async () => {
    await emailCode();
    const request = () => new Request("https://example.com/auth/email/verify-code", { method: "POST",headers:{'X-Glance-Device':'test-signup-device-001'}, body: JSON.stringify({ email: "member@example.com", code: "123456" }) });
    const first = await userRoutes({ ...env, NEW_USER_CREDITS: "0" }, request());
    expect(await first!.json()).toMatchObject({ result: { user: { credits: 0 } } });
    await emailCode();
    const second = await userRoutes({ ...env, NEW_USER_CREDITS: "100" }, request());
    expect(await second!.json()).toMatchObject({ result: { user: { credits: 0 } } });
  });

  it("reports code attempts separately from an expired or exhausted code",async()=>{
    await emailCode();
    const first=await verify("000000");expect(await first.json()).toMatchObject({error:{code:"invalid_code",details:{attemptsRemaining:4}}});
    for(let i=0;i<3;i++)await verify("000000");
    expect(await (await verify("000000")).json()).toMatchObject({error:{code:"code_unavailable"}});
    expect(await (await verify()).json()).toMatchObject({error:{code:"code_unavailable"}});
    await emailCode();for(let i=0;i<4;i++)await verify("000000");expect((await verify()).status).toBe(200);
  });
  it("limits guesses, expires codes, rejects disabled users, and consumes codes atomically", async () => {
    await emailCode();
    for (let i=0; i<5; i++) expect((await verify("000000")).status).toBe(401);
    expect((await verify()).status).toBe(401);
    await emailCode();
    await env.DB.prepare("UPDATE user_email_codes SET expires_at='2000-01-01T00:00:00Z'").run();
    expect((await verify()).status).toBe(401);
    await emailCode();
    const results = await Promise.all([verify(), verify()]);
    expect(results.map(r=>r.status).sort()).toEqual([200,401]);
    await env.DB.prepare("UPDATE users SET status='disabled' WHERE email='member@example.com'").run();
    await emailCode();
    expect((await verify()).status).toBe(403);
  });

  it("sends the email through the configured provider without exposing the code, and throttles resends", async () => {
    const delivery = vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({ id: "sent" }));
    const send = async () => (await userRoutes(env, new Request("https://example.com/auth/email/send-code", {
      method: "POST", body: JSON.stringify({ email: "member@example.com" })
    })))!;
    const response = await send();
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(JSON.parse(text)).toMatchObject({ result: { email: "member@example.com" } });
    expect(text).not.toContain("code_hash");
    expect((await send()).status).toBe(429);
    expect(delivery).toHaveBeenCalledOnce();
    expect(delivery.mock.calls[0][0]).toBe("https://api.resend.com/emails");
    const sent = JSON.parse(delivery.mock.calls[0][1]!.body as string) as { text: string };
    const code = sent.text.match(/code is (\d{6})/)![1];
    expect(text).not.toContain(code);
    expect((await verify(code)).status).toBe(200);
  });

  it("uses OAuth state and PKCE, so intercepted callback codes cannot be exchanged or reused", async () => {
    const state = "s".repeat(32), challenge = "c".repeat(43);
    expect((await api("/auth/google")).status).toBe(400);
    const start = await api(`/auth/google?state=${state}&code_challenge=${challenge}`, { redirect: "manual" });
    expect(start.status).toBe(302);
    const google = new URL(start.headers.get("Location")!);
    expect(google.hostname).toBe("accounts.google.com");
    const callbackState = google.searchParams.get("state");
    const cancelled = await api(`/auth/google/callback?state=${callbackState}`, { redirect: "manual" });
    expect(cancelled.status).toBe(302);
    expect(new URL(cancelled.headers.get("Location")!).searchParams.get("state")).toBe(state);
    expect((await api(`/auth/google/callback?state=${callbackState}`, { redirect: "manual" })).status).toBe(400);
    const verifier = "v".repeat(64);
    const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
    const expected = btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
    await env.DB.prepare("INSERT INTO user_auth_codes(code_hash,user_id,code_challenge,expires_at) VALUES(?,1,?,?)")
      .bind(await sha256Hex("native-code"), expected, new Date(Date.now()+60000).toISOString()).run();
    const exchange = (code_verifier: string) => api("/auth/native/exchange", { method: "POST", json: { code: "native-code", code_verifier } });
    expect((await exchange("wrong".repeat(12))).status).toBe(401);
    expect((await exchange(verifier)).status).toBe(200);
    expect((await exchange(verifier)).status).toBe(401);
  });

  it("completes Google login and joins a verified email account without awarding signup credits twice", async () => {
    await emailCode();
    const emailSession = await (await verify()).json() as { result: { user: { id: number } } };
    const verifier = "v".repeat(64);
    const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
    const challenge = btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
    await env.DB.prepare("INSERT INTO user_oauth_states(state_hash,client_state,code_challenge,expires_at) VALUES(?,?,?,?)")
      .bind(await sha256Hex("google-state"), "s".repeat(32), challenge, new Date(Date.now()+60000).toISOString()).run();
    const outgoing = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(Response.json({ access_token: "google-access" }))
      .mockResolvedValueOnce(Response.json({ sub: "google-member", email: "member@example.com", email_verified: true, name: "Member" }));
    const callback = await userRoutes(env, new Request("https://example.com/auth/google/callback?state=google-state&code=google-code"));
    expect(callback!.status).toBe(302);
    const nativeCode = new URL(callback!.headers.get("Location")!).searchParams.get("code");
    expect(nativeCode).toBeTruthy();
    expect(outgoing).toHaveBeenCalledTimes(2);
    outgoing.mockRestore();
    const exchange = await api("/auth/native/exchange", { method: "POST", json: { code: nativeCode, code_verifier: verifier } });
    expect(await exchange.json()).toMatchObject({ result: { user: { id: emailSession.result.user.id, google_id: "google-member", credits: 100 } } });
  });
});

describe("Widget credit billing", () => {
  it("initializes legacy prices without retaining invalid third-party signatures or changing existing task charges", async () => {
    await price(7);
    const task = await (await submit()).json() as { result: { taskID: string } };
    await env.DB.prepare("UPDATE widget_versions SET manifest_json=json_set(manifest_json,'$.official',json('false'),'$.signature',json(?)) WHERE id='version_test'")
      .bind(JSON.stringify({ algorithm: "Ed25519", keyID: "old", value: "old-signature" })).run();
    const migration = env.TEST_MIGRATIONS.find(m => m.name === "0011_widget_credit_prices.sql")!;
    expect(migration).toBeDefined();
    await env.DB.batch(migration.queries.map(query => env.DB.prepare(query)));
    const row = await env.DB.prepare("SELECT manifest_json FROM widget_versions WHERE id='version_test'").first<{ manifest_json: string }>();
    expect(JSON.parse(row!.manifest_json)).toMatchObject({ creditCost: 1, official: false });
    expect(JSON.parse(row!.manifest_json).signature).toBeUndefined();
    expect(await env.DB.prepare("SELECT credit_cost FROM widget_tasks WHERE id=?").bind(task.result.taskID).first()).toEqual({ credit_cost: 7 });
    expect(await balance()).toBe(9993);
  });

  it("lets only admins edit the price, exposes it in the catalog, and charges the saved amount", async () => {
    const { creditCost: _price, ...manifest } = OFFICIAL_MANIFESTS[0];
    const created = await api("/api/admin/v2/widgets", { method: "POST", token: env.ADMIN_TOKEN, json: { manifest, status: "published" } });
    expect(created.status).toBe(201);
    const { result } = await created.json() as { result: { widgetId: string; commandIds: string[] } };
    const catalog = async () => {
      const response = await api(`/api/v2/widgets/${result.widgetId}`);
      return await response.json() as { result: Record<string, unknown> };
    };
    expect(await catalog()).toMatchObject({ result: { creditCost: 1 } });
    const edited = { ...manifest, creditCost: 4 };
    const update = (token: string, creditCost = 4) => api(`/api/admin/v2/widgets/${result.widgetId}`, {
      method: "PUT", token, json: { manifest: { ...edited, creditCost }, status: "published" }
    });
    expect((await update(USER_TOKEN)).status).toBe(401);
    expect((await update(env.ADMIN_TOKEN, -1)).status).toBe(422);
    expect((await update(env.ADMIN_TOKEN)).status).toBe(200);
    expect(await catalog()).toMatchObject({ result: { creditCost: 4 } });
    const submitPriced = (expectedCreditCost: number) => submit(undefined, {
      widgetID: result.widgetId, commandID: result.commandIds[0], expectedCreditCost
    });
    expect((await submitPriced(1)).status).toBe(409);
    const charged = await submitPriced(4);
    expect(charged.status).toBe(202);
    expect(await charged.json()).toMatchObject({ result: { creditCost: 4, balance: 9996 } });
    expect(await balance()).toBe(9996);
    expect(await catalog()).toMatchObject({ result: { creditCost: 4 } });
    expect((await update(env.ADMIN_TOKEN, 0)).status).toBe(200);
    expect(await catalog()).toMatchObject({ result: { creditCost: 0 } });
    await env.DB.prepare("UPDATE users SET credits=0 WHERE id=1").run();
    const free = await submitPriced(0);
    expect(free.status).toBe(202);
    expect(await free.json()).toMatchObject({ result: { creditCost: 0, balance: 0 } });
  });

  it("charges the published developer price, records a ledger entry, and ignores a spoofed price", async () => {
    await price(7);
    const result = await (await submit(undefined, { creditCost: 0 })).json() as { result: { taskID: string } };
    expect(await balance()).toBe(9993);
    expect(await env.DB.prepare("SELECT amount,reason,task_id FROM user_credit_ledger WHERE user_id=1").first())
      .toEqual({ amount: -7, reason: "widget_task", task_id: result.result.taskID });
    expect((await env.DB.prepare("SELECT credit_cost FROM widget_tasks WHERE id=?").bind(result.result.taskID).first<{ credit_cost: number }>())!.credit_cost).toBe(7);
    const history = await api("/api/v2/account/credits", { token: USER_TOKEN });
    expect(await history.json()).toMatchObject({ result: { balance: 9993, transactions: [{ amount: -7 }] } });
  });

  it("defaults old manifests to one credit and rejects negative production prices", async () => {
    expect((await createTask()).response.status).toBe(202);
    expect(await balance()).toBe(9999);
    await price(-1);
    expect((await submit()).status).toBe(409);
    expect(await balance()).toBe(9999);
  });

  it("accepts free tasks with zero balance and keeps retries free without credit entries", async () => {
    await price(0);
    await env.DB.prepare("UPDATE users SET credits=0 WHERE id=1").run();
    const key = crypto.randomUUID();
    const first = await submit(key, { expectedCreditCost: 0 });
    expect(first.status).toBe(202);
    const body = await first.json() as { result: { taskID: string } };
    expect(body).toMatchObject({ result: { creditCost: 0, balance: 0 } });
    const retry = await submit(key, { expectedCreditCost: 0 });
    expect(retry.status).toBe(202);
    expect(await retry.json()).toMatchObject({ result: { taskID: body.result.taskID, creditCost: 0, balance: 0 } });
    expect(await env.DB.prepare("SELECT credit_cost FROM widget_tasks WHERE id=?").bind(body.result.taskID).first()).toEqual({ credit_cost: 0 });
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM user_credit_ledger").first<{ n: number }>())!.n).toBe(0);
    expect(await balance()).toBe(0);
  });

  it("rejects insufficient balance without a task or ledger change", async () => {
    await price(5);
    await env.DB.prepare("UPDATE users SET credits=4 WHERE id=1").run();
    const response = await submit();
    expect(response.status).toBe(402);
    expect(await response.json()).toMatchObject({ error: { code: "insufficient_credits" } });
    expect(await balance()).toBe(4);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM widget_tasks").first<{ n: number }>())!.n).toBe(0);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM user_credit_ledger").first<{ n: number }>())!.n).toBe(0);
  });

  it("prevents concurrent overspending and duplicate charges on retries", async () => {
    await price(5);
    await env.DB.prepare("UPDATE users SET credits=5 WHERE id=1").run();
    const key = crypto.randomUUID();
    const duplicates = await Promise.all([submit(key), submit(key)]);
    expect(duplicates.map(r=>r.status)).toEqual([202,202]);
    const bodies = await Promise.all(duplicates.map(r=>r.json())) as { result: { taskID: string } }[];
    expect(bodies[0].result.taskID).toBe(bodies[1].result.taskID);
    expect(await balance()).toBe(0);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM user_credit_ledger WHERE reason='widget_task'").first<{ n: number }>())!.n).toBe(1);
    expect((await submit(key, { parameters: { prompt: "changed" } })).status).toBe(409);
    await env.DB.prepare("UPDATE users SET credits=5 WHERE id=1").run();
    const racing = await Promise.all([submit(), submit()]);
    expect(racing.map(r=>r.status).sort()).toEqual([202,402]);
    expect(await balance()).toBe(0);
  });

  it("does not charge rejected input, price changes, or a full queue", async () => {
    expect((await submit(undefined, { commandID: "missing" })).status).toBe(400);
    expect((await submit(undefined, { expectedCreditCost: 999 })).status).toBe(409);
    expect(await balance()).toBe(10000);
    await env.DB.prepare("INSERT INTO service_settings(key,value,updated_at) VALUES('task_queue_limit','1',?)").bind(new Date().toISOString()).run();
    expect((await submit()).status).toBe(202);
    expect((await submit()).status).toBe(429);
    expect(await balance()).toBe(9999);
  });

  it("refunds queued cancellation, and keeps account history private", async () => {
    const { taskID } = await createTask();
    expect((await api(`/api/v2/tasks/${taskID}`, { method: "DELETE", token: USER_TOKEN })).status).toBe(200);
    expect(await balance()).toBe(10000);
    expect((await api(`/api/v2/tasks/${taskID}`, { token: "other-user" })).status).toBe(404);
    expect(await (await api("/api/v2/account/credits", { token: "other-user" })).json()).toMatchObject({ result: { balance: 10000, transactions: [] } });
  });

  it("allows only admins to grant credits and makes grants idempotent", async () => {
    const key = crypto.randomUUID();
    const grant = (token = env.ADMIN_TOKEN, amount = 20) => api("/api/admin/v2/users/1/credits", {
      method: "POST", token, headers: { "Idempotency-Key": key }, json: { amount, note: "Support grant" }
    });
    expect((await grant(USER_TOKEN)).status).toBe(401);
    expect((await grant()).status).toBe(200);
    expect((await grant()).status).toBe(200);
    expect(await balance()).toBe(10020);
    expect((await grant(undefined, 21)).status).toBe(409);
    expect((await api("/api/admin/v2/users", { token: USER_TOKEN })).status).toBe(401);
    expect((await api("/api/admin/v2/users", { token: env.ADMIN_TOKEN })).status).toBe(200);
  });

  it("leaves balance and ledger unchanged if the database rejects a task", async () => {
    await env.DB.exec("CREATE TRIGGER reject_test_task AFTER INSERT ON widget_tasks BEGIN SELECT RAISE(ABORT, 'test_rejection'); END;");
    try {
      expect((await submit()).status).toBe(500);
      expect(await balance()).toBe(10000);
      expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM user_credit_ledger").first<{ n: number }>())!.n).toBe(0);
    } finally { await env.DB.exec("DROP TRIGGER reject_test_task;"); }
  });

  it("does not bill administrator review tasks", async () => {
    await env.DB.prepare("INSERT INTO widget_tasks(id,widget_id,version_id,command_id,owner_id,type,input_json,status,created_at) VALUES('review_task',?,'version_test','run','admin','review_test','{}','queued',?)")
      .bind(WIDGET_ID, new Date().toISOString()).run();
    expect(await balance()).toBe(10000);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM user_credit_ledger").first<{ n: number }>())!.n).toBe(0);
  });

  it("rejects invalid developer pricing before saving a submission", async () => {
    for (const creditCost of [-1, 1.5, "3", true, null, 1000001]) {
      const response = await api("/api/v2/widget-submissions", { method: "POST", token: env.DEVELOPER_TEST_TOKEN,
        json: { manifest: { creditCost } } });
      expect(response.status).toBe(422);
      expect(await response.json()).toMatchObject({ error: { code: "invalid_manifest", message: expect.stringContaining("creditCost") } });
    }
  });
});
