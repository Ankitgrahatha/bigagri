# RewardLoop PRD Traceability and Build Status

Last reviewed: 2026-10-21
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
| Tenant foundation | Supabase tenant and membership tables exist; tenant slug is `growta-rewardloop` | Partial; test cross-tenant isolation and all RLS policies before production |
| Partner onboarding | Partner profiles and admin verification actions exist | Implemented in code; full role/permission E2E still required |
| QR issuance | Admin UI issues batches and downloads raw tokens once; backend RPC is called by Edge Function | Implemented in code; printing workflow, token custody and concurrency/replay tests remain |
| QR claim | Authenticated Edge Function delegates to database RPC; request UUID supplied for idempotency | Implemented in code; verify atomic transaction, uniqueness, race tests, and event logging in live DB |
| Points ledger | `points_ledger` table exists and is documented append-only | Partial until constraints, RPC behavior, RLS and reversal tests are verified |
| Campaigns | Draft creation, date validation, explicit activation/pause/archive and demo campaign activation guard exist in code/migrations | Implemented in code; boundary tests and campaign budget enforcement still required |
| Rewards/redemptions | Catalogue and redemption UI/actions exist; cancellation/refund and finite-stock restoration are described in repo docs/code | Partial until concurrent redemption, retries, reconciliation and ledger invariants pass tests |
| Brand multi-tenancy | Tenant ID is present on core tables and server-side tenant selection is used | Partial; current app has a single configured tenant slug, so configurable tenant onboarding and cross-tenant tests are not complete |
| Admin settings | `admin-settings.html/js` and `rewardloop-admin-settings` function exist | Partial/blocked: preferences can be stored, but SMTP/Auth settings are not applied to Supabase Auth; test-email action is a placeholder |
| Analytics/fraud | Basic admin counters and CSV exports exist | Partial; risk case workflow, budget/liability analytics, campaign profitability and advanced fraud review not implemented/verified |
| Reward fulfilment integrations | No verified provider integration in the inspected repository | Not started / open dependency |
| Billing and SaaS plans | No verified subscription billing implementation in inspected repository | Not started |
| Monitoring/operations | Production notes exist; full alerting, backup/restore drill and incident playbooks not verified | Partial |
| Automated test suite / CI gates | No test suite or CI configuration was visible in the inspected root listing | Not verified; create before production launch |

## Requirement-to-implementation matrix

| ID | Requirement | Current state | Acceptance evidence required |
|---|---|---|---|
| TENANT-001 | Every brand's records are isolated by tenant | Partial | RLS policy inventory plus negative cross-tenant tests for read/insert/update/delete/export |
| AUTH-001 | Secure user onboarding and session handling | Partial | Confirm signup/login/reset/expired session flows with configured production email |
| PARTNER-001 | Participant role and verification state | Implemented in code | Tests for farmer/retailer/distributor roles, pending/rejected/suspended restrictions |
| QR-001 | Unique random code per eligible pack | Implemented in code | Entropy/token hash review; issuance audit; one-time download custody procedure |
| QR-002 | Atomic one-time claim | Implemented in code; not yet verified end-to-end | Parallel claim test proving one entitlement and one credit only |
| QR-003 | Revoke issued unclaimed code batch | Implemented in code | Test revoked codes fail; already-posted claims remain auditable |
| LEDGER-001 | Immutable points accounting | Partial | Database privilege review, append-only enforcement, compensating-entry tests |
| LEDGER-002 | Claim and point credit commit atomically | Required; verify database RPC | Injected-failure and concurrency tests proving no partial write |
| CAMPAIGN-001 | Versioned, dated eligibility and explicit activation | Partial | Rule versioning/immutability and start/end boundary tests |
| BUDGET-001 | Campaign reward liability stays within approved budget | Not verified | Atomic budget reservation and exhaustion tests; exact accounting definition |
| REDEEM-001 | Reserve points once and fulfil safely | Partial | Concurrent requests, provider timeout, idempotent retry, failure/release/reconciliation tests |
| ADMIN-001 | Brand admin can operate only authorized tenant | Partial | Positive and negative authorization tests; no client-supplied tenant ID as authority |
| EMAIL-001 | Confirmation and recovery emails deliver reliably | Blocked | Configured SMTP/provider, verified domain, deliverability tests, expired/used link tests |
| EMAIL-002 | Admin console can change live Auth email settings | Blocked | Server-only Management API integration, secure secret storage, validation and rollback tests |
| LOCALE-001 | Rural-friendly regional language UX | Partial | Hindi/English coverage review, error/empty/loading states, low-bandwidth Android testing |
| FRAUD-001 | Suspicious claims can be reviewed and resolved | Partial | Case workflow, reasoned decisions, audit history, false-positive handling |
| ANALYTICS-001 | Brand can measure engagement, redemption cost and suspicious activity | Partial | Defined metric formulas, tenant-scoped exports and reconciled sample reports |
| OPS-001 | Production release is reproducible and recoverable | Partial | CI checks, backup/restore drill, deployment rollback, monitoring and incident runbook |

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
