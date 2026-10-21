import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const client = readFileSync(new URL("../../app.js", import.meta.url), "utf8");
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");

test("farmer onboarding sends fields accepted by the API", () => {
  assert.match(client, /api\("profile",\s*\{\s*display_name:\s*displayName,\s*phone_e164:\s*phone,\s*preferred_locale:/);
  assert.match(api, /body\.display_name/);
  assert.match(api, /body\.phone_e164/);
  assert.match(api, /body\.preferred_locale/);
});

test("QR claim sends server-required token and request id", () => {
  assert.match(client, /api\("claim",\s*\{\s*token,\s*request_id:\s*crypto\.randomUUID\(\)\s*\}\)/);
  assert.match(api, /body\.token/);
  assert.match(api, /body\.request_id/);
  assert.match(api, /rewardloop_claim_qr_internal/);
});

test("redemption sends the request key required by the API", () => {
  assert.match(client, /api\("redeem",\s*\{\s*reward_id:\s*rewardId,\s*request_key:\s*crypto\.randomUUID\(\)\s*\}\)/);
  assert.match(api, /body\.reward_id/);
  assert.match(api, /body\.request_key/);
  assert.match(api, /rewardloop_redeem_internal/);
});

test("privileged admin actions require active tenant admin membership", () => {
  assert.match(api, /tenant_memberships/);
  assert.match(api, /\.eq\("status",\s*"active"\)/);
  assert.match(api, /\.in\("role",\s*\["brand_admin",\s*"super_admin"\]\)/);
  assert.match(api, /admin_access_required/);
});

test("browser API client never embeds a service-role credential", () => {
  assert.doesNotMatch(client, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
  assert.match(api, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("account balance is summed across ledger pages, not only the recent activity feed", () => {
  assert.match(client, /async function loadPointsBalance\(tenantId, partnerId\)/);
  assert.match(client, /\.range\(offset, offset \+ pageSize - 1\)/);
  assert.match(client, /loadPointsBalance\(tenant\.id, state\.profile\.id\)/);
  assert.match(client, /state\.balance = balance;/);
  assert.doesNotMatch(client, /state\.balance = state\.ledger\.reduce/);
});

test("CORS has only the canonical production origin by default", () => {
  assert.match(api, /DEFAULT_ALLOWED_ORIGINS\s*=\s*\["https:\/\/bigagri\.vercel\.app"\]/);
  assert.match(api, /CONFIGURED_ALLOWED_ORIGINS/);
  assert.doesNotMatch(api, /https:\/\/growta-rewardloop(?:-git-main-acme-bce0|-acme-bce0)?\.vercel\.app/);
});
