# Growta RewardLoop — Comprehensive SaaS Gap Audit & Implementation Roadmap

**Audit date:** 2026-10-23  
**Repository:** `Ankitgrahatha/bigagri`  
**Status:** Evidence-based implementation plan; not a production-readiness certification.  
**Production frontend:** https://bigagri.vercel.app/  
**Supabase project ref:** `guhhuqxrobhuumwrypnc`  
**Companion documents:** [Implementation status](./IMPLEMENTATION_STATUS.md), [whole-project audit](./WHOLE_PROJECT_GAP_AUDIT_AND_IMPLEMENTATION_PLAN.md), [master gap register](./MASTER_GAP_REGISTER_AND_ROADMAP.md), [PRD traceability](./REWARDLOOP_PRD_TRACEABILITY.md).

## 1. Executive assessment

Growta RewardLoop has a useful farmer-facing PWA, Supabase authentication and database foundation, partner/admin workflows, QR claims, points ledger, campaign and redemption operations, and meaningful isolated PostgreSQL security tests. It is **not yet a complete multi-tenant SaaS product and is not approved for unrestricted production rewards or live subscription billing**.

The critical gap is alignment: source code, migrations, deployed Edge Functions, production database history and the production Vercel alias do not consistently represent the same release. SaaS monetization is a new workstream, not an existing feature. A recent branch adds a Razorpay raw-body signature verification primitive and tests; this is only one prerequisite and does not constitute checkout, durable webhook processing or subscriptions.

This plan covers platform safety, core rewards correctness, multi-tenancy, SaaS billing, admin/control-plane completeness, operations, user experience and release verification. Each workstream must move through evidence-based states: **Backlog → In progress → Code complete → CI passed → Staging verified → Production released → Production verified**.

## 2. Evidence labels and working rules

- **Implemented / source evidence:** source or schema exists; does not prove runtime behavior.
- **CI-tested:** automated checks passed in a disposable/test environment; does not prove production state.
- **Production-confirmed:** verified against the exact live deployment/service and recorded with a timestamp and version.
- **Partial / not verified:** incomplete or missing end-to-end evidence.
- **Blocked:** requires access, an operator approval, provider account, quota recovery, policy decision or safe release gate.

Rules:
1. No production mutation without a reviewed diff, backup/recovery plan, explicit approval and recorded post-change verification.
2. Never apply the schema baseline as DDL to production, run a linked reset, or use migration history repair to hide schema differences.
3. Never trust a tenant ID, role, amount, payment status or entitlement supplied by the browser.
4. Never retire legacy endpoints solely because a short log window shows little/no traffic.
5. Never enable live payments based on a browser redirect or unverified webhook.
6. Never claim a screen or module is complete until backend authorization, negative tests, auditability, failure states and deployment compatibility are proven.
7. Keep SaaS subscription accounting separate from farmer points, campaign liability, reward inventory and partner settlements.
8. Do not add paid services, upgrades or usage charges without explicit approval.

## 3. Current known release risks

Treat these as the latest recorded findings in repository documentation and re-check them before execution because live state can change:

- Production migration history records 13 original migration versions while later source migrations are pending; safe schema/history reconciliation is a hard gate.
- Production frontend has been reported behind Git `main`; the Vercel build/deployment quota previously returned HTTP 402. Do not repeatedly trigger builds or infer live code from a READY deployment.
- Production `rewardloop-api` was recorded at version 9, without all later product/security migration capabilities.
- Six legacy Edge Function routes remain deployed. Caller references and a longer traffic window must be reviewed before deactivation; one legacy onboarding route has a divergent profile-write path.
- Supabase Auth leaked-password protection was recorded disabled; email delivery, confirmation/recovery and privileged MFA policy are not fully verified.
- Admin settings are preferences, not a live SMTP/Auth configuration integration; the test-email action is a placeholder and must remain honestly labelled.
- True self-service tenant onboarding and tenant-aware branding/control-plane workflows are not complete; configuration has a single-tenant assumption.
- SaaS plans, subscriptions, entitlements, usage metering, checkout, durable payment events, invoices, refunds, tax handling and billing consoles are not verified.
- Formal fraud cases, provider fulfilment, partner settlement, incident response, alerting and restore drills are incomplete or not verified.
- Browser-level production end-to-end proof of signup through claim, redemption and cancellation/fulfilment is missing.
- A limited clean runtime-error query is not proof of correctness or adequate observability.

