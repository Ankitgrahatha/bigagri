# RewardLoop Implementation Status

Last reviewed: 2026-10-23
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

## Current production state after the 2026-10-23 SaaS billing hardening merge

- **Latest canonical Git main:** `a4b4f82ac0d707cc95c1ce918f22f4c29382736d`, containing merged PRs #93 (webhook health/operations), #94 (bounded API request bodies), and #95 (controlled billing release workflow).
- **Local verification on this exact main:** 149 Node.js contract tests passed; browser JavaScript syntax checks and `git diff --check` passed. The constituent PRs also passed quality gate, safe smoke, legacy-route guard, and isolated PostgreSQL regression CI.
- **Vercel production alias:** the latest deployment returned by the Vercel API still targets commit `263d5982736101c1c5bf4baf943d0a228f05234f`, not the current main merge. A new production deployment attempt for the current main was rejected with HTTP 402 `api-deployments-free-per-day` (more than 100 deployments per 24 hours). Do not retry until the quota resets or the account owner resolves the plan limit.
- **Live Supabase migration history:** read-only API reports exactly the original 13 historical versions. The repository now has 41 migration files, including the SaaS billing tables/RPCs and webhook-health migration; these later migrations have not been applied to production.
- **Live Supabase Edge Functions:** the project currently lists six legacy functions (`claim-qr`, `onboard-farmer`, `issue-qr-batch`, `revoke-qr-batch`, `redeem-reward`, `verify-partner`) plus `rewardloop-api` v10 and `rewardloop-admin-settings` v2. The new Razorpay/SaaS billing functions are not deployed.
- **Live Auth security:** Supabase's security advisor still reports leaked-password protection disabled. Enable and verify it in the Supabase Auth settings before production launch.
- The billing scheduler is committed in Git but intentionally disabled until repository variable `REWARDLOOP_BILLING_MONITOR_ENABLED=true` is set after the processor secret and deployed backend are verified.
- No production migration, migration-history repair, Edge Function deployment, provider secret change, or real payment was performed during this hardening work.

**Release boundary:** source and isolated CI are substantially more complete, but production is not current and is not approved for live SaaS billing. Do not run baseline DDL or bypass the protected release workflow. The remaining live steps require a schema-parity review, backup/recovery confirmation, Auth security configuration, server-side test credentials, a successful reviewed migration dry-run, and test-mode end-to-end evidence.

## Latest release-gate evidence (2026-10-23)

- The full baseline-parity gate was added in PR #68 and merged as commit `a3f70d1bbb16685c4828385a5f8b474b1f1cf547`. The isolated PostgreSQL job passed after applying the schema-only baseline and all 13 historical no-op markers, then comparing catalog fingerprints, function body/security hashes, per-table effective grants, and default-ACL behavior before applying newer migrations.
- The same main commit passed all four CI workflows: isolated PostgreSQL regression, quality gate, safe API smoke tests, and legacy-route guard.
- A fresh read-only query of the connected Supabase project still shows exactly the original 13 historical migration versions. It also confirms the baseline function hashes for `private.claim_qr`, `private.resolve_redemption`, and the eight original internal wrappers. The live `tenants` table does **not** yet have `public_catalog_enabled`, confirming that post-baseline migrations are still pending in production.
- Vercel reports the production alias READY at commit `f246e08891e1e13f36f9e9abea2b2803b74dfae9` (deployment `dpl_7pt54LRi6Gn7PWihqa8mT6suALrB`). Git `main` has since advanced to `a3f70d1bbb16685c4828385a5f8b474b1f1cf547`; this is deployment drift. The Vercel deployment API still showed the recent production build-rate limit, so do not repeatedly trigger builds.
- Vercel's grouped runtime-error query returned no errors in its selected window. This is only a limited observability signal, not proof of end-to-end correctness.

**Release boundary:** the passing parity test proves the checked-in baseline matches the captured schema snapshot in the isolated test environment; it does not apply pending migrations or perform the Supabase CLI history-only repair. Do not change production migration history or push SQL until the authenticated CLI workflow confirms the full linked schema diff, current migration list, backup/restore readiness, and exact pending migration plan.

## Latest live Supabase advisor snapshot (2026-10-22)

