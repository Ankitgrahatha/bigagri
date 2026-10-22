import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const read = (path) => readFileSync(new URL(path, root), "utf8");
const release = read("docs/PRODUCTION_RELEASE_GATE.md");
const readme = read("README.md");
const workflow = read(".github/workflows/rewardloop-quality-gate.yml");

test("production release gate explicitly blocks unsafe migration replay and reset", () => {
  assert.match(release, /Do not run `db reset --linked`/);
  assert.match(release, /Compare every migration file/);
  assert.match(release, /human review before applying production DDL/);
  assert.match(release, /backup\/restore evidence/);
});

test("release gate requires deployed SHA and production target verification", () => {
  assert.match(release, /production deployment SHA equals the intended merge SHA/);
  assert.match(release, /deployment target is `production`/);
  assert.match(release, /deployed Edge Function source\/version and JWT verification settings/);
});

test("release gate covers tenant authorization, financial integrity, and legacy route review", () => {
  assert.match(release, /active tenant membership and role server-side/);
  assert.match(release, /claim and redemption idempotency under retries and concurrency/);
  assert.match(release, /caller inventory/);
  assert.match(release, /leaked-password protection/);
});

test("README does not claim an unverified current production release", () => {
  assert.match(readme, /not yet a public-ready rewards programme/i);
  assert.match(readme, /production deployment SHA/i);
});

test("quality gate runs the production release gate contract", () => {
  assert.match(workflow, /rewardloop_production_release_gate\.test\.mjs/);
});

test("canonical API rejects non-JSON, malformed, non-object, and oversized request bodies", () => {
  const api = read("supabase/functions/rewardloop-api/index.ts");
  assert.match(api, /MAX_REQUEST_BODY_BYTES = 64 \* 1024/);
  assert.match(api, /content_type_required/);
  assert.match(api, /body_too_large/);
  assert.match(api, /invalid_json/);
  assert.match(api, /req\.headers\.get\("Content-Length"\)/);
  assert.match(api, /req\.body\.getReader\(\)/);
  assert.match(api, /JSON\.parse\(new TextDecoder\(\)\.decode\(bytes\)\)/);
  assert.match(api, /const parsedBody = await readJsonBody\(req\)/);
  assert.match(api, /parsedBody\.error === "body_too_large" \? 413/);
  assert.match(api, /parsedBody\.error === "content_type_required" \? 415/);
});