## 4. Prioritised workstreams

### P0 — Release integrity, database safety and production/source alignment

**Gap:** production schema, migration history, API version and frontend release are not proven to be mutually compatible.

**Implementation**
1. Inspect current `main`, open PRs, workflow status, migration files and release workflow before each batch.
2. Confirm protected production environment, required reviewers, access secrets and the manually gated migration workflow. Never print secret values.
3. Capture a backup or documented recovery path and establish restore constraints, RPO/RTO and an owner.
4. Run read-only schema comparison covering tables/columns, enums, constraints, indexes, triggers, functions/security-definer settings, RLS, policies, effective grants and default privileges.
5. Compare all remote migration versions with the checked-in baseline and historical no-op markers. If and only if the schema equivalence is proven, an approved operator may perform the documented history-only reconciliation and inspect the linked dry-run.
6. Review every pending migration in timestamp order; apply only via the protected release workflow. Verify schema/function/grant fingerprints and key RPC behavior after each batch.
7. Define the canonical production repository and explicitly map any secondary repository, project and deployment; do not silently copy source between repositories.
8. Produce a release manifest recording frontend commit SHA, Vercel deployment ID/alias, Edge Function version, migration versions and smoke-test run.
9. Preserve a known-good rollback target; make rollback instructions executable and rehearse them in a non-production environment.

**Acceptance**
- Read-only schema comparison and migration-history plan reviewed by an authorized operator.
- Linked dry-run contains only expected reviewed migrations.
- Backup/recovery evidence and protected approval are recorded.
- Post-release live schema and function checks match the release manifest.
- Production alias serves the exact intended commit; smoke tests pass on the live alias.
- No production release is attempted merely to clear a CI marker or while deployment quota is blocked.

### P0 — Authentication, privileged authorization and legacy Edge Functions

**Gap:** live Auth lifecycle, leaked-password protection, privileged MFA and legacy route containment are not fully verified.

**Implementation**
- Configure and test trusted email delivery, sender domain and SPF/DKIM/DMARC where applicable, confirmation/recovery templates, redirect allowlist and rate limits.
- Enable leaked-password protection and verify using controlled test accounts.
- Test signup, email confirmation, sign-in/out, expired/revoked session, recovery, resend cooldown, suspended user, invalid links and abuse throttling.
- Define admin MFA, least privilege, operator onboarding/offboarding, emergency recovery and separation-of-duties rules.
- Inventory references to every legacy function across both repositories, deployment config, browser bundles, scheduled jobs and external clients.
- Review privacy-safe route logs over an appropriate window, migrate known callers, verify behavior parity and tighten CORS to explicit trusted origins where compatible.
- Retire routes individually only after caller review, adequate traffic evidence, approved rollout and rollback plan. Keep JWT verification and server-side user/membership/role/tenant checks intact.

**Acceptance**
- Positive and negative live Auth tests pass; privileged accounts meet policy.
- Each privileged API has allow/deny tests for unauthenticated, wrong-role, wrong-tenant and suspended users.
- No untracked legacy caller remains before a route is retired; post-retirement metrics and rollback are monitored.

### P1 — Rewards, claims, QR traceability, campaign budget and ledger correctness

**Existing foundation:** server-side claim/redemption RPCs, idempotency protections, ledger immutability, QR batch operations, budget protections and isolated concurrency/security tests exist in source/CI. Production deployment of all later migrations remains a separate question.

