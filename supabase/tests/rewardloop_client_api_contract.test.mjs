import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const client = readFileSync(new URL("../../app.js", import.meta.url), "utf8");
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");

test("farmer onboarding sends fields accepted by the API", () => {
    assert.match(client, /api\("profile",\s*\{\s*tenant_slug:\s*TENANT_SLUG,\s*display_name:\s*displayName,\s*phone_e164:\s*phone,\s*preferred_locale:/);
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

test("API rejects missing bearer tokens before invoking any business operation", () => {
  const missingBearer = api.indexOf('if (!authHeader?.startsWith("Bearer "))');
  const firstBusinessAction = api.indexOf('if (action === "profile")');
  assert.notEqual(missingBearer, -1, "missing-bearer guard must exist");
  assert.ok(firstBusinessAction > missingBearer, "business actions must be unreachable before the bearer guard");
  assert.match(api, /return reply\(401, \{ ok: false, error: "authentication_required" \}\)/);
});

test("caller identity is derived from Supabase Auth, never a request-body user id", () => {
  assert.match(api, /userClient\.auth\.getUser\(\)/);
  assert.match(api, /p_actor_user_id:\s*user\.id/);
  assert.doesNotMatch(api, /p_actor_user_id:\s*body\.(?:user_id|actor_user_id)/);
});

test("disallowed origins are rejected before authentication and business logic", () => {
  const originGuard = api.indexOf("if (!originAllowed)");
  const authGuard = api.indexOf('if (!authHeader?.startsWith("Bearer "))');
  const businessAction = api.indexOf('if (action === "profile")');
  assert.notEqual(originGuard, -1, "origin allowlist guard must exist");
  assert.ok(authGuard > originGuard, "origin allowlist must be checked before auth");
  assert.ok(businessAction > originGuard, "origin allowlist must be checked before business actions");
  assert.match(api, /return new Response\(null, \{ status: 403/);
});

test("unexpected API errors are not returned verbatim to clients", () => {
  assert.match(api, /catch \{\s*\/\/ Avoid returning raw exception details or credentials to the client\.\s*return reply\(500, \{ ok: false, error: "unexpected_server_error" \}\);/);
});

test("tenant scope is selected server-side and never accepted as an API authority field", () => {
  assert.match(api, /const requestedTenantSlug = typeof body\.tenant_slug === "string" \? body\.tenant_slug\.trim\(\) : TENANT_SLUG/);
  assert.match(api, /tenant_slug_invalid/);
  assert.match(api, /\.eq\("slug", requestedTenantSlug\)/);
  assert.match(api, /tenant\.public_catalog_enabled !== true/);
  assert.doesNotMatch(api, /\.eq\("tenant_id",\s*body\.tenant_id\)/);
});

test("main API bounds request bodies before JSON parsing and rejects malformed shapes", () => {
  assert.match(api, /MAX_REQUEST_BODY_BYTES = 64 \* 1024/);
  assert.match(api, /async function readLimitedJson\(req: Request\)/);
  assert.match(api, /total > MAX_REQUEST_BODY_BYTES/);
  assert.match(api, /parsedBody\.tooLarge \? 413 : 400/);
  assert.match(api, /!parsedBody\.value \|\| typeof parsedBody\.value !== "object" \|\| Array\.isArray\(parsedBody\.value\)/);
  assert.doesNotMatch(api, /const body = await req\.json\(\)/);
});
