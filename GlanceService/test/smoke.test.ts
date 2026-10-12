import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

describe("smoke", () => {
  it("GET /health returns 200", async () => {
    const response = await SELF.fetch("https://example.com/health");
    expect(response.status).toBe(200);
  });

  it("GET /api/v2/widgets returns an array", async () => {
    const response = await SELF.fetch("https://example.com/api/v2/widgets");
    expect(response.status).toBe(200);
    const body = await response.json() as { result: { widgets: unknown } };
    expect(Array.isArray(body.result.widgets)).toBe(true);
  });
});
