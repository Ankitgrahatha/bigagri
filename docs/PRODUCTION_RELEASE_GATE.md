# Production release gate and recovery runbook

This runbook is a mandatory gate for Growta RewardLoop production changes. It is deliberately conservative because the production Supabase database and the Vercel production alias may not be on the same revision as `main`.

## Current release posture

**Status: NOT CERTIFIED FOR GENERAL PUBLIC LAUNCH.** A successful GitHub merge, green source tests, a READY preview, or an HTTP 200 from the site is not proof that production database schema, Edge Functions, and frontend assets are mutually compatible.

Known current risks to resolve before certification:

- The latest confirmed production Vercel alias was serving an older commit than the latest merged admin search changes. Vercel's build-rate-limit check has failed; do not claim the latest main commit is deployed until deployment metadata proves it.
- The Supabase migration history contains the recorded migrations, but source-to-live schema equivalence has not yet been demonstrated. Do not run `db reset --linked`, replay baseline DDL, or apply a guessed migration to production.
- Several legacy Edge Functions have JWT verification disabled. Do not disable or delete them until invocation logs/callers are inventoried and migrated to the canonical API.
- Supabase's leaked-password protection advisor is warning that the control is disabled.
- Admin settings currently include placeholders; SMTP, Auth configuration and email-template publishing are not wired end-to-end.

## Gate A — reconcile source, migration history and live schema

1. Freeze production DDL and function deployments while investigating.
2. Record the exact `main` SHA, production Vercel deployment SHA, deployed `rewardloop-api` version, and current Supabase migration list.
3. Compare every migration file in `supabase/migrations` with the migration ledger in Supabase. Record missing, duplicate, out-of-order and renamed versions.
4. Compare live table, column, constraint, index, trigger, function and RLS-policy definitions with the expected schema from the repository using read-only introspection or a production schema dump approved by the owner.
5. Produce a reviewed reconciliation migration only for proven drift. Never edit old migration files to make history appear aligned.
6. Test the exact reconciliation against a disposable database restored from a recent schema/data-safe snapshot. Verify both forward migration and documented recovery.
7. Obtain a human review before applying production DDL. Take/verify a recoverable backup first.

**Exit evidence:** signed migration matrix, schema diff with no unexplained drift, tested migration on isolated Postgres, backup/restore evidence, and approved production change record.

## Gate B — identity, authorization and legacy API containment

- Keep `rewardloop-api` JWT verification enabled and verify the caller via Supabase Auth before any service-role operation.
- Verify every privileged action checks active tenant membership and role server-side. Never trust a client-supplied actor ID or tenant membership.
- Run negative tests for anonymous calls, expired/invalid JWTs, ordinary farmer calling each admin action, inactive membership, cross-tenant IDs, replayed requests, and concurrent claims/redemptions.
- Inventory all traffic and callers for `claim-qr`, `onboard-farmer`, `issue-qr-batch`, `revoke-qr-batch`, `redeem-reward`, and `verify-partner`. Migrate callers to the canonical API and verify telemetry before changing their JWT settings or retiring them.
- Enable Supabase leaked-password protection in Auth settings and verify the control with a safe test account.
- Configure production email/SMTP and test sign-up confirmation, password recovery, expiration, and template rendering. Do not represent admin settings placeholders as working controls.

**Exit evidence:** automated negative authorization suite, caller inventory, verified Auth controls, and successful email-flow test results.

## Gate C — reward and financial correctness

- Verify points ledger is append-only and balances reconcile to ledger entries.
- Verify claim and redemption idempotency under retries and concurrency; one request ID must not issue duplicate points or stock movements.
- Verify QR tokens are unique, non-guessable, revocable, scoped to the correct tenant/campaign/product, and cannot be reused after a successful claim.
- Verify campaign budgets have defined units and semantics; do not mix points, currency minor units, and token counts.
- Verify finite stock cannot be oversold under concurrent redemptions.
- Verify fulfilment, cancellation, rejection and refunds are atomic, audited, idempotent and do not refund twice.
- Verify demo rewards/campaigns are not redeemable or activatable as production offers.

**Exit evidence:** isolated PostgreSQL concurrency/replay tests, ledger reconciliation report, and audited state-transition tests.

## Gate D — operator console and tenant control plane

The release checklist must explicitly test each module that is advertised in the UI. Existing partner/campaign/product/QR/redemption controls do not imply that the broader SaaS control plane exists.

- Tenant directory, tenant status, membership/role management and tenant isolation.
- Partner verification, QR issuance/revocation and campaign lifecycle.
- Rewards catalogue, redemption fulfilment, refund/cancellation and ledger explorer.
- Audit/security event viewer, fraud/risk review, exports and operational reports.
- Integrations/system health, Auth/email settings, branding/content and support operations.
- Subscription plans/billing, kept separate from reward points, only if SaaS billing is enabled for customers.

For every module, test loading, empty/error states, pagination, authorization, audit trail, mobile layout, keyboard access, and CSV formula-injection handling where export is available. Hide or label unfinished capabilities rather than presenting placeholders as complete.

## Gate E — release, observability and recovery

1. Require all repository quality gates and isolated database regression jobs to pass on the exact merge SHA.
2. Verify Vercel's production deployment SHA equals the intended merge SHA and deployment target is `production`; verify aliases resolve to that deployment.
3. Verify deployed Edge Function source/version and JWT verification settings. A green frontend deployment alone is insufficient.
4. Run safe post-deploy smoke tests for landing page, auth routes, PWA manifest/service worker, authenticated API health, admin denial for non-admin users, and tenant isolation. Never run destructive smoke tests against production.
5. Check security/performance advisors and review every finding; do not drop indexes based solely on an advisor's unused-index warning.
6. Verify monitoring/alerts for function errors, auth failures, failed claims/redemptions, rate limits, database saturation and deployment failures.
7. Test restore/recovery procedures and document the operator, rollback trigger, rollback steps and customer communications.
8. Record the final go/no-go decision and known residual risks.

## Rollback principles

- Frontend: revert/roll back to a known-good production deployment only after checking its API/schema compatibility.
- Edge Functions: redeploy the last verified compatible function version; do not roll back independently if a schema change makes it incompatible.
- Database: prefer a tested forward fix for additive changes. Restoring a backup can lose writes and requires an explicit incident decision.
- Never make destructive production changes as an automated response to a failing deployment.

## Release record template

- Candidate commit SHA:
- Production deployment SHA and URL:
- Edge Function name/version/JWT setting:
- Migration reconciliation evidence:
- Backup/restore evidence:
- CI and isolated DB test runs:
- Auth and authorization negative tests:
- Ledger/claim/redemption concurrency tests:
- Security advisor findings and disposition:
- Smoke-test timestamp/results:
- Rollback owner and procedure:
- Go/no-go approver:
- Known residual risks:
