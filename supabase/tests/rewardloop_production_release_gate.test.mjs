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
