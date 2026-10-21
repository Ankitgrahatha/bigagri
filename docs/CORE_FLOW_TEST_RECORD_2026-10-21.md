# RewardLoop Core Flow Test Record — 2026-10-21

## Environment

- Supabase project: `guhhuqxrobhuumwrypnc` (production project)
- Repository: `Ankitgrahatha/bigagri`, branch `main`
- Test approach: read-only metadata assertions plus RPC negative-input smoke tests. No production QR, user balance, reward stock, or campaign was mutated.

## Executed checks

| Check | Result | Evidence |
|---|---|---|
| RLS enabled on selected core tables | PASS | Catalog assertion ran without exception |
| Privileged internal RPCs denied to anon/authenticated and granted to service_role | PASS | Catalog assertion ran without exception |
| Demo-campaign activation guard present in private lifecycle function | PASS | Catalog source assertion ran without exception |
| Explicit client deny policy for QR codes | PASS | Catalog policy assertion ran without exception |
| Claim RPC rejects null actor / invalid request safely | PASS | Returned `ok=false`, `outcome=invalid_request`, `points_awarded=0` |
| Redemption RPC rejects null actor / invalid request safely | PASS | Returned `ok=false`, `error=invalid_request` |

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

Create a disposable Supabase project or isolated database branch, apply repository migrations, and run deterministic integration tests there. A live database branch may incur usage charges, so it should not be created without explicit budget approval. Do not run concurrency or balance-mutating tests against the production tenant.

## Release gate

Status remains **NO-GO for an unrestricted real-value campaign** until the remaining transactional tests, production email confirmation, budget enforcement, fulfilment reconciliation, and recovery/monitoring checks have passed.
