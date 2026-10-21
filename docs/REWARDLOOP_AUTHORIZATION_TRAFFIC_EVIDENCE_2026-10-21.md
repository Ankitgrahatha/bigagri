# RewardLoop Authorization and Traffic Evidence Baseline

**Captured:** 2026-10-21  
**Environment:** production observability metadata only; no business data was changed.  
**Status:** partial evidence; privileged database authorization and transaction correctness remain unproven.

## Safety statement

This review used read-only repository inspection, Supabase security-advisor output, and aggregated Edge Function request logs. It did not disable functions, change configuration, create claims, redeem rewards, or modify balances/stock.

## Current API-path evidence

A read-only aggregation of `function_edge_logs` for the preceding 24 hours returned:

| Request path | Requests | First observed (UTC) | Last observed (UTC) | Observed status codes |
|---|---:|---|---|---|
| `/functions/v1/rewardloop-api` | 43 | 2026-10-21 12:47:16 | 2026-10-21 16:47:14 | 200, 401, 403, 204 |

The same query returned **no rows for the six legacy function paths** (`claim-qr`, `onboard-farmer`, `issue-qr-batch`, `revoke-qr-batch`, `redeem-reward`, `verify-partner`) during this 24-hour window.

### Interpretation limits

- This is evidence only for the queried log source and 24-hour window. It is **not proof that legacy endpoints have no callers**.
- Existing mobile/PWA caches, direct URL callers, external integrations, other time windows, and incomplete log retention can all hide traffic.
- Keep legacy functions enabled until callers are inventoried and observed over an agreed deprecation window, with access logs and a rollback plan.
- Do not infer business-action counts from aggregate function request counts; the API endpoint serves multiple actions and OPTIONS/auth failures.

## Repository-level authorization observations

The current `rewardloop-api` verifies the bearer token with Supabase Auth and passes `user.id` as the actor to internal RPCs. Admin actions also check an active `tenant_memberships` row for `brand_admin` or `super_admin` before dispatching the action. The tenant slug is currently hardcoded to `growta-rewardloop`.

These are useful application-layer guards, but **they do not prove that privileged database operations independently enforce authorization**. The service-role database client bypasses RLS, so every internal RPC that accepts actor, tenant, campaign, batch, partner, reward, or redemption identifiers must validate the actor's active membership/role and the resource's tenant ownership inside the transaction. In particular, client-supplied tenant/resource IDs must not be trusted without an ownership check.

Required proof for each privileged RPC:
1. Authenticated actor is present and cannot be substituted with another user ID.
2. Actor has an active membership in the resource tenant and the required role for the operation.
3. Target resource belongs to that same tenant.
4. Unauthorized attempts return a controlled denial and produce no mutation.
5. Direct EXECUTE is denied to `anon` and `authenticated`; service-role execution is limited to server-side callers.
6. A two-tenant negative test proves Tenant A cannot read or mutate Tenant B's resources.

## Current security-advisor findings

Read-only Supabase Security Advisor returned two findings:

1. **Leaked-password protection disabled** — enable the Auth setting for compromised-password checks and verify it is active.
2. **RLS enabled without policies on `public.rewardloop_admin_settings`** — determine the intended access model. If the table is server-only, verify client grants are revoked and access is limited to trusted server roles; do not add a broad allow policy just to silence the advisor.

The first finding is an Auth configuration task; the second needs a grants/access review before any policy change.

## Next evidence-producing steps

1. Inspect the SQL definitions of all privileged `rewardloop_*_internal` RPCs in a controlled read-only manner, mapping each actor/role/membership/tenant/resource check.
2. Add pgTAP tests to a disposable local Supabase database for each allowed and denied role/tenant/resource combination. Run `supabase test db` only after rebuilding from repository migrations.
3. Run replay, concurrent-claim, concurrent-last-stock redemption, duplicate-refund, and rollback tests using synthetic fixtures in the isolated environment. Capture before/after claim counts, ledger sums, redemption counts, and stock.
4. Establish legacy caller evidence from repository references, deployed clients/integrations, and a sufficiently long production log window. Do not disable endpoints based on a single quiet day.
5. Resolve both advisor findings and re-run the advisor; attach test outputs and commit SHA to the release evidence.
6. Keep unrestricted real-value rewards **NO-GO** until authorization, transaction, replay/concurrency, and operational recovery evidence all pass.

## Test evidence distinction

The repository's static contract tests verify expected code patterns and metadata. They do not by themselves prove transaction atomicity, database authorization behavior, or concurrency safety. Production success responses are not substitutes for isolated database-state assertions.

Supabase recommends testing database functions, RLS, and data integrity with pgTAP and running database tests in CI:
- https://supabase.com/docs/guides/local-development/testing/overview
- https://supabase.com/docs/guides/database/postgres/row-level-security
