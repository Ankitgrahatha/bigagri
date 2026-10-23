# RewardLoop PRD Traceability and Build Status

Last reviewed: 2026-10-23
Repository: `Ankitgrahatha/bigagri` (branch `main`)
Production app: `https://bigagri.vercel.app/`
Supabase project: `guhhuqxrobhuumwrypnc`
Tenant slug: `growta-rewardloop`

## Purpose and requirement hierarchy

This repository implements **Growta RewardLoop**, a multi-tenant agricultural loyalty, product-authentication, and incentive product. The RewardLoop business blueprint supplied by the product owner defines this product's scope. The broader Growta Master PRD governs shared engineering controls (phased implementation, explicit dependencies, security reviews, tests, auditability, and honest completion reporting). A separate inventory/distributor operations PRD exists in the user's document library; its stock-ledger and Kotlin field-app scope is not silently imported into RewardLoop. Any product-level conflict must be recorded as an open question before implementation.

## Evidence-backed current state

| Area | Observed evidence | Status |
|---|---|---|
| Web PWA shell | `index.html`, `app.js`, `styles.css`, `manifest.webmanifest`, `sw.js` exist; Hindi/English toggle and QR camera/manual entry are implemented in client code | Implemented in code; device/browser E2E not independently verified here |
| Authentication | Supabase Auth email/password; signup/profile flow present | Partial; production email delivery and successful user verification remain release blockers |
| Tenant foundation | Supabase tenant and membership tables exist; tenant slug is `growta-rewardloop`; public catalog is opt-in per tenant | Improved: isolated tests prove private tenant catalog rows are hidden from anon and authenticated; production migration deployment and all write/export isolation tests remain open |
| Partner onboarding | Partner profiles and admin verification actions exist | Implemented in code; full role/permission E2E still required |
| QR issuance | Admin UI issues batches and downloads raw tokens once; backend RPC is called by Edge Function | Implemented in code; printing workflow, token custody and concurrency/replay tests remain |
| QR claim | Authenticated Edge Function delegates to database RPC; request UUID supplied for idempotency | Implemented in code; verify atomic transaction, uniqueness, race tests, and event logging in live DB |
| Points ledger | Database trigger blocks UPDATE/DELETE/TRUNCATE in clean PostgreSQL CI; compensation uses ledger entries | Isolated behavior tests pass; production migration deployment and live reconciliation remain open |
| Campaigns | Draft creation, date validation, explicit activation/pause/archive and demo campaign activation guard exist in code/migrations | Implemented in code; boundary tests and campaign budget enforcement still required |
| Rewards/redemptions | Atomic reservation/replay tests; parallel redemption tests; cancellation refund uses valid redeem_release enum; cancellation/fulfillment accounting tested | Isolated tests pass for one-time refund/stock restoration and fulfilled redemption finality; production deployment and real provider reconciliation remain open |
| Brand multi-tenancy | Tenant ID is present on core tables and server-side tenant selection is used | Partial; current app has a single configured tenant slug, so configurable tenant onboarding and cross-tenant tests are not complete |
| Admin settings | `admin-settings.html/js` and `rewardloop-admin-settings` function exist | Partial/blocked: preferences only; SMTP/Auth settings are not applied to Supabase Auth. Test-email control is visibly disabled until the privileged integration exists |
| Analytics/fraud | Basic admin counters and CSV exports exist | Partial; risk case workflow, budget/liability analytics, campaign profitability and advanced fraud review not implemented/verified |
| Reward fulfilment integrations | No verified provider integration in the inspected repository | Not started / open dependency |
| Billing and SaaS plans | Versioned plans, tenant subscriptions, idempotent Razorpay checkout, signed webhook inbox/worker, reconciliation queue and billing portal exist in source with contract/SQL tests | Source implemented; production blocked: live project has only 13 historical migrations and does not list billing Edge Functions; test-mode lifecycle not verified |
| Monitoring/operations | Controlled release workflow, webhook health metrics, opt-in five-minute scheduler, aggregate alerts and incident runbook exist | Partial; scheduler remains disabled, production backup/restore drill and billing test-mode evidence remain open |
| Automated test suite / CI gates | GitHub Actions quality gate, smoke tests, legacy-route guard, and disposable PostgreSQL migration/transaction/concurrency suite | Implemented in repository; tests must pass on the final merged commit and do not prove production migrations have been applied |

## 2026-10-23 verified progress