**Implementation**
- Preserve the append-only points ledger; correct errors with compensating entries, never editing posted rows.
- Define canonical traceability: tenant → product → SKU/pack → lot → QR batch → individual code → claim → ledger event.
- Validate token entropy, token hashing at rest, one-time export, access controls, batch custody, recall, revoke, invalid/damaged label and replay behavior.
- Pin a campaign rule/version to each award; specify budget semantics explicitly (points liability, acquisition cost, fulfilment cost and/or separate budgets).
- Enforce eligibility, per-code/user/campaign caps, timezone boundaries, campaign budgets and claim-credit atomicity at the database transaction boundary.
- Make redemption state transitions explicit: requested → reserved → processing → fulfilled, or failed/cancelled/rejected. Make every transition idempotent.
- Prove that cancellation/rejection restores points and finite stock exactly once; fulfillment does not refund. Handle timeouts by querying/reconciling provider state before retry.
- Add ledger explorer/account statement, compensating-entry audit, claim/redeem/budget reconciliation, anomaly queue and alerts for duplicate effects, negative balances and unmatched reservations.

**Acceptance**
- Unit, contract, SQL integration, concurrent race, replay, fault-injection and tenant-isolation tests pass.
- Every financial effect reconciles to an immutable ledger/reservation record.
- Production migration/function version is verified before enabling associated UI controls or campaigns.

### P1 — Tenant isolation and platform control plane

**Gap:** current configuration has a single-tenant assumption; full tenant lifecycle and self-service onboarding are not verified.

**Implementation**
- Resolve tenant scope only from authenticated membership and server-side policy, never from request-body tenant IDs.
- Define platform roles (platform owner/support/billing operator) separately from tenant roles (owner/admin/manager/operator/read-only) with a permission matrix.
- Build audited tenant provisioning, invitation, membership changes, suspend/reactivate, configuration, plan assignment, export and deletion workflows.
- Add tenant slug/domain, branding, locale, timezone, feature flags, environment, lifecycle state and integration configuration.
- Apply RLS and tenant constraints to tables, RPCs, Edge Functions, exports, asynchronous jobs, storage and analytics queries.
- Define safe support access: prefer audited scoped support actions over impersonation; require reason, time limit, visible banner and immutable audit if impersonation is ever approved.
- Add onboarding workflow, ownership verification, invitation expiry, duplicate identity handling and recovery for the first tenant admin.

**Acceptance**
- Cross-tenant read/write/RPC/search/export/storage/job tests deny access for every sensitive path.
- Role matrix tests prove both allow and deny behavior.
- Tenant lifecycle actions are audited and reversible where policy requires.
- A tenant can be created and administered without code changes or a hard-coded tenant slug.

### P1 — Admin shell and module completeness

Build a consistent responsive admin control plane with persistent navigation, deep links, active states, breadcrumbs, tenant/environment context, capability-aware visibility, server-side authorization, accessible keyboard navigation, and loading/empty/error/retry/success states. Destructive actions require confirmation and reason.

| Module | Known gap / required completion |
|---|---|
| Overview | Define metrics, time windows and tenant scope; reconcile counts to source records; test empty/error states. |
| Partners/farmers | Complete cross-page search/filter/pagination, detail/history, status reason, duplicate handling and export authorization. |
| Tenants | Provision/view/configure/suspend/reactivate/export/delete by policy; enforce membership-derived scope. |
| Roles/memberships | Invite/revoke, least privilege, MFA policy, separation of duties and audited role changes. |
| Products/SKU/pack | Ensure API and migrations are released before enabling controls; validate SKU/pack and lifecycle. |
| QR batches | Detail/reconciliation, print labels, custody/download guidance, recall, revoke and failure recovery. |
| Campaigns | Draft/preview/approve/schedule/pause/archive, immutable rule versions, timezone, eligibility/caps and budget reports. |
| Rewards catalogue | CRUD, inventory, eligibility, media/content, inactive/out-of-stock rules and stock audit. |
| Redemptions | State machine, dispatch/retry, provider references, cancellation/refund and exception queue. |
| Points ledger | Read-only explorer, statements, reversals, reconciliation and anomaly review; no direct edits. |
| Audit/security | Search/filter/date range, actor/action/tenant/correlation ID, reasons, retention and export controls. |
| Fraud/risk | Cases, evidence, signals, assignment, reasoned decisions, appeals/false positives and audited closure. |
| Reports/analytics | Metric dictionary, date ranges, safe aggregation, export limits, liability/profitability and ledger reconciliation. |
| Integrations/health | Auth/email/API/provider/queue health, compatibility, redacted diagnostics, failed jobs and alert routing. |
| Auth/email settings | Either implement server-only privileged integration and test/publish/rollback or keep controls clearly labelled as preferences/placeholders. |
| Content/branding | Tenant theme/logo/language, storefront content, announcement draft/preview/publish/version/rollback and cache invalidation. |
| SaaS billing | Plan/pricing, subscription, invoices, payments, entitlements, usage, failed-payment recovery and platform billing console. |
| Support/operations | Tickets, disputes, incident notes, account recovery audit, data export/deletion and safe support access. |