- **Warning:** leaked-password protection remains disabled in Supabase Auth. Enable it in Auth security settings and verify it with a controlled signup/password test before production launch.
- **Informational:** `public.rewardloop_admin_settings` has RLS enabled with no table policies. This is intentional only if direct client access remains revoked and all reads/writes stay behind the authenticated, tenant-authorized `rewardloop-admin-settings` Edge Function. Recheck table grants and the function boundary if this changes.
- **Performance info:** 25 indexes are currently reported unused. Do not drop them solely on this advisory; traffic is limited and these indexes support expected QR, claim, ledger, redemption and audit queries. Reassess after representative load tests.

These findings were read from the connected project advisor. They are not fixed by CI and are separate from the migrations still pending production deployment.

## Production blockers still open

1. **Production migration history is not yet reconciled.** Do not run the schema baseline against the live database. Compare live schema to the baseline, confirm the remote migration versions, then perform the documented history-only repair and review a linked dry-run before any production push.
2. **Refund, claim/rate-limit, product creation, product lifecycle, product editing and other subsequent security migrations are pending deployment.** They are in Git and passed isolated tests; the live function/database still needs controlled release verification.
3. **Auth email delivery and leaked-password protection** remain unverified/disabled as noted below.
4. **Legacy Edge Functions remain active.** The latest 24-hour function-log query showed traffic to `rewardloop-api` but no logged requests to the six legacy routes. That is only a 24-hour observation window—not sufficient evidence to retire routes. Keep them active until client references and a longer observation window are checked.
5. **No browser-level end-to-end run** has yet proved signup → confirmation → profile → claim → balance → redemption → cancellation/fulfillment on the deployed production stack.
6. **Production deployment is behind Git main.** Vercel reports the latest production target at commit `948e6f5bf541e77a70ea92ce5319d14f46055a51`. The latest marker-enhanced smoke check failed because the production alias does not yet serve the newest rate-limit UI and admin email-settings copy. Do not claim current main UI is live; deploy only after the database release gate is resolved.

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

PRs #91–#93 and #95 have added a meaningful Razorpay SaaS billing foundation in source: versioned plans/pricing, tenant subscriptions and payment-attempt records, fail-closed entitlements, idempotent subscription checkout, a read-only checkout-reconciliation queue, provider-verified checkout recovery, a signed webhook receiver with durable deduplication, a bounded processing worker, aggregate health metrics, and an operations/runbook workflow.

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

- Production Auth email delivery and account confirmation are not verified; current account's email confirmation was previously observed as pending.
- The settings console does not yet apply SMTP, Auth URL, signup policy or email templates to live Supabase Auth. Its test-email action is a placeholder.
- The repository now has isolated PostgreSQL regression coverage for tenant catalog isolation, exact dashboard metrics, claim/redeem idempotency, concurrent requests, campaign budgets, refund/stock restoration, client grants, future-object default privileges and ledger immutability. These tests do not prove the connected production database has received the latest migrations or that full Supabase Auth email delivery works.
- Current client/server configuration is bound to the `growta-rewardloop` tenant slug; customer self-service multi-tenant onboarding is not implemented.
- Reward provider integration, formal fraud case handling, backup/restore drill and production alerting remain unverified or incomplete.
- Sentry is not confirmed integrated in the inspected source. Redis infrastructure exists but application integration and safe usage are not confirmed. A tenant-aware CMS/control plane is not complete.
- The account membership was previously added as super_admin, but membership does not prove that a successful admin login or end-to-end operation has been tested.

## Release decision

**Do not run an unrestricted public rewards campaign or accept live SaaS subscription payments yet.** Before a controlled pilot, configure and test production email, verify admin login, apply and verify the reviewed pending production migrations, configure an approved point valuation for every budgeted campaign, and conduct a production go/no-go review. Isolated CI now exercises one-time claims, budget caps, redemption accounting, grants/RLS and concurrent requests, but it does not substitute for deployment verification. For monetization, also require test-mode checkout/webhook/reconciliation coverage and reviewed tax/invoice rules before live activation.

See [PRD traceability matrix](./REWARDLOOP_PRD_TRACEABILITY.md) for requirements, evidence and the ordered implementation backlog.
