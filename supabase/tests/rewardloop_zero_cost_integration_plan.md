# RewardLoop Zero-Cost Integration Test Plan

Date: 2026-10-21
Repository: `Ankitgrahatha/bigagri`
Production project is explicitly out of scope for mutating tests.

## Run strategy (no paid Supabase branch)

1. Use local Supabase CLI + Docker if already installed, or a free local PostgreSQL/Supabase-compatible environment. Local setup must apply the repository migrations in order.
2. If local Supabase CLI/Docker is unavailable, run only the read-only contract checks against production and keep transactional tests marked BLOCKED. Do not send claim, redeem, cancel, fulfil, campaign mutation, or QR issuance requests to production for testing.
3. Never use a real user, real reward, or real points balance in the test fixture. Use synthetic users and tenant data in the local database.
4. Do not copy production service-role keys into local files or commit secrets.

## Current source audit findings

- Edge Function verifies the bearer token through `auth.getUser()`; it does not trust a caller-supplied user ID for claim/redeem.
- Claim action validates token length and UUID request ID before invoking the internal RPC.
- Redemption action validates reward UUID and request-key length before invoking the internal RPC.
- Admin actions require an active tenant membership with role `brand_admin` or `super_admin`.
- The Edge Function currently pins `TENANT_SLUG = "growta-rewardloop"`; it is a single-tenant pilot implementation, not yet a general multi-tenant router.
- CORS currently allows `*`. Because requests are bearer-token authenticated this is not equivalent to unauthenticated access, but production should use an explicit origin allowlist.
- The repository contains schema/security contract SQL, but no executable valid-claim/concurrency integration suite has yet been demonstrated.
- Browser publishable key is expected to be public; service-role key must remain exclusively in server-side Edge Function secrets.

## Local test fixture

Create a disposable tenant, two users (one verified farmer and one unverified farmer), one admin, one active campaign, one inactive campaign, one product, two QR codes (different tokens), and one active non-demo reward. Record initial points-ledger totals, reward stock, QR statuses, and redemption count.

Do not seed this fixture in production.

## Test cases

| ID | Scenario | Expected assertion |
|---|---|---|
| AUTH-01 | Missing bearer token | API returns 401; no writes |
| AUTH-02 | Invalid/expired bearer token | API returns 401; no writes |
| AUTH-03 | Ordinary farmer calls admin action | 403; no admin mutation |
| PROF-01 | Same user onboards twice | One partner profile only; no duplicate |
| QR-01 | Claim valid QR once | Exactly one accepted claim and one positive ledger entry |
| QR-02 | Repeat same request ID | Stable/idempotent result; no second credit |
| QR-03 | Repeat same QR with a different request ID | Second award denied; balance unchanged |
| QR-04 | Two concurrent claims of one QR | At most one award and one accepted claim |
| QR-05 | Revoked/expired QR | Rejected; no ledger change |
| QR-06 | QR campaign inactive or outside validity window | Rejected; no ledger change |
| QR-07 | Unverified or wrong-role partner | Rejected per entitlement policy; no ledger change |
| TEN-01 | User from Tenant A submits Tenant B QR | Rejected; no cross-tenant writes |
| RED-01 | Redeem with sufficient balance and stock | One redemption and one reservation/debit |
| RED-02 | Insufficient points | Rejected; no debit and no stock change |
| RED-03 | Zero/out-of-stock/inactive/demo reward | Rejected; no debit |
| RED-04 | Retry same request key | Same logical redemption; no second debit |
| RED-05 | Two concurrent redemptions near balance limit | Balance never goes negative; stock never oversold |
| RED-06 | Cancel/reject twice | Refund and stock restoration happen at most once |
| RED-07 | Fulfil redemption | Status changes once; points are not refunded |
| ADMIN-01 | Non-admin tries campaign/QR mutation | 403; no writes |
| DEMO-01 | Activate demo campaign | Rejected server-side |
| DEMO-02 | Redeem demo reward | Rejected server-side |
| AUD-01 | Every privileged transition | Actor, tenant, outcome and reason are auditable |

## Execution notes

- For concurrency cases, use separate database connections/processes and assert final persisted state, not just HTTP responses.
- For each rejected case, compare before/after snapshots of claims, ledger, QR status, reward stock and redemptions.
- Inject failures between reservation and provider fulfilment. A timeout must enter a reconciliation state; it must not blindly reissue or refund.
- Ensure test fixtures are recreated or rolled back between scenarios.
- Run the read-only SQL contract in `supabase/tests/rewardloop_security_contract.sql` after migrations.

## Current status

**Prepared, not executed.** No valid QR claims, real redemption, or concurrency tests have been run because there is no isolated database available in this workflow. A zero-cost local environment is the next execution target.