**Acceptance for every module:** source, backend permission checks, tenant scope, input validation, audit trail where applicable, tests, accessible UI states, docs and production evidence.

### P1 — SaaS plan catalogue, subscriptions and entitlements

**Gap:** no complete verified monetization domain model.

**Implementation**
1. Settle business policies before accepting money: monthly/annual pricing, currency, tax display, trial eligibility, grace period, cancellation effective date, upgrade/downgrade timing, proration/refund policy and suspension rules.
2. Create immutable plan versions with feature/limit definitions and published/retired state. Do not overwrite the price/version used by an existing invoice.
3. Model tenant subscription, subscription history, entitlement snapshot/evaluation, usage counter, invoice, invoice line, payment attempt, provider event, refund/credit note and audit record.
4. Implement a server-side entitlement resolver. Fail closed for restricted actions; do not infer entitlements from frontend flags or stale cache.
5. Define quota semantics and units for seats, partners, claims, QR issuance, campaigns, storage, exports and API usage; record usage at the authoritative event boundary.
6. Provide tenant billing pages for current plan, usage, invoices, payment status, renewal, upgrade/downgrade and cancellation.
7. Provide a separate platform billing workspace for plan versions, tenant subscriptions, approved overrides, payment exceptions and audit.
8. Keep subscription revenue and entitlements separate from farmer points, reward stock, campaign finance and partner settlement.

**Acceptance**
- Plan changes do not mutate historical invoices or retroactively change existing entitlements without explicit policy.
- Every restricted server action has plan/limit allow/deny tests.
- Subscription lifecycle transitions are audited, transactional and safe on retries.
- Suspension never deletes tenant data or corrupts loyalty history.

### P1 — Payment gateway, durable webhooks and accounting

**Gap:** no verified checkout, durable event inbox, invoice/refund/reconciliation workflow or tax-ready accounting. Razorpay is a candidate provider; selection and account eligibility/fees must be confirmed before commitment.

**Implementation**
1. Keep gateway code behind a provider-neutral adapter. Start in test mode; keep provider IDs alongside internal order, invoice and payment IDs.
2. Complete the webhook foundation: verify signature against exact raw bytes before parsing; use the provider event ID for deduplication; persist the verified event durably; return success only after durable acceptance; process asynchronously and idempotently.
3. Handle retries, duplicate and out-of-order events, secret rotation, malformed payloads, timeouts and replay. Do not trust event arrival order as the subscription state machine.
4. Bind every payment to one tenant, invoice/order, expected amount and currency. Quarantine mismatches for reconciliation; never activate an entitlement from client redirect alone.
5. Apply payment and subscription transitions transactionally and audit them. Use a transactional outbox/job or equivalent durable processing mechanism with bounded retries and dead-letter/review queue.
6. Add reconciliation against provider API/settlement data for unknown outcomes, missed webhooks, refunds and payment status mismatches.
7. Add invoices, credit notes, refund records, payment attempts, gateway fees, settlement exports and renewal/failure notifications.
8. Have a qualified accountant review Indian GST applicability, business identity/address, invoice numbering, place of supply, SAC/HSN treatment and credit-note requirements before issuing legal tax invoices.
9. Test payment success/failure, wrong amount/currency, duplicate event, delayed/out-of-order event, refund, cancellation, renewal, secret rotation and recovery. Do not test using live money.