The following items are now present in the repository and have passed isolated GitHub Actions checks; they are not a substitute for production release verification:

- Clean PostgreSQL rebuild from a schema-only baseline, timestamp markers, and idempotent local demo seed.
- Tenant opt-in for public catalog reads, with private-tenant isolation checks for both `anon` and `authenticated`.
- Least-privilege client grants on reward-bearing tables and explicit internal RPC grants.
- Default ACL hardening for newly-created tables, sequences, and functions.
- Append-only points ledger trigger and tests rejecting UPDATE, DELETE, and TRUNCATE.
- Parallel claim/redemption tests for same-key replay, QR contention, balance serialization, points totals, and stock accounting.
- Redemption cancellation/rejection compensation uses the deployed enum value `redeem_release`; isolated tests cover one-time refund, stock restoration, fulfillment finality, and rejection of a NULL resolution status.

Evidence links: [PR #24 migration rebuild](https://github.com/Ankitgrahatha/bigagri/pull/24), [PR #25 default ACLs](https://github.com/Ankitgrahatha/bigagri/pull/25), [PR #26 refund enum fix](https://github.com/Ankitgrahatha/bigagri/pull/26), [PR #42 null-status guard](https://github.com/Ankitgrahatha/bigagri/pull/42), and [isolated database CI](https://github.com/Ankitgrahatha/bigagri/actions/workflows/rewardloop-claim-replay-db.yml).

**Production boundary (read-only recheck on 2026-10-23):** Supabase still reports only the original 13 migration versions out of 41 repository migration files. The live project lists `rewardloop-api` v10 and `rewardloop-admin-settings` v2 plus six legacy functions; the new Razorpay/SaaS billing Edge Functions are absent. The security advisor reports leaked-password protection disabled and an informational RLS-enabled/no-policy finding on `public.rewardloop_admin_settings` (do not add permissive client policies; keep access behind the authenticated, tenant-authorized function). The performance advisor reports 25 unused indexes; do not drop them without representative workload evidence. A fresh read-only catalog fingerprint comparison previously matched the checked-in baseline, but it is not a backup and does not reconcile migration history. Never run baseline DDL against the live project.

### Additional verified work on 2026-10-23

- SaaS billing source includes versioned plan pricing, tenant subscription and payment-attempt tables, fail-closed entitlements, idempotent checkout, provider-verified checkout recovery, signed webhook receipt/deduplication, bounded processing, health metrics, and a read-only reconciliation queue. This is not live billing readiness: the corresponding production migrations and functions remain absent.
- Production release runbook now distinguishes shallow HTTP smoke tests from test-mode billing lifecycle proof and keeps the scheduler disabled until test-mode evidence exists.
- The scheduler safety contract now checks the opt-in flag, five-minute cadence, bounded batch size/runtime, health metric validation, alert thresholds, and secret/payload non-disclosure.
- Latest local main test suite on `a588595c0d0c798934b1188ce0987c803335902b`: 157 passed, 0 failed after PRs #102–#104 and #106. PR #106's quality gate, safe smoke, legacy-route guard, and isolated PostgreSQL regression workflows passed before merge. Browser JavaScript syntax checks and `git diff --check` passed.
- The production release workflow now verifies `password_hibp_enabled=true` through the Supabase Management API before linking/mutating production; it fails closed on disabled/unknown state or missing `auth_config_read` permission and does not print the Auth config response.
- Admin settings now explicitly labels Auth controls as preferences only, and the test-email button is disabled until a real privileged provider integration exists.
- Vercel deployment is still blocked by the reported daily deployment quota; the latest PR status remains a Vercel quota failure, not a passing deployment.

## Requirement-to-implementation matrix

| ID | Requirement | Current state | Acceptance evidence required |
|---|---|---|---|
| TENANT-001 | Every brand's records are isolated by tenant | Partial | RLS policy inventory plus negative cross-tenant tests for read/insert/update/delete/export |
| AUTH-001 | Secure user onboarding and session handling | Partial | Confirm signup/login/reset/expired session flows with configured production email |
| PARTNER-001 | Participant role and verification state | Implemented in code | Tests for farmer/retailer/distributor roles, pending/rejected/suspended restrictions |
| QR-001 | Unique random code per eligible pack | Implemented in code | Entropy/token hash review; issuance audit; one-time download custody procedure |
| QR-002 | Atomic one-time claim | Implemented in code; not yet verified end-to-end | Parallel claim test proving one entitlement and one credit only |
| QR-003 | Revoke issued unclaimed code batch | Implemented in code | Test revoked codes fail; already-posted claims remain auditable |
| LEDGER-001 | Immutable points accounting | Isolated CI verified | Database trigger blocks update/delete/truncate; compensating entries and redemption refund accounting pass disposable PostgreSQL tests; production deployment remains pending |
| LEDGER-002 | Claim and point credit commit atomically | Isolated concurrency coverage present | Parallel same-key and different-key claim tests verify one accepted credit; production migration deployment and live E2E remain pending |
| CAMPAIGN-001 | Versioned, dated eligibility and explicit activation | Partial | Rule versioning/immutability and start/end boundary tests |
| BUDGET-001 | Campaign reward liability stays within approved budget | Not verified | Atomic budget reservation and exhaustion tests; exact accounting definition |
| REDEEM-001 | Reserve points once and fulfil safely | Isolated CI verified for database reservation/refund/fulfillment | Concurrent idempotency, balance serialization, cancellation refund and stock restore tests pass; external provider timeout/reconciliation and production deployment remain open |
| ADMIN-001 | Brand admin can operate only authorized tenant | Partial | Positive and negative authorization tests; no client-supplied tenant ID as authority |
| EMAIL-001 | Confirmation and recovery emails deliver reliably | Blocked | Configured SMTP/provider, verified domain, deliverability tests, expired/used link tests |
| EMAIL-002 | Admin console can change live Auth email settings | Blocked | Server-only Management API integration, secure secret storage, validation and rollback tests |
| LOCALE-001 | Rural-friendly regional language UX | Partial | Hindi/English coverage review, error/empty/loading states, low-bandwidth Android testing |
| FRAUD-001 | Suspicious claims can be reviewed and resolved | Partial | Case workflow, reasoned decisions, audit history, false-positive handling |
| ANALYTICS-001 | Brand can measure engagement, redemption cost and suspicious activity | Partial | Defined metric formulas, tenant-scoped exports and reconciled sample reports |
| OPS-001 | Production release is reproducible and recoverable | Partial: clean PostgreSQL rebuild and CI gates implemented | Migration chain and seed rebuild are tested in CI; production history reconciliation, backup/restore drill, deployment rollback and monitoring remain open |

## Immediate build order

1. **Release safety:** confirm auth/email, verify admin login, test current migrations/RPCs/RLS and add automated tests for claims/redemptions.
2. **Requirement traceability:** keep this matrix current as each requirement is implemented and tested.
3. **Tenant-ready admin:** remove hard-coded tenant assumptions from business workflows; tenant must derive from verified membership and server-side authorization.
4. **Campaign and ledger correctness:** enforce rule versioning, budget reservations, atomic claims, redemption reservations, reversals and reconciliation.
5. **Pilot operations:** secure QR batch export, provider-neutral fulfilment interface, fraud cases, support/dispute workflow, reporting and monitoring.
6. **Commercial SaaS:** customer onboarding, subscription/billing, usage metering, branded tenant configuration and integration contracts.
7. **Advanced capabilities:** risk scoring and richer analytics only after deterministic controls and pilot data are trustworthy.

## Open questions / decisions required before relevant work

- OQ-001: Is this first release farmer-only, or must farmer, retailer and distributor incentives all launch together? The code supports all three entitlement roles, but commercial rules must be explicit.
- OQ-002: What is the authoritative proof for retailer/distributor incentives: pack QR, invoice, distributor-management-system feed, or an approved combination?
- OQ-003: What is the campaign budget model: points liability at a configured redemption value, reward acquisition cost, or both?
- OQ-004: Which reward provider(s) and fulfilment modes are approved for the first paid pilot?
- OQ-005: Which Indian languages are mandatory for the first pilot beyond Hindi and English?
- OQ-006: What customer-owned domain and email provider will be used for production authentication?
- OQ-007: Confirm that the separate inventory/distributor operations PRD is a future Growta module, not part of RewardLoop's initial standalone product.

## Definition of done for every feature

A feature is not marked complete merely because it renders or deploys. Require: linked requirement ID; committed migration/source; server-side authorization; tests for success, failure, duplicate/retry and unauthorized cases as applicable; loading/empty/error states; audit trail; updated documentation; deployment result; and known limitations. Do not activate real reward campaigns until claim, ledger, redemption, budget and recovery controls have passed their acceptance tests.
