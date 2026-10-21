# Growta RewardLoop — Master Gap Register and Systematic Implementation Roadmap

**Reviewed:** 2026-10-21  
**Canonical repository:** `Ankitgrahatha/bigagri` (`main`)  
**Production URL:** https://bigagri.vercel.app/  
**Status:** Planning baseline; not a production-readiness certification.

## 1. Purpose and rules

This is the master inventory for completing RewardLoop as a secure, tenant-aware agricultural loyalty SaaS. It consolidates the traceability matrix and adds missing commercial, operational, governance and SaaS control-plane areas.

**Evidence labels**
- **Present/partial:** some code or schema exists, but acceptance tests or full workflows are missing.
- **Not verified:** current repository evidence does not prove the feature works end to end.
- **Backlog:** implement only after dependencies and acceptance criteria are satisfied.

A UI screen, table, deployed function, or successful build does not alone mean a feature is complete. Every item needs source, authorization, automated tests, operational evidence, documentation, and a release decision. Do not claim a feature is live until it is verified.

## 2. Product boundaries and financial separation

Keep these domains distinct:
1. **Growta SaaS billing:** subscription revenue, plans, invoices, taxes, payment attempts, refunds and subscription entitlements.
2. **RewardLoop loyalty accounting:** points earned/reversed, redemptions, reward stock, campaign budgets and fulfilment liabilities.
3. **Partner settlement:** amounts payable to reward/fulfilment partners, settlement statements, fees and disputes.
4. **Campaign finance:** approved campaign budget, point liability assumptions, reward acquisition cost and actual redemption cost.

No payment callback, points entry, cache value or admin UI state can be treated as authoritative without server-side verification and durable database records.

## 3. Full gap register

### A. Release safety, engineering and environments
- **Current:** CI/smoke checks exist; transaction-level test coverage and recovery evidence remain incomplete.
- **Gaps:** repeatable local/test environment; migrations from clean database; environment separation; branch protections; dependency/security scans; build/deploy provenance; rollback; feature flags; secrets inventory; test data factory; release checklist.
- **Plan:** establish baseline and environment matrix; make CI run lint/type/syntax, unit, integration, RLS and contract tests; validate migrations against clean and upgraded databases; require checks before merge; document rollback and deployment verification.
- **Acceptance:** clean install and upgrade tests pass; secrets absent from source; deployment can be traced to commit; rollback rehearsal recorded.

### B. Identity, authentication and account lifecycle
- **Current:** Supabase email/password onboarding exists; production email and confirmation remain unverified.
- **Gaps:** confirmed signup, email verification, reset-password, invite flow, session expiry/revocation, MFA policy for privileged users, account deletion/export policy, login throttling, user suspension, recovery and support workflow.
- **Plan:** verify SMTP/domain and Auth redirect configuration; test every lifecycle state; add server-side authorization checks and privileged-user MFA guidance; document retention and recovery.
- **Acceptance:** positive and negative E2E tests pass for signup, confirmation, login, logout, recovery, expired sessions and suspended accounts.

### C. Multi-tenancy and authorization
- **Current:** tenant/membership schema and tenant IDs exist; app configuration is bound to `growta-rewardloop`.
- **Gaps:** tenant provisioning, tenant resolution from authenticated membership, isolation tests for all read/write/export paths, tenant lifecycle, invitations, custom domains, per-tenant branding, support access controls, deletion/export and tenant-aware jobs.
- **Plan:** derive tenant scope server-side from verified identity and membership; never trust client tenant IDs as authority; inventory RLS/policies/RPCs/Edge Functions; add cross-tenant denial tests; build controlled tenant provisioning.
- **Acceptance:** tests prove Tenant A cannot read, alter, export, claim against, or administer Tenant B data via UI, REST, RPC, background jobs or guessed identifiers.

### D. Roles, permissions and audit
- **Current:** membership and admin operations exist; full permission matrix is not proven.
- **Gaps:** RBAC/permission catalog; least-privilege role templates; scoped support roles; separation of duties for refunds and plan overrides; admin activity history; security-event alerts.
- **Plan:** define platform owner, tenant owner/admin, campaign manager, finance, support, partner operator and farmer/retailer roles; enforce on server; log actor, tenant, action, reason and correlation ID; restrict sensitive overrides.
- **Acceptance:** role matrix tests cover allow/deny paths; sensitive actions require reasons and are auditable.