**Acceptance**
- Test-mode checkout/webhook/reconciliation end-to-end passes.
- Duplicate event produces no duplicate invoice payment, entitlement extension or ledger effect.
- Invalid signature, wrong amount/currency/tenant and replayed IDs cannot grant entitlements.
- Financial reconciliation reports zero unexplained discrepancies before a live-money decision.
- Finance/accounting and security review approve the live launch; secrets remain server-side.

### P1 — Fulfilment provider and partner settlement

**Gap:** external reward fulfilment and partner settlement are not verified as complete workflows.

**Implementation**
- Define provider-neutral fulfilment adapter only after selecting a real provider and agreeing its SLA/returns contract.
- Model dispatch requests, provider references, retries, unknown outcomes, shipping/status callbacks, cancellation/return and exception handling.
- Keep provider calls outside long database transactions; use durable jobs/outbox and idempotency keys.
- Maintain a separate partner-payable ledger, fee model, settlement statement, disputes and reconciliation.
- Add manual exception handling with maker/checker approval and immutable reason/audit.

**Acceptance:** sandbox callbacks, duplicate/out-of-order events, timeout recovery, refund/return and settlement reconciliation pass.

### P1 — Fraud and abuse operations

**Gap:** rate limiting and deterministic guards exist, but a complete fraud case workflow is not verified.

**Implementation**
- Extend deterministic controls first: token uniqueness, per-actor rate limits, campaign/user caps, velocity thresholds, duplicate identities, unusual claim/redemption patterns and replay controls.
- Create a case workflow with risk signals, evidence references, owner/queue, severity, reasoned decision, false-positive appeal and closure audit.
- Keep sensitive evidence access restricted; avoid placing raw QR tokens, personal data or payment secrets in logs.
- Add alert thresholds and an operational response playbook. Introduce AI risk scoring only after ground-truth quality, evaluation and human review policies are established.

**Acceptance:** seeded abuse scenarios are detected, high-risk actions fail safely, case transitions are audited, and legitimate user false positives can be reviewed.

### P1 — Observability, support and reliability

**Gap:** monitoring/alerting, support operations, recovery drill and provider/job visibility are not sufficiently verified.

**Implementation**
- Add structured JSON logs with request/correlation IDs, tenant ID where safe, action, outcome, latency and redacted error class. Never log tokens, secrets, full payment payloads or unnecessary PII.
- Add error tracking, uptime/route smoke checks, function latency/error rates, database saturation, failed-job queue, webhook lag, payment reconciliation drift and claim/redemption anomaly alerts.
- Define alert owner, severity, runbook, escalation and incident/postmortem template.
- Add support tickets, dispute tracking, customer-facing status, data export/deletion request lifecycle and audited account recovery.
- Define backup retention, RPO/RTO, restore procedures, test data isolation, dependency/security scanning, vulnerability patch SLA and key rotation.
- Reassess unused indexes only after representative load/traffic evidence; do not remove indexes solely from an advisory snapshot.

**Acceptance:** alerts are exercised with a controlled test; a restore drill meets documented objectives; incident ownership and support escalation are demonstrated.

### P1 — PWA quality, accessibility, localization and performance

**Gap:** automated asset/syntax tests exist, but full browser-level mobile and language workflows are not proven.

**Implementation**
- Test Android low-memory devices and mainstream browsers; camera permission denied/unavailable; manual QR fallback; offline/install flow; stale service-worker cache and safe update recovery.
- Ensure Hindi and English cover validation, auth, claim/redeem, errors, empty/loading/retry states and admin screens.
- Add keyboard/screen-reader semantics, contrast, focus management, form errors and destructive-action confirmations.
- Establish budgets for page weight, API latency, query counts, pagination, bundle size and cache freshness.
- Add load, rate-limit, abuse and database contention tests; review slow queries and indexes with representative traffic.
- Add browser end-to-end tests for signup → confirmation → onboarding → claim → balance → redemption → cancellation/fulfilment and relevant admin flows.

