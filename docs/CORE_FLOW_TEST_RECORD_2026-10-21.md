# RewardLoop Core Flow Test Record — 2026-10-21

## Environment and safety

- Repository: `Ankitgrahatha/bigagri`, branch `main`
- Supabase project: `guhhuqxrobhuumwrypnc`
- Production checks were limited to read-only catalog/policy/privilege queries and invalid-input RPC calls. No real QR, balance, reward stock, payment, or campaign was mutated.
- Current live Edge Function inventory reports `rewardloop-api` version 9 with platform JWT verification enabled. This supersedes the older version-7 note below.
- This record is a safety snapshot, not production launch approval.

## Executed checks

| Check | Result | Evidence |
|---|---|---|
| RLS enabled on inspected core tables | PASS | Table catalog reports RLS enabled on inspected tables |
| Internal RPC privilege boundary | PASS | All eight `rewardloop_*_internal` functions deny EXECUTE to `anon` and `authenticated`, and allow `service_role` |
| Demo-campaign activation guard present | PASS | Existing catalog contract test checks the guard |
| Explicit client deny policy for QR codes | PASS | `qr_codes` policy denies client reads/writes |
| Claim RPC rejects null actor / invalid request safely | PASS | Returned `ok=false`, `outcome=invalid_request`, `points_awarded=0` |
| Redemption RPC rejects null actor / invalid request safely | PASS | Returned `ok=false`, `error=invalid_request` |
| Accepted-claim uniqueness guard | PASS | `claims_one_accepted_per_qr_idx` exists as a partial unique index |
| Claim and ledger idempotency guards | PASS | Unique indexes exist on tenant + idempotency key |
| Redemption idempotency guard | PASS | Unique index exists on tenant + request key |
| QR token uniqueness guard | PASS | Unique index exists on tenant + token hash |

The reusable catalog assertion is committed at `supabase/tests/rewardloop_security_contract.sql`.

## Phase 0 — additional read-only findings

### Security Advisor
- **WARN:** leaked-password protection is disabled. Enable it in Supabase Auth configuration and test signup/password-change behavior.
- **INFO:** `public.rewardloop_admin_settings` has RLS enabled but no RLS policies. This denies policy-based client access, but verify that only the intended server-side service path accesses settings and that no browser path expects direct table access.

### RLS policy review
- Tenant memberships, partner profiles, claims, ledger and redemptions have user-scoped SELECT policies; confirm tenant membership is also enforced in privileged API paths.
- Active campaigns, products and rewards have public SELECT policies for active records. Review whether public discovery across every tenant is intended; if not, change to a tenant-scoped public contract or a server-side API.
- The active-tenant SELECT policy allows discovery of all active tenant rows. Review whether exposing tenant names/slugs/status is necessary.
- Explicit client-deny policies exist for audit logs, production batches, QR codes, QR issuance batches and scan events.

### Edge Function inventory
- `rewardloop-api` v9: `verify_jwt=true`, configured origin allowlist, server-side bearer verification and hard-coded tenant slug `growta-rewardloop` observed in deployed source.
- Legacy functions `claim-qr`, `onboard-farmer`, `issue-qr-batch`, `revoke-qr-batch`, `redeem-reward` and `verify-partner` are active with `verify_jwt=false`; inspected claim/redeem implementations manually validate bearer tokens, but use wildcard CORS. Audit every route/caller and authorization behavior before migrating or retiring them. Do not disable them until caller analysis and replacement tests pass.
- The main API's hard-coded tenant slug means tenant self-service/multi-tenant support is not complete.
- Redis infrastructure exists on the free Upstash plan; application integration is not proven. Sentry integration is not confirmed by inspected source. Do not put authoritative balances, inventory or entitlements in Redis.

### CI / documentation consistency
- The workflow `.github/workflows/rewardloop-smoke-tests.yml` checks shell syntax, client/API contract tests and a read-only CORS/auth smoke script.
- A previous run was reported as passing the smoke/contract checks, but these checks do not prove valid-claim, concurrency, redemption or cross-tenant transaction correctness.
- The old notes below saying version 7 and workflow pending were stale when this record was refreshed. Current API version is 9. Preserve historical evidence, but use this top-level snapshot as current inventory.

## Not yet tested (required before real rewards)

These checks require isolated test records and ideally a disposable local/test database, not production business records:

1. A valid unique QR claim creates one claim and exactly one ledger credit.
2. Same idempotency key replays the same result without duplicate points.
3. Two concurrent requests for one QR produce at most one successful award.
4. A revoked, expired, wrong-role, or wrong-tenant QR cannot award points.
5. Insufficient redemption balance leaves ledger, redemption, and reward stock unchanged.
6. Duplicate redemption request key does not reserve points twice.
7. Cancellation/rejection refunds points and restores stock exactly once.
8. Fulfilment does not refund points and cannot resolve a redemption twice.
9. Demo reward redemption and demo campaign activation are rejected server-side.
10. Tenant A's administrator cannot read or mutate Tenant B records.
11. Every legacy Edge Function validates identity and permission equivalently to the canonical API.
12. Public tenant/catalogue read policies expose only intentionally public fields and tenant scope.

## Next required setup

Use a local Supabase CLI/Docker environment if available. If a disposable remote project or database branch is needed, confirm cost first; do not create it without explicit cost approval. No production balance-mutating, concurrency, payment, or cross-tenant test should be run.

## Release gate

Status remains **NO-GO for unrestricted real-value campaigns or live subscription payments** until transactional, cross-tenant, budget, fulfilment, recovery, email, monitoring and reconciliation checks have passed.

## Historical follow-up hardening — 2026-10-21

- Updated `supabase/functions/rewardloop-api/index.ts` to remove wildcard CORS.
- Default browser origin allowlist is exactly `https://bigagri.vercel.app`; additional exact origins may be configured using the Edge Function environment variable `ALLOWED_ORIGINS` as a comma-separated list.
- Requests carrying a disallowed Origin now receive HTTP 403 before authentication or business logic. Requests without an Origin header remain subject to bearer-token authentication and authorization.
- This deployment was reported as version 7 at the time. Current live inventory now reports version 9 with JWT verification enabled.
- Security Advisor findings at the latest read-only check still include leaked-password protection disabled and `rewardloop_admin_settings` RLS enabled without policies.

## Safe CORS smoke test

`supabase/tests/rewardloop_cors_smoke_test.sh` performs non-mutating checks:
1. Production-origin OPTIONS preflight returns 204 and exact allowed-origin header.
2. An unapproved origin receives 403 and no wildcard CORS header.
3. POST with no bearer token returns 401.

Run from a shell with curl:
```bash
bash supabase/tests/rewardloop_cors_smoke_test.sh
```

Optional environment variables: `API_URL`, `ALLOWED_ORIGIN`, `BLOCKED_ORIGIN`. A passing CORS/auth smoke test is not a substitute for transactional integration tests.
