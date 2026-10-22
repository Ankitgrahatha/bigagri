import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL("../functions/rewardloop-api/index.ts", import.meta.url),
  "utf8",
);

test("Upstash rate limiting is optional until server-side secrets are configured", () => {
  assert.match(source, /UPSTASH_REDIS_REST_URL/);
  assert.match(source, /UPSTASH_REDIS_REST_TOKEN/);
  assert.match(source, /if \(!rawUrl \|\| !token\) return \{ allowed: true, configured: false \}/);
  assert.match(source, /endpoint\.protocol !== "https:"/);
  assert.match(source, /endpoint\.hostname\.endsWith\("\.upstash\.io"\)/);
});

test("rate limiting is atomic and tenant/action/actor scoped", () => {
  assert.match(source, /redis\.call\('INCR', KEYS\[1\]\)/);
  assert.match(source, /redis\.call\('EXPIRE', KEYS\[1\], ARGV\[1\]\)/);
  assert.match(source, /rewardloop:v1:\$\{TENANT_SLUG\}:\$\{action\}:\$\{actorId\}/);
  assert.match(source, /status: 429/);
  assert.match(source, /"Retry-After"/);
});

test("Redis outage does not replace database transaction safeguards or log secrets", () => {
  assert.match(source, /Database constraints and the existing\s+// invalid-token counter remain authoritative/);
  assert.match(source, /Fail open to existing database-level protections when Redis is unavailable/);
  assert.doesNotMatch(source, /console\.(?:log|error|warn)\([^\n]*(?:token|rawUrl|actorId)/i);
});

test("only explicitly listed API actions are rate limited", () => {
  const start = source.indexOf("const ratePolicy:");
  const end = source.indexOf("const policy = ratePolicy[action]", start);
  assert.ok(start >= 0 && end > start, "rate policy block exists");
  const policy = source.slice(start, end);
  for (const action of ["profile", "claim", "redeem", "admin_dashboard", "issue_qr_batch", "resolve_redemption", "admin_record_export"]) {
    assert.match(policy, new RegExp(action + ":"));
  }
});
