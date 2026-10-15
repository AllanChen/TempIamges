import { env } from "cloudflare:workers";
import { applyD1Migrations } from "cloudflare:test";
import { beforeEach } from "vitest";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

beforeEach(async () => {
  const token = "user-token-a";
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${env.SESSION_SECRET}:${token}`));
  const tokenHash = Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const at = new Date().toISOString();
  await env.DB.prepare(`INSERT OR IGNORE INTO app_users(id,email,auth_provider,created_at,updated_at,last_login_at)
    VALUES(1,'test@example.com','email',?,?,?)`).bind(at, at, at).run();
  await env.DB.prepare("UPDATE wallets SET balance=10000 WHERE user_id=1").run();
  await env.DB.prepare("INSERT OR REPLACE INTO app_sessions(token_hash,user_id,expires_at,created_at) VALUES(?,?,?,?)")
    .bind(tokenHash, 1, new Date(Date.now() + 86_400_000).toISOString(), at).run();
});