### E. Products, packaging and traceability
- **Current:** product management and QR batch issuance exist in code.
- **Gaps:** complete product CRUD/lifecycle, SKU/pack-size/lot linkage, production and dispatch traceability, print-ready QR labels, batch custody, duplicate/defective label handling, recall/quality hold and audit.
- **Plan:** define product → SKU/pack → production lot → QR batch model; validate uniqueness and lifecycle transitions; add batch preview, secure one-time token export and revoke/recall controls.
- **Acceptance:** every issued QR traces to the correct product/lot/tenant; revoked, malformed and ineligible codes fail safely; exported secrets are not logged or retrievable after initial download.

### F. Campaign studio and budgets
- **Current:** campaign creation and status controls exist; budget enforcement and full rule versioning are not verified.
- **Gaps:** draft/preview/approval/schedule/pause/archive, immutable rule versions, eligibility, date/time-zone boundaries, audience segmentation, point value, cap per pack/user, anti-abuse limits, budget reservation and campaign profitability.
- **Plan:** version campaign rules; model approval and state transitions; atomically reserve budget with claims; define whether budget means point liability, reward acquisition cost, or both; add boundary and exhaustion tests.
- **Acceptance:** concurrent claims cannot exceed campaign caps/budget; old claims remain explainable against the rule version that applied.

### G. QR scans, claims and points ledger
- **Current:** scan/claim/ledger tables and server RPC paths exist; atomicity/idempotency require end-to-end proof.
- **Gaps:** token entropy/hash review, replay/race tests, claim-to-credit atomicity, append-only ledger enforcement, reversals, reconciliation, anomaly detection and audit retention.
- **Plan:** keep QR secrets hashed at rest; enforce unique constraints and server-side eligibility; make claim + ledger credit atomic; use compensating entries rather than editing posted ledger entries; add concurrency, duplicate, expiry, revocation and fault-injection tests.
- **Acceptance:** many parallel requests for one QR yield exactly one accepted claim and one credit; failed transactions leave no partial credit; every balance reconciles to ledger entries.

### H. Rewards, redemption, fulfilment and partner settlement
- **Current:** reward catalogue and redemption actions exist; stock restoration, cancellation and external fulfilment remain partially verified.
- **Gaps:** full reward CRUD, stock reservations, redemption lifecycle, timeout/retry, cancellation, refunds/reversals, provider adapters, partner SLA, settlement statements, dispute handling and reconciliation.
- **Plan:** reserve points and stock atomically; define state machine (requested → reserved → fulfilled / failed / cancelled); make provider calls idempotent; reconcile unknown outcomes before retrying; build partner ledger and exception queue.
- **Acceptance:** duplicate requests do not double-debit; failure/cancellation restores eligible balances and stock exactly once; fulfilment and partner settlement reconcile.

### I. SaaS plans, subscriptions, payment and monetization
- **Current:** billing implementation is not verified.
- **Gaps:** plan catalogue/versioning; monthly/yearly price and currency; trial, coupon and add-on rules; subscriptions; checkout; payment attempts; webhook inbox; invoice/credit note; refunds; renewals; proration policy; failed-payment dunning; grace periods; cancellations; entitlements; usage metering; overages; billing portal; tax/accounting exports; payment reconciliation.
- **Plan:** first settle policies and domain model; implement immutable plan versions and server-side entitlements; build provider adapter in test mode; verify webhook signature against raw body; persist and deduplicate events; process events idempotently and tolerate out-of-order delivery; reconcile provider state; then build tenant billing and platform billing console.
- **Acceptance:** test-mode checkout, duplicate/out-of-order webhook, wrong amount/currency, failed payment, refund, renewal, cancellation, upgrade/downgrade and recovery tests pass. Client redirect alone never activates entitlement. No live money until finance/tax review and release approval.
- **Provider note:** Razorpay is a candidate for India, not an existing integration. Official guidance emphasizes signature validation and idempotent webhook handling: https://github.com/razorpay/markdown-docs/blob/master/payments/payment-gateway/s2s-integration/recurring-payments/webhooks.md and https://github.com/razorpay/markdown-docs/blob/master/webhooks/validate-test.md.

### J. Invoices, tax, revenue and finance controls
- **Current:** not verified.
- **Gaps:** invoice numbering and immutability, seller/customer details, GST/tax treatment, credit notes, refunds, fee accounting, reconciliation, revenue recognition policy, collection aging and export.
- **Plan:** agree policy with accountant; persist invoice snapshots and line items; separate taxable amounts/tax/fees; produce reconciliation reports and auditable credit notes.
- **Acceptance:** invoice totals reconcile to provider payments and refunds; required Indian tax/legal fields are reviewed before live launch. This roadmap is not tax advice.

