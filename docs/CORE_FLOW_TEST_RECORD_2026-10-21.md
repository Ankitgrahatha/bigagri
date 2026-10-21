# RewardLoop Core Flow Test Record — 2026-10-21

## Environment and safety

- Repository: `Ankitgrahatha/bigagri`, branch `main`
- Supabase project: `guhhuqxrobhuumwrypnc`
- Checks executed against production were read-only metadata queries and invalid-input RPC calls. No real QR, balance, reward stock, or campaign was mutated.

## Executed checks

| Check | Result | Evidence |
|---|---|---|
| RLS enabled on selected core tables | PASS | Catalog assertion ran without exception |
| Privileged internal RPCs denied to anon/authenticated and granted to service_role | PASS | Catalog assertion ran without exception |
| Demo-campaign activation guard present | PASS | Catalog source assertion ran without exception |
| Explicit client deny policy for QR codes | PASS | Catalog policy assertion ran without exception |
| Claim RPC rejects null actor / invalid request safely | PASS | Returned `ok=false`, `outcome=invalid_request`, `points_awarded=0` |
| Redemption RPC rejects null actor / invalid request safely | PASS | Returned `ok=false`, `error=invalid_request` |
| Accepted-claim uniqueness guard | PASS | `claims_one_accepted_per_qr_idx` exists as a partial unique index |
| Claim and ledger idempotency guards | PASS | Unique indexes exist on tenant + idempotency key |
| Redemption idempotency guard | PASS | Unique index exists on tenant + request key |
| QR token uniqueness guard | PASS | Unique index exists on tenant + token hash |

The reusable catalog assertion is committed at `supabase/tests/rewardloop_security_contract.sql`.

## Not yet tested (required before real rewards)

These checks require isolated test records and ideally a disposable Supabase project, not the production tenant:

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

## Next required setup

Create a disposable Supabase project or database branch, apply repository migrations, and run deterministic integration tests there. A database branch may incur usage charges; do not create it until the applicable cost is known and approved. No production balance-mutating or concurrency tests should be run.

## Release gate

Status remains **NO-GO for an unrestricted real-value campaign** until the remaining transactional tests, production email confirmation, budget enforcement, fulfilment reconciliation, and recovery/monitoring checks have passed.


## Follow-up hardening — 2026-10-21

- Updated `supabase/functions/rewardloop-api/index.ts` to remove wildcard CORS.
- Default browser origin allowlist is exactly `https://bigagri.vercel.app`; additional exact origins may be configured using the Edge Function environment variable `ALLOWED_ORIGINS` as a comma-separated list.
- Requests carrying a disallowed Origin now receive HTTP 403 before authentication or business logic. Requests without an Origin header remain subject to the existing bearer-token authentication and authorization checks.
- Supabase Edge Function `rewardloop-api` deployed successfully as version 7 with JWT verification enabled.
- This deployment does not prove end-to-end browser behavior; a production-origin smoke test and any custom-domain/preview-origin configuration still need verification.
- Security Advisor still reports leaked-password protection disabled and `rewardloop_admin_settings` RLS enabled without policies. These remain open review items.


## Safe CORS smoke test prepared — 2026-10-21

Added `supabase/tests/rewardloop_cors_smoke_test.sh`. It performs three non-mutating checks using curl:
1. Production-origin OPTIONS preflight returns 204 and the exact allowed-origin header.
2. An unapproved origin receives 403 and no wildcard CORS header.
3. POST with no bearer token returns 401.

Run from a shell with curl:
```bash
bash supabase/tests/rewardloop_cors_smoke_test.sh
```

Optional environment variables: `API_URL`, `ALLOWED_ORIGIN`, `BLOCKED_ORIGIN`. This script has been committed but has **not been executed from this workflow**, so the CORS behavior remains deployed but not yet runtime-smoke-tested.
