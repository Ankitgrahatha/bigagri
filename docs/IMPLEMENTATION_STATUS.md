# RewardLoop Implementation Status

Last reviewed: 2026-10-22
Status: **MVP foundation exists; production launch is not yet approved.**

## Current deployed components

- Production PWA: https://bigagri.vercel.app/
- Admin operations console: https://bigagri.vercel.app/admin.html
- Admin settings console: https://bigagri.vercel.app/admin-settings.html
- GitHub source: https://github.com/Ankitgrahatha/bigagri
- Supabase project ref: `guhhuqxrobhuumwrypnc`

## Verified engineering progress since the prior review

The following changes are merged in Git and covered by successful GitHub Actions runs on `main`. They are **not all deployed to the connected production Supabase project**.

- Claim idempotency and actor-scoped replay tests.
- Parallel PostgreSQL claim and redemption contention tests, including one-credit, one-reservation, balance serialization, and stock/accounting assertions.
- Points ledger immutability: update, delete and truncate are rejected in the disposable database.
- Least-privilege grants on reward-bearing tables and internal RPC execution.
- Public catalog opt-in by tenant, with private tenant records hidden from both `anon` and `authenticated` roles in isolated tests.
- Default privileges tightened for future objects and tested by creating new tables, sequences, and functions.
- Schema-only local baseline, timestamp markers, safe local seed, and clean PostgreSQL rebuild workflow.
- Redemption refund enum fix: cancellation/rejection compensation uses the existing `redeem_release` enum value; the isolated behavior test proves refund/stock restoration occurs once and fulfillment does not refund.
- The deployed admin settings function is now tracked in Git with tests for caller authentication, tenant admin authorization, field allowlisting and SMTP password non-persistence.
- Six legacy Edge Function sources are archived outside the canonical deployment folder; none has been disabled.

Current CI evidence on main:
- Latest legacy-route guard and quality gate passed on commit `d8e8342f3dabfb8737b7ef1db07081d033a95b6a`.
- The prior main run also passed isolated database regression and smoke tests on `a42ab0844dbf6ce27ae36620d09b32a72a04f0c0`.
- These results prove the tested repository/CI path only, not that pending SQL has been applied to production.

## Production blockers still open

1. **Production migration history is not yet reconciled.** Do not run the schema baseline against the live database. Compare live schema to the baseline, confirm the remote migration versions, then perform the documented history-only repair and review a linked dry-run before any production push.
2. **Refund fix and subsequent security migrations are pending deployment.** They are in Git and passed isolated tests; the live function/database still needs controlled release verification.
3. **Auth email delivery and leaked-password protection** remain unverified/disabled as noted below.
4. **Legacy Edge Functions remain active.** The latest 24-hour function-log query showed traffic to `rewardloop-api` but no logged requests to the six legacy routes. That is only a 24-hour observation window—not sufficient evidence to retire routes. Keep them active until client references and a longer observation window are checked.
5. **No browser-level end-to-end run** has yet proved signup → confirmation → profile → claim → balance → redemption → cancellation/fulfillment on the deployed production stack.
6. **Vercel deployment quota previously blocked new production deploys.** Verify current project/deployment status before claiming the latest Git commit is live.

## Implemented in repository / database

- Hindi-first/English-switchable responsive PWA shell.
- Supabase email/password auth and profile onboarding.
- Partner verification admin flow.
- Product and campaign management with explicit campaign lifecycle controls. A new isolated-tested migration adds explicit point valuation, an append-only campaign award-liability ledger, serialized budget checks and fail-closed activation rules; it remains pending production deployment until reviewed.
- Unique QR batch issuance, one-time token download and batch revocation.
- Server-side QR claim and redemption endpoints using database RPCs.
- Points ledger, scan events, claim records, redemption history and audit tables.
- Admin CSV exports and redemption resolution operations.
- Protected admin settings preference store and settings UI.

## Explicitly missing or unverified: SaaS plans, payments and billing

The existing implementation inspection does **not** establish a working SaaS monetization system. Treat all items below as backlog until code, database schema, tests and provider configuration demonstrate otherwise.

### Plan and entitlement management
- No verified plan catalogue with versioned monthly/yearly prices, trial rules, currency, tax treatment, feature entitlements and published/retired states.
- No verified tenant-to-subscription lifecycle or entitlement resolver enforcing plan limits server-side.
- No verified tenant usage metering, quota warnings, overage rules, add-ons, coupons, trials, grace periods or plan change proration policy.
- No verified customer billing portal for upgrade, downgrade, cancellation, renewal and payment-method changes.
- No verified super-admin workspace for plan creation, pricing history, tenant subscriptions, overrides or subscription audit.

### Payments and accounting
- No verified payment gateway integration for SaaS subscription checkout or one-time invoices.
- No verified signed payment-webhook endpoint with signature validation, event deduplication, replay safety and reconciliation.
- No verified durable records for payment attempts, invoices, refunds, credit notes, tax breakdowns, gateway fees or settlement reconciliation.
- No verified failed-payment retry/dunning workflow, renewal reminders, grace-period expiry or controlled suspension/reactivation.
- No verified GST invoice numbering, legal business details, HSN/SAC mapping, credit-note handling or accountant-ready exports. These need business/accountant review before production.
- No verified separation between Growta subscription revenue and RewardLoop's farmer points, reward inventory, campaign budgets, redemption liabilities or partner settlements.

### Required financial invariants
- A browser redirect or client-supplied success flag must never activate a paid plan. Only a server-verified gateway event or verified provider API response can confirm payment.
- Webhook processing must be idempotent, authenticated, durable and safe under retries/out-of-order delivery.
- A payment must map to one tenant, one invoice/order and one currency/amount; mismatches must be quarantined for reconciliation.
- Subscription state and entitlements must be changed transactionally and audited. Expiry/suspension must not delete tenant data or corrupt reward/points history.
- Points and redemption stock remain in the database's authoritative transaction path. Redis/cache values must never determine financial balances or permissions.
- Never store raw card credentials or gateway secrets in the browser, repository or logs.

### Recommended zero-cost-first implementation sequence
1. Finalize billing domain model and policies before collecting money: plans, immutable plan versions, subscriptions, invoices, payment attempts/events, refunds/credit notes, entitlements, usage counters and audit trail.
2. Add migrations, constraints, RLS and service-side authorization; derive tenant scope from authenticated membership rather than request-supplied tenant IDs.
3. Implement a gateway adapter in test mode first (Razorpay is a candidate for India; confirm account eligibility and fees before choosing). Keep gateway-specific IDs alongside internal IDs.
4. Implement webhook signature verification, durable event inbox, idempotency keys, replay protection and reconciliation job. Test duplicate and out-of-order events.
5. Build tenant billing pages and a Super Admin billing workspace; enforce quotas on the server and show usage, invoices, payment status and next renewal.
6. Add invoice/tax documents, payment-failure notifications, grace period, cancellation and recovery paths after policy and accountant review.
7. Run test-mode end-to-end tests, security review and rollback rehearsal before enabling live payments. Do not use live money or production business records as test fixtures.

Razorpay's documented subscription model supports plans, subscriptions, lifecycle operations and webhooks; it is a candidate provider, not an integration currently claimed to exist. See [Razorpay Subscriptions API](https://razorpay.com/docs/api/payments/subscriptions/create-plan/?preferred-country=IN) and [subscription webhooks overview](https://github.com/razorpay/markdown-docs/blob/master/payments/subscriptions/subscribe-to-webhooks.md).

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
