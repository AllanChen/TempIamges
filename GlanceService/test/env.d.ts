import type { D1Migration } from "@cloudflare/vitest-pool-workers";
import type { Env as ServiceEnv } from "../src/index";

declare global {
  namespace Cloudflare {
    interface Env extends ServiceEnv {
      TEST_MIGRATIONS: D1Migration[];
    }
  }
}
