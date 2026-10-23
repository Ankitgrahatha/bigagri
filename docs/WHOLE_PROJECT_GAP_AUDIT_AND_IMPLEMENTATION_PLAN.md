# Growta RewardLoop — Whole-Project Gap Audit & Implementation Plan

**Audit date:** 2026-10-23  
**Status:** Evidence-based planning document; not a production-readiness certification.  
**Canonical product repository:** [Ankitgrahatha/bigagri](https://github.com/Ankitgrahatha/bigagri)  
**Secondary frontend/API repository:** [Ankitgrahatha/growta-rewardloop](https://github.com/Ankitgrahatha/growta-rewardloop)  
**Production URL:** https://bigagri.vercel.app/  
**Supabase project:** `guhhuqxrobhuumwrypnc`

## Executive summary

The project has a meaningful MVP foundation and substantial database/security test coverage. Billing source, webhook processing, checkout recovery, health monitoring and controlled release workflow are now present in the canonical repository, but the product is **not complete and not approved for a production launch**. The largest risk remains release drift: source, deployed frontend, deployed Edge Functions, database migration history, and product scope are not yet aligned.

The current evidence shows:
- The `bigagri` repository has the main admin console, admin settings, the broader SQL migration chain, multiple CI/security workflows and the master gap/traceability docs.
- `growta-rewardloop` is a separate smaller static PWA/API repository with its own deployment/project history. It is not automatically synchronized with `bigagri`.
- Admin screens include partner verification, product catalogue/lifecycle controls (capability-gated), QR batch issue/revoke/export, campaign operations and point valuation, redemption queue, and recent audit activity.
- The settings page explicitly states that SMTP, Supabase Auth configuration and Auth template publishing are not integrated; its “send test email” action is a placeholder.
- Product CRUD migrations and several later security migrations exist in Git but are not all deployed to the linked production Supabase project.
- The production Supabase migration history still reports the original 13 versions. A schema-baseline/history reconciliation gate must be completed before any pending production migration is run.
- The production deployment is behind Git `main`; the recorded deployment limit was HTTP 402 for Vercel build quota. Do not repeatedly trigger builds or treat a READY deployment as proof it runs current code.
- Six legacy Edge Function routes remain deployed with manual JWT checks and wildcard CORS; `onboard-farmer` also has a divergent profile status/write path. Do not retire these until traffic and callers are reviewed.
- Supabase Auth leaked-password protection was recorded as disabled. Enable and verify before launch.
- A substantial SaaS billing foundation now exists in source and passes CI contract/database tests, but production has not received its billing migrations or Edge Functions and test-mode provider lifecycle evidence is missing. External reward fulfilment, partner settlement and complete fraud-case workflow also remain unverified.

## Confidence and evidence rules

Labels:
- **Verified in source:** code/docs/tests exist in the repository.
- **CI-tested:** an automated test passed in a disposable/test environment; not proof of live behavior.
- **Production-confirmed:** checked against the connected live deployment/service at a recorded point in time.
- **Partial / blocked / not verified:** code exists but acceptance evidence or a required integration/release is missing.
- **Backlog:** not present as a complete capability in reviewed source.

A UI component, API action, migration file, successful CI run, or Vercel deployment marked READY does not individually establish end-to-end completion. Close each item only when code, authorization, automated tests, live acceptance evidence, monitoring and rollback/release notes agree.

## P0 — Release safety and production/source alignment

### P0.1 Reconcile production database safely
**Gap:** migration source and remote migration history are not aligned; later migrations are pending. A schema-only baseline is not a backup.

**Work**
1. Confirm required GitHub secrets and the protected `production` environment/reviewer gate for the manually dispatched release workflow.
2. Take/verify an appropriate backup or documented recovery path and record restore constraints.
3. Read-only compare production catalog to the checked-in baseline: columns, constraints, enums, functions and security properties, indexes, policies, RLS flags, grants, triggers and default privileges.
4. Compare all 13 remote migration timestamps to the baseline/no-op markers.
5. Only if the schema comparison proves equivalence, have the approved operator perform history-only repair for the baseline marker, then re-list migration status and inspect the exact dry-run.
6. Review each pending migration in order; deploy only through the protected release workflow. Verify the live schema/functions/security after each release.
7. Never run baseline DDL against production; never use `db reset --linked`; do not use migration repair as a substitute for schema proof.

**Acceptance:** remote/local migration list is reconciled; dry-run contains only reviewed migrations; migration workflow is approved and passes; live catalog and key RPC behavior match expected versions; recovery evidence is recorded.

### P0.2 Align frontend and backend releases
**Gap:** `bigagri` and `growta-rewardloop` are separate repositories; the latest Git commit is not necessarily the code serving the production alias.

**Work**
1. Declare one canonical source for the production product and write down which routes/assets belong to each repo.
2. Decide whether to consolidate the duplicate frontend/API code or maintain two explicit deployment targets. Do not silently copy code between repos.
3. Record commit SHA, Vercel deployment ID, alias, Supabase function versions and migration version in one release manifest.
4. When deployment quota permits, deploy the reviewed commit once, verify production smoke checks and confirm the alias serves the expected commit.
5. Add an automated release drift check that fails when required frontend markers/API capability versions are missing.
6. Preserve a known-good rollback deployment and a documented rollback procedure.

**Acceptance:** production alias, repository, commit SHA, API function version and migration set are traceable and mutually compatible; smoke checks pass on the actual alias.

### P0.3 Identity and privileged account security
**Gap:** Auth email lifecycle is not proven; leaked-password protection was recorded disabled; privileged MFA policy and account recovery are not fully evidenced.

**Work**
- Configure a trusted custom SMTP sender/domain, SPF/DKIM/DMARC as applicable, redirect allowlist, confirmation/recovery templates and rate limits.
- Enable leaked-password protection and verify via a controlled test.
- Test signup, confirmation, sign-in, sign-out, expired/revoked session, recovery, resend cooldown, suspended account and invalid-link states.
- Define privileged admin MFA requirements, operator provisioning/revocation and emergency recovery.
- Add login throttling/abuse controls and safe support process.

**Acceptance:** positive and negative lifecycle tests pass against the intended live configuration; no production secrets are exposed in frontend or logs.

### P0.4 Legacy route containment
**Gap:** six legacy routes remain deployed with `verify_jwt=false`, manual token validation and wildcard CORS; legacy onboarding writes profile state differently from the canonical API.

**Work**
- Search all repos, deployments, workflows and external clients for route references.
- Inspect a privacy-safe request-log window to identify actual callers.
- Move callers to the canonical API and test parity.
- Restrict exact CORS allowlists where safe, add route-level tests, then retire one legacy route at a time with rollback and post-retirement monitoring.
- Do not disable a route based on a short quiet period alone.

**Acceptance:** no untracked caller remains; canonical flow is proven; route is retired only after documented traffic evidence and rollback plan.

## P1 — Complete and make the admin console navigable

### P1.1 Admin shell and route model
**Current:** the admin console is primarily a long dashboard with sections, not a complete tab-based control plane.

**Work**
- Build a responsive persistent navigation with route/deep-link support, active states, breadcrumb/title, loading/empty/error/retry states, keyboard accessibility and mobile navigation.
- Hide navigation items by server-returned capabilities, but enforce all authorization again on the backend.
- Provide tenant context and a visible environment indicator; show destructive-action confirmation and reason fields.
- Add global search only after the data scope and permission rules are defined.

### P1.2 Admin module coverage matrix

| Module/tab | Current evidence | Required work / exit criteria |
|---|---|---|
| Overview dashboard | Basic counters exist | Validate definitions, time windows, tenant scoping, empty/error states and reconciliation to source records |
| Partners/farmers | Partner verification and current-page CSV exist | Complete search/filter/pagination across all pages, partner detail/history, status reasons, suspension/reinstatement, duplicate handling and export permission tests |
| Tenant directory/control plane | Tenant context exists; current deployment has a single configured tenant limitation | Provision, view, suspend/reactivate, configure, export/delete by policy; membership-based tenant resolution and cross-tenant denial tests |
| Roles & memberships | Server-side membership checks exist | Role/permission matrix, invite/revoke, least privilege, privileged MFA policy and separation-of-duties tests |
| Products & SKU/pack | Product CRUD source/migrations exist but are capability/deployment gated | Deploy matching API+migrations first; complete create/edit/archive, SKU/pack validation, lifecycle audit and tenant isolation |
| QR batches | Issue/revoke/export exists in code | Batch detail, per-code reconciliation without re-exposing secrets, print-ready labels, custody/download instructions, recall and failure recovery |
| Campaigns | Create/status/point value and budget-related SQL exist | Full draft/preview/approve/schedule/pause/archive, timezone boundaries, immutable rule versions, eligibility/caps, budget liability and campaign performance |
| Rewards catalogue | Catalogue and redemption paths exist | Admin reward CRUD, inventory, eligibility, fulfilment details, images/content, inactive/out-of-stock behavior and stock audit |
| Redemptions/fulfilment | Queue and resolution exist | State machine, provider dispatch, retry/idempotency, cancellation/refund, shipping/reference status, exception queue and reconciliation |
| Points/ledger | Immutable ledger protections tested in isolated CI | Read-only ledger explorer, per-account statement, reversals, reconciliation, anomaly queue; never edit posted ledger rows |
| Audit & security events | Recent audit activity and gated audit API exist | Search/filter/date range, actor/action/tenant/correlation, reason visibility, export controls, retention policy and tamper-resistance |
| Fraud/risk review | Rate limiting exists; full case management not evidenced | Case creation, evidence, risk signals, assignment, reasoned decision, appeal/false-positive handling and audited closure |
| Reports & analytics | Basic counters and CSV exports | Define metric dictionary, date ranges, tenant-safe aggregation, export limits, profitability/liability and ledger-reconciled reports |
| Integrations & system health | Limited configuration status | Auth/SMTP/API/queue/provider health, version compatibility, failed-job queue, redacted diagnostics and alert routing |
| Email/Auth settings | Preference form exists; live integration is blocked | Implement privileged server-only Auth management, secret handling, test email and publish/rollback; otherwise remove misleading controls |
| Content/branding | Not verified as a full CMS | Tenant logo/theme/language, public storefront content, announcement/draft/preview/publish/version/rollback and cache invalidation |
| Plans/billing/entitlements | Versioned plans, tenant subscriptions, checkout, webhook inbox/worker, reconciliation and fail-closed entitlements implemented in source; not production-deployed/verified | Deploy only after migration reconciliation; run provider test-mode lifecycle; invoices/tax, refunds, dunning/grace, plan changes and usage metering remain separate work |
| Support/operations | Not verified as a complete workflow | Support tickets, safe impersonation policy (prefer no impersonation), dispute handling, incident notes, data export/deletion and account recovery audit |

**Acceptance for every admin module:** capability visible only to allowed roles; backend enforces tenant and role; full CRUD/read scope has validation and audit where relevant; automated allow/deny tests pass; loading/empty/error/success states exist; production behavior is tested before marking complete.

## P1 — Core loyalty business correctness

### P1.3 Product, pack, lot and QR traceability
- Define canonical relation: tenant → product → SKU/pack size → production/dispatch lot → QR batch → individual code → claim.
- Validate unique IDs and transitions; define damaged/duplicate label, batch custody, recall and quality-hold behavior.
- Review token entropy, hashing at rest, secret exposure in logs, one-time export, revoke and scan/claim eligibility.
- Add end-to-end tests from issued code to credited ledger event and from revoked/invalid code to safe denial.

### P1.4 Campaign rules and financial budget
- Define budget semantics explicitly: points liability, reward procurement cost, fulfilment cost, or separate budgets.
- Version rules and retain the rule version on each claim.
- Reserve budget atomically with claim/credit; enforce per-code/per-user/per-campaign caps and time-zone boundaries.
- Add race/exhaustion/failure tests and reports reconciling budget reservations to claims and ledger.

### P1.5 Points ledger and account reconciliation
- Keep ledger append-only; make reversals compensating entries.
- Define authoritative balance calculation and periodic reconciliation; report any ledger/cache/materialized-balance drift.
- Add fault-injection and retry tests for claim credit, redemption debit, refund, cancellation and stock restore.
- Alert on negative balances, duplicate accounting effects and unbalanced reservations.

### P1.6 Redemption fulfilment and partner settlement
- Define requested → reserved → accepted/processing → fulfilled / failed / cancelled states and legal transitions.
- Add provider-neutral fulfilment adapter only after a provider is chosen; use idempotency keys and reconcile unknown timeout outcomes before retry.
- Define partner payable ledger, fees, settlement statement, disputes and reconciliation separately from customer points.
- No external fulfilment integration is complete until sandbox callbacks, duplicate/out-of-order events, refund and manual exception handling pass.

## P2 — Multi-tenant SaaS, finance and growth capabilities

### P2.1 True multi-tenant control plane
- Remove hard-coded tenant assumptions in app and backend configuration.
- Resolve tenant from verified identity/membership; never trust client tenant ID as authorization.
- Add tenant provisioning, lifecycle, domains, branding, language, feature flags, configuration and data export/deletion.
- Test cross-tenant read/write/RPC/export/job isolation for every sensitive path.

### P2.2 SaaS monetization and accounting (separate from rewards)
- Design plan catalogue/versioning, trial, subscription, entitlement, usage meter, checkout, payment attempt, webhook inbox, invoices/credit notes, refunds, renewals, dunning, cancellations, taxes and reconciliation.
- Provider integration (e.g. Razorpay) is a candidate, not an existing verified feature.
- Verify webhook signatures against raw request bytes, persist/deduplicate events and handle out-of-order delivery idempotently.
- Have finance/accounting review Indian tax and invoice requirements before live payments.

### P2.3 Fraud, analytics and operational reporting
- Add a risk case workflow before adding opaque AI scoring.
- Establish metric definitions for activation, claim conversion, repeat engagement, campaign liability, redemption cost, fraud rate and fulfilment SLA.
- Add tenant-scoped reports, reconciliation and export audit.
- Keep deterministic abuse controls (rate limits, caps, uniqueness, idempotency) authoritative.

## P2 — Reliability, accessibility and performance

- Test Android low-memory/mobile browsers, camera permissions, manual QR entry, install/offline behavior, service-worker updates and stale-cache recovery.
- Verify Hindi/English coverage across errors, onboarding, admin, confirmation, empty and retry states.
- Add performance budgets, database query/index review, pagination bounds, load tests, abuse/rate tests and graceful degradation.
- Establish structured redacted logs, error tracking, uptime/smoke checks, alert ownership, incident response and post-incident review.
- Define backup retention, restore test, RPO/RTO, data retention, deletion/export process and dependency/security scanning.
- Verify security headers, CSP, CORS, secret scanning, dependency updates, accessibility and keyboard navigation.

## P3 — Later enhancements, only after correctness and pilot evidence
- Advanced risk scoring and recommendations.
- More advanced campaign segmentation and cohort analytics.
- Rich storefront personalization, notifications and partner integrations.
- Predictive forecasting/AI dashboards only when metric definitions and source data quality are proven.

## Cross-cutting delivery method

Every issue should include:
1. Requirement ID and owner.
2. User/business outcome and in-scope/non-scope.
3. UI route/components, API actions, DB tables/RPCs/migrations and external dependencies.
4. Authorization and tenant-isolation rules.
5. Unit/contract/integration/concurrency/negative tests.
6. Accessibility, localization, mobile and error-state criteria.
7. Deployment sequence and backward-compatibility requirement.
8. Production verification evidence, observability and rollback.
9. Status: Backlog → In progress → Code complete → CI passed → Staging verified → Production released → Production verified.

Do not move an issue to Production verified solely because code is merged or a deployment is marked READY.

## Recommended execution sequence

| Phase | Focus | Exit gate |
|---|---|---|
| 0 | Freeze scope; canonical repo/deployment decision; release evidence and permissions | Every live component has an owner/source/version; no unknown deployment target |
| 1 | Supabase migration reconciliation, Auth protection, legacy route dependency audit | Approved schema diff, backup/recovery plan, protected release workflow and Auth checklist |
| 2 | Apply reviewed backend/security migrations and release compatible API/frontend | Live schema/function versions match release manifest; smoke tests pass |
| 3 | Core farmer/partner, QR claim, ledger, campaign budget and redemption E2E | Duplicate/race/failure/reconciliation tests pass against staging and selected live smoke paths |
| 4 | Admin shell, roles/tenants, module completion and settings integration | Every shipped tab has capability + backend authorization + audit + tests |
| 5 | Fulfilment, fraud cases, reports, operational support | End-to-end exception handling and reconciliation work |
| 6 | Multi-tenant onboarding, branding, content and SaaS billing | Tenant isolation, billing webhook/idempotency and accounting review pass |
| 7 | Load, security, accessibility, recovery and pilot sign-off | Release checklist signed; rollback/restore drill and monitoring verified |

## Release-blocking checklist

- [ ] Confirm one canonical production repo and documented relationship to the secondary repo.
- [ ] Complete read-only production schema/migration comparison and approved history reconciliation.
- [ ] Apply pending production migrations only through the protected workflow.
- [ ] Deploy the matching Edge Function version and frontend commit; verify actual alias and release manifest.
- [ ] Enable Supabase leaked-password protection and verify Auth/email flows.
- [ ] Complete legacy route traffic/caller review and safe consolidation.
- [ ] Run tenant/role negative tests, QR replay/race tests, budget exhaustion, redemption refund/stock tests and live smoke checks.
- [ ] Validate backup/recovery, logs/alerts, secrets, headers, dependency/security checks and rollback.
- [ ] Sign off on pilot scope, support owner, data retention and incident procedure.

## Explicit non-goals for this release plan

- Do not add features just to make a menu look complete while backend authorization or data semantics are missing.
- Do not enable production product CRUD before matching migrations and Edge Function code are released.
- Do not execute schema baseline SQL against the existing production database.
- Do not retire legacy functions without caller/traffic evidence.
- Do not add live payment processing before billing policy, webhook security, accounting and reconciliation are ready.
- Do not describe CI-only database tests as proof of production behavior.

## External release guidance

The release gates above follow the same core principles as Supabase's official production and migration guidance: use version-controlled migrations, review schema drift, use staged/approved deployments, enable RLS and Auth protections, configure trusted SMTP, and validate backups, performance and availability. See:
- https://supabase.com/docs/guides/deployment/going-into-prod
- https://supabase.com/docs/guides/deployment/database-migrations
- https://supabase.com/docs/guides/deployment/managing-environments
