# RewardLoop Transaction-Safety Test Matrix

Status: **specification only — not evidence that the cases have passed**.

## Safety boundary

Run these cases only against a disposable local Supabase stack or a dedicated non-production project with synthetic users, tenants, QR tokens, rewards, and balances. Do not execute successful-claim, redemption, refund, stock, or fulfilment cases against production. Do not use real customer identifiers or real QR secrets in test fixtures.

The preferred database-level harness is Supabase CLI + pgTAP, with each SQL test wrapped in a transaction and rolled back. Supabase documents this approach for testing constraints, functions, and RLS policies: https://supabase.com/docs/guides/local-development/testing/overview. Application-level concurrency tests must use unique fixture IDs and clean up only their own test records.

## Preconditions

- A local/dedicated database has been rebuilt from repository migrations.
- Test tenant A and tenant B are distinct and synthetic.
- Synthetic farmer/user A, farmer/user B, admin A, and admin B exist.
- Test QR fixtures include valid, revoked, expired, wrong-tenant, and already-claimed variants.
- Reward fixtures include active/inactive and sufficient/insufficient-stock variants.
- Each test uses a fresh idempotency key unless the test explicitly replays one.
- Capture before/after counts and sums for claims, points ledger, redemptions, and reward stock.
- Do not weaken production RLS, grants, or JWT checks to make a test pass.

## Required cases and acceptance criteria

| ID | Scenario | Expected invariant | Evidence to capture |
|---|---|---|---|
| TX-01 | Valid QR claim, first request | Exactly one accepted claim and exactly one positive ledger credit; response points match ledger | Response + before/after rows |
| TX-02 | Retry same claim with same idempotency key | Stable replay result; no second claim or credit | Two responses + unique-key row counts |
| TX-03 | Concurrent claim requests for one QR | At most one accepted claim and one credit, regardless of response order | Parallel request log + ledger aggregate |
| TX-04 | Claim revoked/expired/wrong-tenant QR | No accepted claim and no points credit | Error/outcome + unchanged ledger |
| TX-05 | Claim request attempts to spoof actor or tenant | Authenticated identity and server-derived tenant scope win; spoofed body fields cannot grant access | Request body + authorization result |
| TX-06 | Redemption with sufficient balance and stock | One redemption and one corresponding points debit; stock reserved once | Response + ledger + stock delta |
| TX-07 | Redemption with insufficient balance | Rejected atomically; no redemption, debit, or stock change | Response + unchanged aggregates |
| TX-08 | Redemption with insufficient stock or inactive reward | Rejected atomically; no debit or stock change | Response + unchanged aggregates |
| TX-09 | Retry redemption with same request key | Same logical redemption; no second debit or stock reservation | Responses + request-key count |
| TX-10 | Two concurrent redemptions competing for last unit | No oversell; stock never negative; accepted reservations do not exceed initial stock | Parallel log + final stock |
| TX-11 | Cancel/reject redemption once | Exactly one refund and one stock restoration, if business rules specify both | Status transitions + ledger + stock |
| TX-12 | Repeat cancellation/refund | No duplicate refund or stock restoration | Repeated responses + ledger delta |
| TX-13 | Fulfil redemption twice | Fulfilment transition occurs once; no refund is introduced by fulfilment | Transition audit + ledger delta |
| TX-14 | Demo campaign/reward redemption | Server rejects prohibited real-value operation, independent of UI | API/RPC result + unchanged ledger |
| TX-15 | Tenant A admin accesses Tenant B data/action | Denied; no cross-tenant rows disclosed or mutated | Caller/tenant IDs + result |
| TX-16 | Non-admin member invokes admin operation | Denied before privileged mutation | Role fixture + result |
| TX-17 | Invalid/null actor, malformed key, or malformed payload | Controlled rejection; no mutation and no internal exception/secret leakage | Response + unchanged aggregates |
| TX-18 | Unexpected exception after a tentative write | Entire operation rolls back; no partial ledger, stock, claim, or redemption state | Injected test-only fault + before/after aggregates |

## Execution sequence

1. **Schema and policy layer:** run `supabase test db` against the local stack. Verify table constraints, partial unique indexes, RLS, and internal RPC execute grants.
2. **Single-operation semantics:** execute TX-01, TX-02, TX-04, TX-06–TX-09, TX-11–TX-17 using synthetic fixtures.
3. **Concurrency:** use a separate integration harness to send genuinely parallel requests for TX-03 and TX-10. A sequential test is not acceptable evidence of concurrency safety.
4. **Atomic rollback:** use a test-only fault injection point or transaction-level harness for TX-18. Never add a production endpoint that lets callers force failures.
5. **Evidence:** store test command, commit SHA, environment label (local or dedicated non-production), pass/fail, fixture IDs, and aggregate deltas. Redact access tokens and QR token values.
6. **Release gate:** any failed case, skipped concurrency test, missing evidence, or run against production means the real-value launch gate remains **NO-GO**.

## Important distinction

Static source-contract tests prove that expected guards and call patterns exist; they do not prove database transaction behavior. A successful API response alone does not prove exactly-once accounting. Acceptance requires correlated claim/redemption state, ledger entries, stock deltas, and replay/concurrency evidence from the isolated environment.
