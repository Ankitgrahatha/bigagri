import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(new URL("../migrations/20261023220000_tenant_admin_invitations.sql", import.meta.url), "utf8");
const api = readFileSync(new URL("../functions/rewardloop-api/index.ts", import.meta.url), "utf8");
const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const release = readFileSync(new URL("../../.github/workflows/rewardloop-production-release.yml", import.meta.url), "utf8");
const quality = readFileSync(new URL("../../.github/workflows/rewardloop-quality-gate.yml", import.meta.url), "utf8");
const databaseWorkflow = readFileSync(new URL("../../.github/workflows/rewardloop-claim-replay-db.yml", import.meta.url), "utf8");

test("invitation records are tenant-bound, private, and constrained to valid lifecycle states", () => {
  assert.match(migration, /CREATE TABLE public\.tenant_invitations/);
  assert.match(migration, /tenant_id uuid NOT NULL REFERENCES public\.tenants\(id\) ON DELETE RESTRICT/);
  assert.match(migration, /token_hash text NOT NULL UNIQUE CHECK \(token_hash ~ '\^\[a-f0-9\]\{64\}\$'\)/);
  assert.match(migration, /CHECK \(status IN \('pending','accepted','revoked'\)\)/);
  assert.match(migration, /tenant_invitations_pending_email_idx[\s\S]*?WHERE status = 'pending'/);
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /FORCE ROW LEVEL SECURITY/);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON TABLE public\.tenant_invitations FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /GRANT ALL PRIVILEGES ON TABLE public\.tenant_invitations TO service_role/);
});

test("creating invitations requires an active tenant admin and audits expiry replacement", () => {
  assert.match(migration, /p_actor_user_id IS NULL OR p_tenant_id IS NULL/);
  assert.match(migration, /m\.status='active' AND m\.role IN \('brand_admin','super_admin'\)/);
  assert.match(migration, /WHERE t\.id=p_tenant_id AND t\.status='active'/);
  assert.match(migration, /already_tenant_admin/);
  assert.match(migration, /Expired pending invites must not permanently block a replacement invitation/);
  assert.match(migration, /tenant_invitation_expired/);
  assert.match(migration, /tenant_invitation_created/);
  assert.match(migration, /EXCEPTION WHEN unique_violation/);
  assert.doesNotMatch(migration, /INSERT INTO public\.tenant_invitations[^;]*\btoken\b/i);
});

test("acceptance binds a one-time hash to the authenticated, confirmed email owner", () => {
  assert.match(migration, /FROM auth\.users WHERE id=p_actor_user_id/);
  assert.match(migration, /IF v_email_confirmed_at IS NULL THEN[\s\S]*?email_not_confirmed/);
  assert.match(migration, /WHERE token_hash=p_token_hash FOR UPDATE/);
  assert.match(migration, /v_invitation\.email <> v_user_email/);
  assert.match(migration, /role=v_invitation\.role::public\.partner_role FOR UPDATE/);
  assert.match(migration, /v_invitation\.role::public\.partner_role,'active'/);
  assert.match(migration, /invitation_email_mismatch/);
  assert.match(migration, /v_invitation\.expires_at <= now\(\)/);
  assert.match(migration, /tenant_invitation_accepted/);
  assert.match(migration, /already_accepted/);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON FUNCTION public\.rewardloop_accept_tenant_invitation_internal\(uuid,text\)\s+FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.rewardloop_accept_tenant_invitation_internal\(uuid,text\) TO service_role/);
});

test("revocation is tenant-scoped, reasoned, lock-protected, and refuses accepted invitations", () => {
  const revoke = migration.slice(migration.indexOf("CREATE OR REPLACE FUNCTION private.revoke_tenant_invitation"), migration.indexOf("CREATE OR REPLACE FUNCTION public.rewardloop_revoke_tenant_invitation_internal"));
  assert.match(revoke, /m\.tenant_id=p_tenant_id AND m\.user_id=p_actor_user_id/);
  assert.match(revoke, /length\(v_reason\) < 5 OR length\(v_reason\) > 500/);
  assert.match(revoke, /WHERE id=p_invitation_id AND tenant_id=p_tenant_id FOR UPDATE/);
  assert.match(revoke, /invitation_already_accepted/);
  assert.match(revoke, /tenant_invitation_revoked/);
  assert.match(revoke, /before_data/);
  assert.match(revoke, /after_data/);
});

test("API hashes random one-time tokens and gates every invitation admin action by tenant membership", () => {
  assert.match(api, /accept_tenant_invitation: \{ limit: 5, windowSeconds: 900 \}/);
  assert.match(api, /create_tenant_invitation: \{ limit: 5, windowSeconds: 60 \}/);
  assert.match(api, /revoke_tenant_invitation: \{ limit: 10, windowSeconds: 60 \}/);
  assert.match(api, /crypto\.getRandomValues\(tokenBytes\)/);
  assert.match(api, /crypto\.subtle\.digest\("SHA-256"/);
  assert.match(api, /rewardloop_create_tenant_invitation_internal/);
  assert.match(api, /rewardloop_accept_tenant_invitation_internal/);
  assert.match(api, /rewardloop_revoke_tenant_invitation_internal/);
  assert.match(api, /const inviteOrigin = origin && ALLOWED_ORIGINS\.has\(origin\)/);
  const adminGate = api.indexOf("if ([\"admin_dashboard\"");
  const membershipCheck = api.indexOf('.eq("tenant_id", tenant.id).eq("user_id", user.id)', adminGate);
  const invitationList = api.indexOf('if (action === "admin_tenant_invitations")', adminGate);
  assert.ok(adminGate >= 0 && membershipCheck > adminGate && invitationList > membershipCheck);
});

test("invite links survive sign-in, open the invited tenant, and are not placed in query strings", () => {
  assert.match(admin, /new URLSearchParams\(location\.hash\.slice\(1\)\)/);
  assert.match(admin, /history\.replaceState\(null,\"\",location\.pathname\+location\.search\)/);
  assert.match(admin, /if\(!authState\?\.session\)[\s\S]*?loginView\(\"Sign in with the exact email address that received this invitation/);
  assert.match(admin, /selectedTenantSlug=accepted\.tenant_slug/);
  assert.match(admin, /else loginView\(pendingInviteToken\?/);
  assert.match(admin, /Tenant access &amp; invitations/);
  assert.match(admin, /Copy link/);
  assert.match(admin, /Hide link/);
  assert.match(admin, /data-invitation-revoke/);
  assert.match(admin, /securely/);
});

test("invitation migration is release-allowlisted and has both static and disposable-Postgres coverage", () => {
  assert.match(release, /20261023220000/);
  assert.match(quality, /rewardloop_tenant_invitation_workflow_contract\.test\.mjs/);
  assert.match(databaseWorkflow, /rewardloop_tenant_invitation_behavior\.test\.sql/);
});

