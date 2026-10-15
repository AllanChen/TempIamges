import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { api, sha256Hex } from "./helpers";

describe("consumer authentication", () => {
  it("exchanges a one-use native code for a revocable app session", async () => {
    const code = `${crypto.randomUUID()}${crypto.randomUUID()}`;
    await env.DB.prepare("INSERT INTO app_auth_codes(code_hash,user_id,expires_at) VALUES(?,?,?)")
      .bind(await sha256Hex(code), 1, new Date(Date.now() + 60_000).toISOString()).run();
    const exchanged = await api("/auth/native/exchange", { method: "POST", json: { code } });
    expect(exchanged.status).toBe(200);
    const body = await exchanged.json() as { result: { token: string; user: { id: number; email: string } } };
    expect(body.result.user).toMatchObject({ id: 1, email: "test@example.com" });
    expect((await api("/auth/native/exchange", { method: "POST", json: { code } })).status).toBe(401);
    expect((await api("/auth/me", { token: body.result.token })).status).toBe(200);
    expect((await api("/auth/logout", { method: "POST", token: body.result.token })).status).toBe(200);
    expect((await api("/auth/me", { token: body.result.token })).status).toBe(401);
  });

  it("rejects malformed login payloads without a server error", async () => {
    expect((await api("/auth/native/exchange", { method: "POST", body: "{invalid" })).status).toBe(400);
    expect((await api("/auth/email/verify-code", { method: "POST", json: { email: "bad", code: "12" } })).status).toBe(401);
  });
});
