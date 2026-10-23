# RewardLoop Implementation Status

Last reviewed: 2026-10-23 (after PRs #101–#103)
Status: **MVP foundation exists; production launch is not yet approved.**

## Current deployed components

- Production PWA: https://bigagri.vercel.app/
- Admin operations console: https://bigagri.vercel.app/admin.html
- Admin settings console: https://bigagri.vercel.app/admin-settings.html
- GitHub source: https://github.com/Ankitgrahatha/bigagri
- Supabase project ref: `guhhuqxrobhuumwrypnc`

## Verified engineering progress since the prior review

The following changes are merged in Git and covered by successful GitHub Actions runs on `main`. They are **not all deployed to the connected production Supabase project**.

- Claim idempotency and actor+QR-scoped replay tests, including conflict responses that do not reveal another claim.
- Claim and redemption request keys are now explicitly bound to the owning actor; redemption replay also checks the requested reward, and conflicting key reuse returns a generic error without a second debit or stock decrement.
- Parallel PostgreSQL claim and redemption contention tests, including one-credit, one-reservation, balance serialization, and stock/accounting assertions.
- Points ledger immutability: update, delete and truncate are rejected in the disposable database.
- Least-privilege grants on reward-bearing tables and internal RPC execution.
- Public catalog opt-in by tenant, with private tenant records hidden from both `anon` and `authenticated` roles in isolated tests.
- Default privileges tightened for future objects and tested by creating new tables, sequences, and functions.
- Schema-only local baseline, timestamp markers, safe local seed, and clean PostgreSQL rebuild workflow.
- Redemption refund enum fix: cancellation/rejection compensation uses the existing `redeem_release` enum value; the isolated behavior test proves refund/stock restoration occurs once and fulfillment does not refund.
- Redemption resolution explicitly rejects a NULL status at the database boundary; isolated SQL regression test passes.
- Invalid QR token guesses are now rate-limited to 10 attempts per actor in a rolling 15-minute window. The private attempt table stores actor/request/time metadata only, never the submitted token. The migration is based on the latest budget-aware claim function so it preserves campaign liability enforcement.
- Frontend release checks validate JavaScript entry points, service-worker syntax, HTML-referenced local assets, PWA manifest JSON, and icon existence.
- Admin email settings now clearly state that they save preferences only; SMTP passwords are cleared after submission and are not persisted to the application settings table.
- The deployed admin settings function is now tracked in Git with tests for caller authentication, tenant admin authorization, field allowlisting and SMTP password non-persistence.
- Six legacy Edge Function sources are archived outside the canonical deployment folder; none has been disabled.

Current CI evidence on main:
- Latest verified transaction/security suite before the newest actor-replay merge passed on commit `948e6f5bf541e77a70ea92ce5319d14f46055a51`; the full clean PostgreSQL migration chain and behavioral tests passed.
- The actor-replay merge (PR #51) adds owner-bound claim and redemption replay migrations and tests. Its quality gate, smoke tests, legacy-route guard, and isolated PostgreSQL suite passed on the pre-merge head `7c5e0abd29c4f0bea03ab8d5076ed5e9111efbc0`.
- The frontend/PWA asset suite passed in PR #44 and the admin email-settings honesty/security suite passed in PR #48 before merge.
- The latest inspected Vercel production deployment is READY at commit `948e6f5bf541e77a70ea92ce5319d14f46055a51` (deployment `dpl_2y3bVsTvGKXd8uB1sojgSPbeLgeT`); it predates the newly merged rate-limit feedback UI.
- The enhanced production smoke workflow on commit `cce4d02268a0e558688240bd493b47d2052d2295` verified all three public routes and security headers, but failed the new frontend marker check because the live alias does not yet serve the expected rate-limit UX and truthful email-settings copy. This is deployment drift, not a database test failure.
- Do not force a production deployment just to clear the smoke check: production Supabase migration history still needs schema comparison and reviewed history-only reconciliation. Keep the final production deployment pending until that release gate is ready.
- These results prove the tested repository/CI path only, not that pending SQL has been applied to production.

## Current production state after the 2026-10-23 release-hardening updates

- **Latest canonical Git main at this review:** `6dab7fa066e24f7c8903b47e1cdc2b741fdd05aa`, including PR #101 (billing release boundary/runbook), PR #102 (scheduler safety contract), and PR #103 (disabled unavailable test-email action and refreshed traceability), on top of PRs #93–#100.
- **Local verification on this exact main:** 155 Node.js contract tests passed, 0 failed; browser JavaScript syntax checks and `git diff --check` passed. This local run does not imply every GitHub-hosted CI job or production deployment succeeded. The constituent PRs also passed quality gate, safe smoke, legacy-route guard, and isolated PostgreSQL regression CI.
- **Vercel production alias:** the latest deployment returned by the Vercel API still targets commit `263d5982736101c1c5bf4baf943d0a228f05234f`, not the current main merge. A new production deployment attempt for the current main was rejected with HTTP 402 `api-deployments-free-per-day` (more than 100 deployments per 24 hours). Do not retry until the quota resets or the account owner resolves the plan limit.
- **Live Supabase migration history:** read-only API reports exactly the original 13 historical versions. The repository now has 41 migration files, including the SaaS billing tables/RPCs and webhook-health migration; these later migrations have not been applied to production.
- **Live Supabase Edge Functions:** the project currently lists six legacy functions (`claim-qr`, `onboard-farmer`, `issue-qr-batch`, `revoke-qr-batch`, `redeem-reward`, `verify-partner`) plus `rewardloop-api` v10 and `rewardloop-admin-settings` v2. The new Razorpay/SaaS billing functions are not deployed.
- **Live Auth security:** Supabase's security advisor still reports leaked-password protection disabled. Enable and verify it in the Supabase Auth settings before production launch.
- The billing scheduler is committed in Git but intentionally disabled until repository variable `REWARDLOOP_BILLING_MONITOR_ENABLED=true` is set after the processor secret and deployed backend are verified.
- No production migration, migration-history repair, Edge Function deployment, provider secret change, or real payment was performed during this hardening work.

**Release boundary:** a fresh read-only production catalog comparison on 2026-10-23 matched the checked-in baseline fingerprints for columns, constraints, enums, indexes, policies, RLS flags, and triggers; all 16 captured function body/security hashes and all 15 per-table ACL fingerprints also matched. This materially strengthens the parity evidence but is not a backup, does not reconcile migration history, and does not apply any DDL. The production migration-history repair remains unperformed pending backup/recovery confirmation and explicit operator approval. Auth security configuration, server-side test credentials, reviewed migration dry-run, and test-mode end-to-end evidence remain outstanding.

## Latest repository changes after PRs #101–#103

- PR #101 clarifies the production runbook: eight billing/RewardLoop Edge Functions are expected in the controlled release; read-only smoke checks do not prove the billing lifecycle; Vercel frontend deployment must be verified independently.
- PR #102 adds contract assertions for the opt-in billing scheduler, five-minute cadence, bounded batch/runtime, required aggregate health fields, alert thresholds, and secret/payload non-disclosure.
- PR #103 disables the admin test-email action until a real privileged email integration exists, removes the placeholder click handler, adds a regression test, and updates the PRD traceability matrix.
- The full local Node contract suite on latest main passed **155/155**. JavaScript syntax checks and `git diff --check` passed.
- The Vercel status check on PR #103 still failed with the account's daily deployment quota (HTTP 402, `api-deployments-free-per-day`). The frontend has not been proven deployed from latest main.

## Latest release-gate evidence

- The baseline-parity test and isolated PostgreSQL workflow validate the schema-only baseline, the 13 historical no-op markers, catalog fingerprints, function bodies/security configuration, per-table grants, default privileges, transactional behavior, tenant isolation, and concurrency in disposable CI.
- The live Supabase project still reports exactly those 13 historical migration versions. CI parity is not proof that pending migrations were applied to production.
- Latest main contract suite on `6dab7fa066e24f7c8903b47e1cdc2b741fdd05aa`: 155 passed, 0 failed; browser JavaScript syntax and diff checks passed. Merged PR CI also passed quality gate, safe smoke, legacy-route guard and isolated PostgreSQL regression.
- The live Supabase advisor reports leaked-password protection disabled and one informational RLS-without-policy finding for `public.rewardloop_admin_settings`. The latter is safe only while direct client grants remain revoked and access stays behind the authenticated, tenant-authorized Edge Function. It is not a reason to create permissive client policies.
- The performance advisor reports 25 unused indexes. Do not drop them based solely on this signal; reassess after representative traffic and load testing.
- The production Vercel alias is not verified against the latest main commit. The latest deployment attempt for current main returned HTTP 402 due the account's 100-deployments-per-24-hours limit. No workaround or plan change was made.

**Release boundary:** never run the schema baseline against the live database. History-only repair is allowed only after a fresh, full schema comparison proves equivalence, backup/recovery readiness is recorded, and an approved operator reviews the exact linked dry-run. See [Supabase migration reconciliation](./SUPABASE_MIGRATION_RECONCILIATION.md) and [production release runbook](./PRODUCTION_RELEASE_RUNBOOK.md).

## Production blockers still open

1. **Production migration history is unreconciled.** Live reports 13 historical versions while repository main contains 41 migration files. A fresh read-only fingerprint comparison now matches the checked-in baseline for the captured catalog categories, 16 function bodies/security settings, and 15 table ACLs. Do not run baseline DDL or repair history until backup/recovery readiness, migration-list review, explicit operator approval and the exact linked dry-run are recorded.
2. **SaaS billing schema and functions are not deployed.** Billing is implemented and CI-tested in source, but the production project has no billing migrations/functions yet. Required server-side test credentials, provider plan IDs and test-mode checkout/webhook/reconciliation evidence remain outstanding.
3. **Auth leaked-password protection is disabled.** Enable it in Supabase Auth security settings and verify it with a controlled test before launch. Production email confirmation, SMTP delivery and privileged MFA policy are also not fully verified.
4. **Six legacy Edge Functions remain active** with `verify_jwt=false` and manual authentication/CORS handling. Do not retire or replace them until source/client references and a longer privacy-safe traffic window have been reviewed and parity/rollback are documented.
5. **Vercel production is behind current main.** The production deployment API reports the old `263d598` main commit; a new deployment of current main was rejected by the account's daily deployment limit (HTTP 402). Wait for quota reset or resolve the plan limit through the account owner; do not bypass project billing/security controls.
6. **No production browser-level end-to-end acceptance run** has proved signup → confirmation → profile → claim → balance → redemption → cancellation/fulfillment against the current deployed stack.
7. **Tenant self-service provisioning and several admin control-plane workflows remain incomplete.** The app still defaults to `growta-rewardloop`; multi-tenant source safeguards do not equal a complete onboarding/invitation/custom-domain/lifecycle product.
8. **Additional product work remains:** live SMTP/Auth configuration, test-email delivery, full fraud-case workflow, external reward fulfilment and settlement, backup/restore drill, operational alert delivery, usage metering and billing tax/invoice policies.

## Implemented in repository / database

- Hindi-first/English-switchable responsive PWA shell.
- Supabase email/password auth and profile onboarding.
- Partner verification admin flow.
- Product and campaign management with explicit campaign lifecycle controls. Product creation, metadata editing (SKU remains immutable), and deactivate/reactivate controls are implemented with tenant-scoped, audited RPCs and passing isolated PostgreSQL tests (PRs #62, #63 and #65). A new isolated-tested migration adds explicit point valuation, an append-only campaign award-liability ledger, serialized budget checks and fail-closed activation rules; it remains pending production deployment until reviewed.
- Unique QR batch issuance, one-time token download and batch revocation.
- Server-side QR claim and redemption endpoints using database RPCs.
- Points ledger, scan events, claim records, redemption history and audit tables.
- Admin CSV exports and redemption resolution operations.
- Protected admin settings preference store and settings UI.

## SaaS plans, payments and billing — source implemented, production unverified

PRs #91–#95 added the Razorpay SaaS billing foundation in source: versioned plans/pricing, tenant subscriptions and payment-attempt records, fail-closed entitlements, idempotent subscription checkout, a read-only checkout-reconciliation queue, provider-verified checkout recovery, a signed webhook receiver with durable deduplication, a bounded processing worker, aggregate health metrics, and an operations/runbook workflow. PRs #101–#103 subsequently tightened release-boundary documentation, scheduler regression coverage, and admin settings honesty.

**Important:** this is not proof of a working live billing service. The production project still has only 13 historical migrations and does not list the billing Edge Functions. The billing migrations/functions must pass the controlled release workflow and test-mode acceptance before billing is enabled.

### Implemented and CI-tested in the repository
- Immutable/versioned plan and entitlement schema with service-role-only operations.
- Authenticated tenant-scoped checkout reservation and idempotency.
- Provider-identity/plan/notes/status checks for explicit checkout recovery; ambiguous outcomes fail closed.
- Raw-body webhook signature verification, durable inbox deduplication, bounded retries, out-of-order protection, and transactional subscription/payment state updates.
- Read-only operator reconciliation queue and aggregate webhook health metrics.
- Five-minute GitHub Actions scheduler, disabled by default until `REWARDLOOP_BILLING_MONITOR_ENABLED=true`; activation also requires the matching processor secret, deployed migration/functions, and a successful test-mode run.
- Incident runbook covering payment failure, exhausted events, monitoring thresholds and release evidence.

### Still missing or not production-verified
- Apply reviewed billing migrations after production schema-parity/history reconciliation and backup/recovery review.
- Deploy the matching billing Edge Functions through the protected workflow after required secrets are verified.
- Configure test-mode Razorpay plan IDs and run checkout, duplicate webhook, invalid signature, amount/currency mismatch, failed payment, cancellation, out-of-order delivery, checkout recovery and entitlement tests against the actual test account.
- Verify the scheduled processor and alert route in operation; a workflow file alone is not operational monitoring.
- Invoice/GST/credit-note legal formatting, refunds, proration, discounts/coupons, dunning/grace policy, customer self-serve payment retries, plan changes/cancellation controls, usage metering and settlement exports remain unimplemented or require separate policy review.
- Live payments are not approved. Do not use a browser redirect or client flag as proof of payment, and do not enable live credentials until test-mode evidence, reconciliation and rollback are reviewed.

### Required financial invariants
- Only a verified provider event/API response may confirm payment or activate entitlements.
- Webhook processing must be idempotent, authenticated, durable and safe under retries/out-of-order delivery.
- Every payment must match one tenant, provider subscription/plan, amount, currency and billing period; mismatches must remain fail-closed and be reconciled.
- Subscription state and entitlements must change transactionally and be audited.
- Loyalty points, redemption stock and campaign liability remain separate from SaaS subscription revenue and must continue to use authoritative database transactions.

## Other blockers and unverified areas

- Production Auth email delivery and account confirmation are not verified; leaked-password protection remains disabled.
- The settings console saves preferences only; it does not apply SMTP, Auth URL, signup policy or email templates to live Supabase Auth. The test-email control is now visibly disabled and states that test delivery is unavailable; no test message is sent.
- Current client/server configuration defaults to the `growta-rewardloop` tenant slug; customer self-service multi-tenant onboarding is not implemented.
- Reward provider integration, formal fraud case handling, backup/restore drill and live alert delivery remain unverified or incomplete.
- Sentry is not confirmed integrated in the inspected source. Redis infrastructure exists, but application integration and safe usage are not fully confirmed. A tenant-aware CMS/control plane is not complete.
- An account's super_admin membership does not prove that successful admin login and every end-to-end privileged operation have been tested.

## Release decision

**Do not run an unrestricted public rewards campaign or accept live SaaS subscription payments yet.** Before a controlled pilot, configure and test production email, verify admin login, apply and verify the reviewed pending production migrations, configure an approved point valuation for every budgeted campaign, and conduct a production go/no-go review. Isolated CI now exercises one-time claims, budget caps, redemption accounting, grants/RLS and concurrent requests, but it does not substitute for deployment verification. For monetization, also require test-mode checkout/webhook/reconciliation coverage and reviewed tax/invoice rules before live activation.

See [PRD traceability matrix](./REWARDLOOP_PRD_TRACEABILITY.md) for requirements, evidence and the ordered implementation backlog.