### K. Admin console and tenant control plane / CMS
- **Current:** admin operations and settings pages exist; settings are preferences, not a complete CMS/control plane.
- **Gaps:** comprehensive CRUD; global tenant directory; tenant creation/suspension; brand/theme/language; content pages and announcements; draft/preview/publish; content versioning/rollback; roles; feature flags; plan controls; billing; integration status; tenant-scoped configuration and cache invalidation.
- **Plan:** map each admin route to a capability and permission; build reusable tables/forms with pagination, validation, empty/error/loading states; implement versioned content and configuration; audit all privileged changes.
- **Acceptance:** an authorized tenant admin can manage only their tenant; preview/publish/rollback is tested; global settings cannot leak across tenants.

### L. Notifications and communications
- **Current:** production Auth email and test-email flow are unverified/placeholders.
- **Gaps:** verified transactional email, SMS/WhatsApp policy and provider adapters, templates/localization, delivery status, retry queue, unsubscribe/consent, campaign announcements, billing reminders and alert escalation.
- **Plan:** create provider-neutral notification interface; store delivery attempts/status; retry transient errors; redact secrets and sensitive QR data; separate operational alerts from marketing consent.
- **Acceptance:** confirmation/reset and billing-critical messages deliver in test environment; retries do not send uncontrolled duplicates; consent and opt-out are respected.

### M. Fraud, disputes and support
- **Current:** basic counters/exports exist; formal fraud case workflow is not verified.
- **Gaps:** duplicate/device velocity signals, geographic anomalies, suspicious partner patterns, case assignment, evidence, reason codes, appeals, dispute/SLA tracking, manual adjustment controls and false-positive monitoring.
- **Plan:** start with explainable deterministic rules and review queue; keep automated risk flags separate from irreversible decisions; require reasoned approvals for reversals and manual ledger adjustments.
- **Acceptance:** case actions are tenant-scoped and audited; false-positive and appeal workflow tested; risk scoring cannot directly mutate points.

### N. Analytics, reports and exports
- **Current:** basic admin counters and CSV exports exist; bounded data and inaccurate totals are risks.
- **Gaps:** server-side aggregate counts, pagination, filter semantics, tenant-scoped analytics, campaign ROI/cost, claim conversion, liability, redemption rates, cohort/retention, fraud review metrics, revenue MRR/ARR/churn, export audit and large-export jobs.
- **Plan:** define metric dictionary and source-of-truth formulas; implement database aggregates and paginated APIs; separate SaaS revenue from campaign costs and points liability; validate reports against source rows.
- **Acceptance:** sample reports reconcile to source transactions; exports respect tenant permissions and log who exported what.

### O. Redis/cache and rate limiting
- **Current:** Upstash Redis resource exists; application connection/use is not confirmed.
- **Gaps:** no verified app integration, key strategy, TTLs, rate limits, cache invalidation, outage fallback or cost monitoring.
- **Plan:** inspect current project/environment configuration; only then connect via server-side secrets; use Redis for rate limits, short-lived idempotency coordination where appropriate and cache—not authoritative balances, stock, entitlements or permissions; add tenant-prefixed keys and safe fallback.
- **Acceptance:** limits work under burst load; tenant keys cannot collide; Redis outage fails safely; no secret leakage. Do not create paid resources for this phase.

### P. Observability, security and privacy
- **Current:** Sentry is not confirmed in inspected source; production alerting and backup/restore drill are not verified.
- **Gaps:** error tracking, release/source maps, structured logs, trace/correlation IDs, uptime checks, alert routing, PII redaction, secret scanning, dependency audit, incident response, retention policy, privacy/data export/deletion.
- **Plan:** instrument browser and server/Edge paths; redact tokens, phone/email where not needed, QR payloads and payment secrets; define severity and actionable alerts; add incident runbooks and privacy inventory.
- **Acceptance:** seeded non-sensitive test error appears with release metadata; no secrets/QR tokens in events; alerts and restore procedure are rehearsed.

### Q. Performance, accessibility and rural usability
- **Current:** responsive Hindi-first PWA shell exists; device-level E2E not independently verified.
- **Gaps:** low-bandwidth handling, offline-safe boundaries, Android browser/device matrix, accessibility, keyboard/screen reader, camera permissions, localization completeness, performance budgets and error recovery.
- **Plan:** test representative Android devices and browsers; optimize assets; provide manual QR entry fallback; clearly distinguish queued/offline actions from confirmed transactions; do not permit offline claim/redemption finalization.
- **Acceptance:** core user flows pass device/browser matrix on slow networks and camera-denied cases; no duplicate actions after reconnect.