**Acceptance:** critical user journeys pass on staging across target devices/locales; accessibility and performance regressions are gated in CI.

### P2 — Data governance and analytics

**Gap:** basic counters/CSV exports exist; a governed reporting and privacy lifecycle is not verified.

**Implementation**
- Define metric dictionary, grain, timezone, source-of-truth, freshness and owner for activation, claim conversion, repeat use, campaign liability, redemption cost, fraud, fulfilment SLA, subscription MRR/ARR, churn, failed payment and usage.
- Make tenant-safe aggregation and exports; enforce pagination/export limits, audit export actions and redact PII.
- Define data classification, retention, legal hold, deletion/anonymization, data subject export and backup deletion behavior.
- Reconcile dashboards with ledger/invoice/source tables and document known latency.
- Keep billing metrics separate from points and campaign finance.

**Acceptance:** sampled dashboard totals reconcile to source queries; tenant-boundary tests cover every report/export; data export/deletion is auditable and tested.

### P2 — Content, branding and integration marketplace

**Gap:** full tenant CMS and integration lifecycle are not verified.

**Implementation**
- Add versioned tenant branding and public storefront content with draft/preview/publish/rollback.
- Add integration registry with scope, credential lifecycle, health state, webhook endpoint configuration, last-success/last-error and revocation.
- Store credentials only in approved server-side secret storage; redact all diagnostics.
- Add cache invalidation/version compatibility and tenant-specific locale/timezone defaults.

**Acceptance:** publish/rollback and cache invalidation are verified; revoked credentials stop working; tenant content and integration state cannot leak across tenants.

## 5. Recommended dependency-ordered delivery plan

| Phase | Main deliverables | Exit gate |
|---|---|---|
| 0. Inventory & freeze | Confirm main/open PRs, canonical repo/deployment, source inventory, access and ownership; keep live billing disabled | Every production component has an identified source/version; no unknown target |
| 1. Release safety | Schema parity, migration history review, backup/restore plan, protected release workflow, Auth and legacy caller audit | Approved read-only diff/history plan; auth checklist; route retirement plan |
| 2. Controlled backend release | Apply reviewed migrations in order; deploy matching API only when compatible; record release manifest | Live schema/RPC/function versions and smoke checks match manifest |
| 3. Core financial correctness | Claim/redeem/ledger/budget E2E, fault injection, concurrency, QR traceability, reconciliation | No duplicate financial effects; transaction and isolation tests pass |
| 4. Tenant control plane | Membership/role model, tenant provisioning/lifecycle, settings, capability-driven admin shell | Cross-tenant deny tests pass; tenant can be onboarded without code edits |
| 5. Admin completion | Partner/product/campaign/reward/QR/redemption/ledger/audit/fraud/reports/health modules | Every shipped tab has server authorization, audit, error states and tests |
| 6. SaaS billing foundation | Plan versions, subscription model, entitlements, usage meter, billing RLS/RPC | Historical invoice immutability and plan-limit enforcement tests pass |
| 7. Test-mode payments | Checkout adapter, durable webhook inbox, deduplication, reconciliation, invoice/refund flows | Duplicate/out-of-order/wrong-amount/failure/refund tests pass |
| 8. Operations & experience | Fulfilment, settlement, support, alerts, backup/restore, mobile/i18n/accessibility/load tests | Operational drills and critical E2E pass |
| 9. Controlled pilot | Finance/security sign-off, staged rollout, alert coverage, rollback rehearsal | Written go/no-go; bounded cohort; clear rollback owner |
| 10. Scale & optimize | Usage-driven query/index tuning, analytics, advanced integrations and risk scoring | Production evidence supports expansion; no speculative features before controls |

