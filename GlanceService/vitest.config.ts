import { defineConfig } from "vitest/config";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";

export default defineConfig(async () => {
  const migrations = await readD1Migrations("migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          // nodejs_compat is needed only by the test runner, not by production.
          compatibilityFlags: ["nodejs_compat"],
          // The pool's bundled workerd can lag behind wrangler.toml's compatibility_date.
          compatibilityDate: "2026-08-01",
          bindings: {
            TEST_MIGRATIONS: migrations,
            // Test-only values. Never reuse these for a deployed environment.
            SESSION_SECRET: "test-session-secret",
            MEDIA_SIGNING_SECRET: "test-media-signing-secret",
            WORKER_TOKEN_PEPPER: "test-worker-token-pepper",
            FLOW_TEST_TOKEN: "test-flow-token",
            DEVELOPER_TEST_TOKEN: "test-developer-token",
            ADMIN_TOKEN: "test-admin-token",
            ADMIN_USERNAME: "test-admin",
            ADMIN_PASSWORD: "test-admin-password",
            ADMIN_PATH: "test-admin-path"
          }
        }
      })
    ],
    test: {
      setupFiles: ["./test/setup.ts"]
    }
  };
});