### R. Fulfilment, integrations and API contracts
- **Current:** no verified reward-provider integration; legacy and consolidated API paths may coexist.
- **Gaps:** integration inventory, provider contracts, retry policy, timeouts, signature validation, webhook replay defense, API versioning, deprecation policy, health checks and contract tests.
- **Plan:** inventory all callers before retiring legacy Edge Functions; select canonical route per operation; add contract tests and request IDs; build provider adapter and reconciliation queue.
- **Acceptance:** every supported route has auth and contract tests; legacy routes cannot bypass controls; external failures are recoverable and auditable.

### S. Data governance, backup and recovery
- **Current:** schema/audit tables exist; restore drill and retention policy not verified.
- **Gaps:** data classification, retention/deletion rules, backup verification, point-in-time recovery assumptions, migration rollback, export/restore, disaster recovery objectives and reconciliation after restore.
- **Plan:** document critical tables and owners; verify backup settings/retention; test restore in isolated environment; run post-restore ledger and tenant consistency checks.
- **Acceptance:** dated restore drill report shows data integrity checks and measured recovery time. Never use production business data for routine destructive tests.

### T. Operations, launch and customer success
- **Current:** launch blockers documented; no evidence of a complete operational runbook.
- **Gaps:** onboarding checklist, help/FAQ, support queue, incident severity, escalation, status page, release notes, training, tenant offboarding, service limits and launch rollback criteria.
- **Plan:** write operational playbooks and customer onboarding; pilot with a limited tenant cohort; use feature flags and explicit launch gates; review pilot metrics and support cases before wider rollout.
- **Acceptance:** support can diagnose a tenant without unrestricted data access; rollback and incident escalation are rehearsed.

## 4. Dependency-ordered implementation phases

### Phase 0 — Inventory and baseline (first)
1. Freeze feature claims: label each requirement present, partial, unverified or backlog.
2. Map repo routes, Edge Functions, RPCs, tables, RLS policies, environment variables and Vercel project.
3. Identify canonical API path; inspect legacy function callers before any deprecation.
4. Confirm current migrations, CI workflows, deployment state and security advisor output.
5. Publish updated gap matrix and a risk-ranked issue list.

**Exit gate:** evidence map is complete enough that changes will not accidentally bypass existing flows.

### Phase 1 — Security and deterministic transaction correctness
1. Authentication/email verification and admin access.
2. Tenant scope and role enforcement.
3. Automated RLS/RPC authorization tests.
4. Atomic QR claim + points ledger; idempotency/concurrency/replay tests.
5. Atomic redemption reservation, stock/points restoration and budget controls.
6. Campaign rule versioning and audit.
7. Remove or lock down any legacy bypass paths after caller analysis.

**Exit gate:** no real-value public campaigns until critical claim, ledger, redemption and isolation tests pass.

### Phase 2 — Platform foundations
1. Admin route/capability/permission matrix.
2. Tenant provisioning and lifecycle.
3. Tenant-aware CMS/configuration with versioning and rollback.
4. Server-side pagination, aggregates and export authorization.
5. Notification provider abstraction and verified auth emails.
6. CI quality gates, release tagging, rollback and operational documentation.

**Exit gate:** a second test tenant can be onboarded and isolated end-to-end.

### Phase 3 — SaaS commercial model and billing
1. Agree plan names, entitlements, usage limits, trial/grace/cancellation and proration policy.
2. Design schema for plan versions, subscriptions, invoices, payment attempts, webhook events, refunds/credit notes, entitlements and usage records.
3. Add constraints, RLS/service-role boundaries and audit trail.
4. Build gateway adapter in test mode and secure webhook ingestion.
5. Add idempotent event processing and provider reconciliation.
6. Build customer billing portal and Super Admin billing console.
7. Add invoice/tax exports after accountant review.
8. Test upgrade/downgrade, renewal, failure, refund, cancellation and tenant suspension/recovery.

**Exit gate:** all billing tests pass in test mode; no live payments until secrets, provider account, legal/tax treatment and monitoring are approved.

### Phase 4 — Operational completeness
1. Product/pack/lot traceability and QR printing/custody.
2. Partner verification and reward fulfilment provider interface.
3. Fraud cases, appeals and support/dispute management.
4. Reconciled analytics and financial reports.
5. Sentry/observability, alert routing, safe Redis rate limiting/cache.
6. Backup/restore drill, privacy/retention review and incident runbooks.