## 6. Definition of done for every ticket

Each implementation ticket must include:
- Unique requirement ID, severity, owner and dependencies.
- Business outcome, scope and explicit non-goals.
- UI routes/components, API/Edge Function actions, tables/RPCs/migrations and external dependencies.
- Authentication, role, tenant and entitlement rules.
- Unit/contract/integration/concurrency/negative tests, plus migration forward/rollback considerations.
- Mobile, accessibility, localization, loading/empty/error/retry behavior.
- Logging, metrics, alerts, audit and data-retention considerations.
- CI evidence, staging acceptance, release SHA, live verification and rollback evidence.
- Status that reflects evidence; no status jumps directly from code merged to production verified.

## 7. Release-blocking checklist

- [ ] Canonical source repository and relationship to any secondary repo documented.
- [ ] Current `main`, open PRs and workflow runs reviewed before release.
- [ ] Production schema compared read-only with baseline; migration history reconciliation reviewed.
- [ ] Backup/restore path and protected approval confirmed.
- [ ] Pending migrations applied only via approved workflow and verified live.
- [ ] Frontend SHA, Vercel deployment ID, API version and DB migration set aligned.
- [ ] Auth email confirmation/recovery, leaked-password protection and privileged MFA verified.
- [ ] Legacy callers inventoried; no endpoint retired without evidence and rollback.
- [ ] Claim/redeem/budget/ledger concurrency and fault-recovery tests pass.
- [ ] All admin modules have server-side role/tenant checks and audited sensitive operations.
- [ ] SaaS plan, entitlement, usage and billing schema/RLS are tested.
- [ ] Test-mode payment checkout, webhook signature, event deduplication, out-of-order handling and reconciliation pass.
- [ ] Invoice/tax/refund policy reviewed by finance/accounting.
- [ ] Fulfilment, settlement, fraud, support and data export/deletion exceptions have runbooks.
- [ ] Monitoring/alerting, restore drill, mobile/browser E2E, accessibility and load tests pass.
- [ ] Pilot go/no-go and rollback owner are recorded.

## 8. Explicitly out of scope until prerequisites pass

- Live subscription payments or unrestricted public rewards campaigns.
- AI fraud scoring that autonomously suspends users or moves money.
- Automated production schema changes without review.
- Deactivation of legacy endpoints without caller/traffic evidence.
- Paid provider upgrades or build-quota workarounds without explicit approval.
- Claiming full completion based solely on repository code, a green CI run or a READY deployment.

## 9. External payment integration reference

Razorpay's documentation says webhook signatures use HMAC-SHA256 over the **raw request body**, that duplicate events should be deduplicated by the event ID, and that events may arrive out of order. Implement and test those requirements before enabling billing: [Validate and test webhooks](https://github.com/razorpay/markdown-docs/blob/master/webhooks/validate-test.md), [subscription webhooks](https://github.com/razorpay/markdown-docs/blob/master/payments/subscriptions/subscribe-to-webhooks.md). Provider documentation informs implementation; it does not prove this repository or its production deployment is integrated.

## 10. Immediate next actions

1. Check current main, open PRs and CI again; avoid overlapping or duplicating existing PR work.
2. Resolve PR #87 signature verifier review/CI and keep it clearly scoped as a security primitive.
3. Review the exact pending migration list, live schema diff, backup/recovery evidence and required production approvals; do not mutate production until all are satisfied.
4. Implement the subscription domain model as reviewed migrations with constraints, RLS, internal RPCs and isolated PostgreSQL tests.
5. Implement the durable webhook inbox and idempotent processor, then test-mode checkout and reconciliation.
6. Only then implement billing UI and platform billing console, with server-enforced entitlements and quota limits.
7. Re-check production deployment quota and release alignment after database/API readiness; deploy once, verify exact SHA and run end-to-end smoke tests.

**Final status:** This is a comprehensive roadmap, not a claim that all gaps have been fixed. Production remains gated until the database, Auth, backend, frontend, billing, operations and recovery acceptance evidence all agree.
