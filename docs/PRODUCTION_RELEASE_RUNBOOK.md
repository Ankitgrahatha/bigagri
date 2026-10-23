# RewardLoop production release runbook

Last reviewed: 2026-10-23

## What the manual release does

The workflow `.github/workflows/rewardloop-production-release.yml` is manual only. It does not run on push.

1. Requires the operator to select `YES` for production release and separately attest that a fresh production schema comparison matches the checked-in baseline if history repair is needed. Before linking or mutating production, the workflow reads the live Supabase Auth config through the Management API and fails closed unless `password_hibp_enabled` is exactly `true`.
2. Requires the four RewardLoop CI workflows to have passed on the exact `main` commit being released.
3. Links to the fixed production Supabase project reference `guhhuqxrobhuumwrypnc`.
4. Checks the local migration set against a hardcoded allowlist.
5. If the remote history has only the 13 historical versions, requires `confirm_live_schema_matches_baseline=YES` before reconciling baseline history version `20261021083000`. This is history-only: it does **not** execute baseline SQL against the live schema. The input is an operator attestation; it is not an automated proof of live schema parity. The SQL fingerprint probe is also run in this path, and the workflow refuses to repair history if it does not return the expected baseline match.
6. Prints a dry-run migration plan, applies only the reviewed pending migration set, and verifies all repository versions are recorded remotely.
7. Deploys the reviewed RewardLoop and SaaS billing Edge Functions after database migrations complete: `rewardloop-api`, `rewardloop-admin-settings`, `razorpay-webhook`, `create-razorpay-subscription`, `reconcile-razorpay-subscription`, `saas-checkout-reconciliation`, `saas-billing-portal`, and `process-razorpay-webhooks`.
8. Runs read-only smoke tests for the Vercel app/admin/settings routes, CORS preflight, unauthenticated API denial, and malformed webhook rejection. It does not create products, issue QR codes, claim points, redeem rewards, or modify business data.

The Vercel Git integration is expected to deploy the frontend from `main`, but deployment must be verified independently; a GitHub merge is not proof of a successful Vercel deployment. Product management controls are capability-gated: they stay hidden on the older API and become visible only after the updated API advertises `capabilities.product_management=true`. The controlled release workflow does not deploy the Vercel frontend.

## Required GitHub configuration

Before dispatching:

- Add repository Actions secrets:
  - `SUPABASE_ACCESS_TOKEN`: a scoped Supabase personal access token with the minimum permissions needed to read Auth config (`auth_config_read`), query the database for the baseline fingerprint, link the project, repair migration history, push migrations, and deploy Edge Functions.
  - `SUPABASE_DB_PASSWORD`: the production database password.
- Configure the GitHub Actions environment named `production` with required reviewers and a deployment branch restriction to `main`.
- In Supabase Auth security settings, enable leaked-password protection before dispatching. The workflow independently verifies `password_hibp_enabled=true` through `GET /v1/projects/{ref}/config/auth`; it fails closed if the API call is unauthorized, malformed, or reports the setting disabled.
- Before selecting `confirm_live_schema_matches_baseline=YES`, perform and review a fresh live schema comparison using the authenticated Supabase CLI/SQL connection. The isolated CI baseline-parity test compares against the checked-in captured snapshot; it does not by itself query production during the release run.
- Confirm the production Vercel alias `https://bigagri.vercel.app` is assigned to the current reviewed main deployment.
- Confirm a current production backup or approved recovery point exists and the restore path has been reviewed.
- Confirm Razorpay secret values are test-mode credentials. The workflow checks secret **names**, not credential mode; the confirmation is an operator attestation.

Do not put secrets in repository files, workflow inputs, logs, PR comments, or chat.

## How to release

1. Open **GitHub → Actions → RewardLoop controlled production release**.
2. Select branch `main`.
3. Set `confirm_production_release` to `YES` only after reviewing the PRs, migration list, and current release status.
4. If the workflow needs to repair baseline history, set `confirm_live_schema_matches_baseline` to `YES` only after a fresh production schema comparison is reviewed. If you cannot prove parity, leave it `NO` and stop.
5. Run the workflow and approve the `production` environment deployment when the reviewer gate appears. The workflow independently checks leaked-password protection through the Management API before any production mutation.
6. If any preflight, dry-run, migration, deploy, or smoke step fails, stop and inspect logs. Do not manually insert/delete rows in `supabase_migrations.schema_migrations`, and never use `supabase db reset --linked` against production.
7. After success, inspect Supabase function/database logs for errors and confirm all eight deployed function versions.
8. Keep `REWARDLOOP_BILLING_MONITOR_ENABLED` unset/false until the test-mode billing lifecycle is proven. Only then configure the GitHub Actions secret `RAZORPAY_PROCESSOR_SECRET` to exactly match the Supabase Edge Function secret and enable the scheduler variable.
9. Run the billing test-mode evidence checklist in `docs/SAAS_BILLING_WEBHOOK_OPERATIONS.md` before approving any real payment flow. Do not treat successful deployment or read-only smoke tests as evidence of a successful subscription lifecycle.

## Failure and retry behavior

- Before baseline repair, the workflow accepts only the known 13 historical versions or the known historical set plus the baseline.
- If the baseline is already recorded, it skips the history-only repair.
- If a release partially applied migrations, a retry is allowed only if remote versions are a subset of the exact local allowlist; unknown versions stop the release.
- If the schema fingerprint CI or exact-commit CI checks are missing, the workflow stops before linking/mutating production.
- A migration failure halts before Edge Function deployment. The functions are not deployed unless all migrations are recorded successfully.

## Release boundary

The workflow must be manually dispatched with explicit confirmation and pass the GitHub environment reviewer gate. This runbook does not itself deploy anything, and the current production database remains unchanged until a release is approved and run.

## SaaS billing release boundary

The controlled release workflow verifies that required secret names exist but cannot prove that their values are test-mode credentials. The operator confirmation is an attestation. Never enable the workflow using live Razorpay credentials during initial verification.

The workflow's HTTP checks are intentionally read-only and shallow: they verify the app/admin routes respond, CORS preflight succeeds, unauthenticated admin access is denied, and a malformed webhook is rejected. They do **not** prove checkout, payment capture, subscription activation, webhook processing, tenant isolation under real sessions, or reconciliation.

Before enabling the scheduler or accepting real payments, require recorded test-mode evidence for checkout idempotency, provider webhook signature verification, duplicate/out-of-order event handling, amount/currency/plan mismatches, failed payment and entitlement denial, cancellation/completion terminality, queue recovery, and restore/reconciliation. Follow `docs/SAAS_BILLING_WEBHOOK_OPERATIONS.md`. The scheduler remains disabled until `REWARDLOOP_BILLING_MONITOR_ENABLED=true`; do not activate it merely because the release workflow completed.
