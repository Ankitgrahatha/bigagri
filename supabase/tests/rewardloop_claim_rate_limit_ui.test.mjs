import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../../app.js", import.meta.url), "utf8");

test("invalid QR rate-limit outcome shows an explicit cooldown message", () => {
  assert.match(app, /rate_limited:"claimRateLimited"/);
  assert.match(app, /claimRateLimited:"बहुत अधिक गलत QR प्रयास हुए हैं/);
  assert.match(app, /claimRateLimited:"Too many invalid QR attempts/);
});
