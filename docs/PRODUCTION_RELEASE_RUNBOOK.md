# RewardLoop production release runbook

Last reviewed: 2026-10-22

## What the manual release does

The workflow `.github/workflows/rewardloop-production-release.yml` is manual only. It does not run on push.

1. Requires the operator to select `YES` for production release and confirm Supabase Auth leaked-password protection is enabled.
2. Requires the four RewardLoop CI workflows to have passed on the exact `main` commit being released.
3. Links to the fixed production Supabase project reference `guhhuqxrobhuumwrypnc`.
4. Checks the local migration set against a hardcoded allowlist.
5. Reconciles only baseline history version `20261021083000` after the catalog fingerprint workflow has passed. This is history-only: it does **not** execute baseline SQL against the live schema.
6. Prints a dry-run migration plan, applies only the reviewed pending migration set, and verifies all repository versions are recorded remotely.
7. Deploys the matching `rewardloop-api` Edge Function after database migrations complete.
8. Runs read-only smoke tests for the Vercel app/admin/settings routes, CORS preflight, and unauthenticated API denial. It does not create products, issue QR codes, claim points, redeem rewards, or modify business data.

The Vercel Git integration deploys the frontend from `main`. Product management controls are capability-gated: they stay hidden on the older API and become visible only after the updated API advertises `capabilities.product_management=true`.

## Required GitHub configuration

Before dispatching:

- Add repository Actions secrets:
  - `SUPABASE_ACCESS_TOKEN`: a scoped Supabase personal access token with the minimum permissions needed to link the project, repair migration history, push migrations, and deploy the Edge Function.
  - `SUPABASE_DB_PASSWORD`: the production database password.
- Configure the GitHub Actions environment named `production` with required reviewers and a deployment branch restriction to `main`.
- In Supabase Auth security settings, enable leaked-password protection. The workflow requires an explicit confirmation; that confirmation is an operator attestation, not an API-level verification.
- Confirm the production Vercel alias `https://bigagri.vercel.app` is assigned to the current reviewed main deployment.

Do not put secrets in repository files, workflow inputs, logs, PR comments, or chat.

## How to release

1. Open **GitHub → Actions → RewardLoop controlled production release**.
2. Select branch `main`.
3. Set `confirm_production_release` to `YES` only after reviewing the PRs, migration list, and current release status.
4. Set `auth_leaked_password_protection_enabled` to `YES` only after enabling the setting in Supabase Auth.
5. Run the workflow and approve the `production` environment deployment when the reviewer gate appears.
6. If any preflight, dry-run, migration, deploy, or smoke step fails, stop and inspect logs. Do not manually insert/delete rows in `supabase_migrations.schema_migrations`, and never use `supabase db reset --linked` against production.
7. After success, verify the admin product catalogue appears (the API capability flag is now present), test a new product only with an approved business test plan, and inspect Supabase function/database logs for errors.

## Failure and retry behavior

- Before baseline repair, the workflow accepts only the known 13 historical versions or the known historical set plus the baseline.
- If the baseline is already recorded, it skips the history-only repair.
- If a release partially applied migrations, a retry is allowed only if remote versions are a subset of the exact local allowlist; unknown versions stop the release.
- If the schema fingerprint CI or exact-commit CI checks are missing, the workflow stops before linking/mutating production.
- A migration failure halts before Edge Function deployment. The function is not deployed unless all migrations are recorded successfully.

## Release boundary

This runbook and workflow do not themselves deploy anything. The workflow must be manually dispatched with explicit confirmation and pass the GitHub environment reviewer gate. The current production database remains unchanged until that happens.