**Exit gate:** pilot operators can resolve ordinary and exceptional cases without direct database edits.

### Phase 5 — Controlled pilot
1. Use a dedicated test tenant and test payment credentials.
2. Run seeded end-to-end scenarios; never create test claims/redemptions in production.
3. Conduct security, privacy, accessibility and load checks.
4. Run a limited pilot with capped budgets and explicit support coverage.
5. Review reconciliation, fraud false positives, conversion, cost, errors and support volume.
6. Expand only after sign-off.

**Exit gate:** documented go/no-go approval with rollback criteria and owners.

### Phase 6 — Scale and advanced capabilities
1. Tenant self-service onboarding and custom domains.
2. Advanced analytics and explainable risk scoring.
3. Integration marketplace, billing add-ons and usage-based billing if justified.
4. Multi-region/reliability improvements only when observed load and recovery requirements justify the cost.

**Exit gate:** each expansion has usage evidence, cost justification and regression coverage.

## 5. Admin information architecture — target, not a claim of current implementation

1. Executive overview
2. Tenants and onboarding
3. Users, roles and permissions
4. Product catalogue and SKU/pack management
5. Production lots and traceability
6. Campaign studio and approvals
7. QR batch factory and revocation
8. Scan, claim and exception review
9. Points ledger and reconciliation
10. Rewards catalogue and inventory
11. Redemptions and fulfilment
12. Partner directory and settlement
13. Fraud, disputes and support cases
14. Analytics, reports and exports
15. CMS, templates and notifications
16. Plans, subscriptions and entitlements
17. Payments, invoices, refunds and reconciliation
18. Integrations, webhooks and API health
19. Tenant branding and configuration
20. Security, audit and system health
21. Global settings, feature flags and release controls

Every workspace must have an explicit role matrix, tenant scope, audit requirements, pagination strategy, error/loading/empty states and acceptance tests.

## 6. Global definition of done

For each requirement, record:
- Requirement ID and user/business outcome.
- Current state and linked source/migration.
- Owner, dependency and priority.
- Authorization and tenant-scope design.
- Success, failure, duplicate, retry and unauthorized tests.
- Observability, audit and support implications.
- Migration/deployment and rollback evidence.
- Acceptance result, residual risks and updated documentation.

Do not use a green build as a substitute for transaction tests. Do not use a test payment as evidence of live payment readiness. Do not use a successful admin page load as proof of authorization.

## 7. Priority scheme

- **P0 — Critical safety:** auth, tenant isolation, ledger integrity, QR claim atomicity, redemption consistency, budget enforcement, secrets, payment correctness before live billing.
- **P1 — Required for controlled pilot:** product/QR operations, campaigns, partner workflow, notifications, support, reconciliation, core reports and release recovery.
- **P2 — SaaS readiness:** plan catalogue, subscriptions, billing portal, CMS/control plane, usage metering, tenant self-service, Sentry and Redis integration.
- **P3 — Scale/optimization:** advanced risk models, marketplace integrations, custom domains, sophisticated cohorts and usage-based monetization.

Priorities reflect dependencies: payment code should not be launched ahead of authentication, tenant isolation, auditability and test infrastructure.

## 8. Cost and production safety guardrails

- Prefer existing free-tier infrastructure and local/test environments; do not create paid branches/resources without explicit approval.
- Keep production read-only during gap discovery. No synthetic production claims, redemptions, refunds or payment attempts.
- Never expose service-role, gateway or Redis credentials in code, chat, logs or browser bundles.
- Keep secrets in server-side environment storage and rotate any credential accidentally exposed.
- Test gateway webhooks using provider test mode and validate raw-body signatures; deduplicate event IDs and tolerate retries/out-of-order delivery.
- Treat live payment activation, real-value campaigns, destructive migrations and production data mutation as separate release decisions requiring explicit verification.

## 9. Immediate next actions

1. Complete Phase 0 evidence inventory and update the traceability matrix.
2. Fix stale docs to match current deployed Edge Function and CI evidence.
3. Add missing automated tests for critical transaction invariants.
4. Close P0 tenant/auth/ledger/redemption gaps before enabling real-value rewards.
5. Build the SaaS billing model and test-mode lifecycle only after the security foundation.
6. Add CMS/control plane, monitoring and safe Redis use.
7. Pilot, reconcile, and make a documented go/no-go decision.

This document is the planning baseline. It does not claim that backlog items have already been implemented.
