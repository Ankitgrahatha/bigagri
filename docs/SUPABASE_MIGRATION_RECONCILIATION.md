# Supabase migration reconciliation

Date: 2026-10-21

## What changed

- Added `supabase/config.toml` for the local Supabase CLI, targeting PostgreSQL 17 (verified against the connected project's `server_version_num=170011`).
- Added `20261021083000_rewardloop_schema_baseline.sql`, a schema-only snapshot derived from the deployed database catalog. It contains no production rows or user/QR/reward secrets.
- Preserved previous migration SQL under `supabase/migration-archive/legacy-unreconciled/` before removing it from the executable migration chain.
- Added no-op history markers for the 13 migration timestamps currently recorded by the connected project's `supabase_migrations.schema_migrations`. They intentionally contain no DDL: the baseline captures their combined schema state.
- Added a local-only `supabase/seed.sql` with one demo tenant, a paused demo campaign, a demo product, admin-settings defaults, and non-redeemable sample rewards. It creates no auth users, QR secrets, claims, points ledger entries, or redemptions.
- Added a later default-privilege migration that removes the observed broad grants for newly-created public tables/sequences/functions and removes PostgreSQL's default PUBLIC EXECUTE on future functions. Existing object grants remain reviewed explicitly.
- Changed isolated CI to bootstrap an empty disposable PostgreSQL database from the baseline, apply the migration folder in timestamp order, load the local seed twice to check idempotency, then run the behavioral, default-privilege, and concurrency tests.

## Critical deployment boundary

**Do not execute the baseline SQL on the existing production database.** Its DDL describes objects that already exist, so running it directly would create conflicts. The baseline is intended to reconstruct a new local/test database and to become the local source of truth.

Before any production migration is pushed:

1. Review a schema diff between the checked-in baseline and the connected production schema. The snapshot excludes data and is not a database backup.
2. Confirm that the 13 no-op marker timestamps match the remote migration history exactly.
3. Run `supabase migration list --linked` after authenticating/linking in a trusted environment.
4. If—and only if—the schema diff proves that the baseline matches the current remote schema, reconcile the baseline timestamp in history without executing its DDL:
   `supabase migration repair 20261021083000 --status applied --linked`
5. Run `supabase migration list --linked` again and inspect `supabase db push --linked --dry-run`. The only pending DDL should be the reviewed security migrations after `20261021170000`.
6. Back up production and execute the reviewed migrations using an explicit release workflow. Never run `supabase db reset --linked` against production.

A migration repair updates migration history only; it does not apply/revert SQL. Do not run the command from this PR automatically because it mutates remote migration history and must follow schema-diff review.

## Why the old files are archived

The repository's prior migration filenames did not match the actual list of 13 migration versions recorded by the live project. Replaying those SQL files after a current schema snapshot could re-run old DDL against already-existing objects. The archive preserves the original contents for auditing; the baseline plus timestamp markers creates a coherent reproducible local chain. Do not copy archived files back into `supabase/migrations` without first re-evaluating the migration plan.

## Local workflow

With Docker-compatible runtime and the Supabase CLI installed:

```bash
supabase start
supabase db reset
supabase test db
```

The committed seed is for local development only. Production `db push` does not automatically apply `seed.sql`; do not use `db reset --linked` on production.

## Validation limits

The GitHub isolated PostgreSQL job validates the SQL migration chain, seed idempotency, transactional claim/redemption behavior, append-only ledger enforcement, privilege boundaries, public-catalog isolation, and concurrency cases. The disposable runner includes a minimal `auth.users`/Auth-function shim, so this is not a replacement for a full local Supabase CLI reset or an end-to-end Auth email-flow test.


## Read-only schema parity evidence (2026-10-22)

A read-only comparison was performed against the connected production project after the baseline was added. Results:

- The live public schema has 15 tables; the baseline has the same 15 table names.
- Every live public table's column-name set matches the corresponding baseline table (15/15 compared; no missing or extra columns).
- The 14 live public RLS policy names match the baseline policy names.
- The live database and baseline both define 16 application functions across `public` and `private`; function names and identity argument types match. The optional default-argument syntax is represented in the baseline but is not part of PostgreSQL's identity-argument display.
- The live database reports 92 constraints: 28 checks, 37 foreign keys, 15 primary keys, and 12 unique constraints. The baseline contains the same constraint categories/counts.
- The live schema reports 60 indexes. The baseline has 33 explicit index definitions plus 27 primary/unique constraint indexes, matching that count.
- The live and baseline contain the same five application enum types. No non-internal triggers were found in the `public`/`private` schemas.

This materially strengthens confidence that the schema-only baseline describes the current live schema. It is **not a full normalized DDL diff**: exact constraint expressions, index definitions, policy expressions, function bodies, ownership, grants, extension versions, and default ACLs still require final review. The structural comparison does not authorize production migration repair or a migration push by itself.

The connected remote migration history still contains the original 13 historical versions and does not yet contain baseline version `20261021083000` or any later security migration. Do not apply the baseline DDL to production. The remaining release action is to use an authenticated Supabase CLI environment to verify `supabase migration list --linked`, perform history-only baseline repair only after the full schema diff and backup gate, then inspect `supabase db push --linked --dry-run` before executing any pending migration.
