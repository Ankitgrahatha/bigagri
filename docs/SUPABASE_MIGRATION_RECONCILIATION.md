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

## Stronger catalog fingerprint gate (2026-10-22)

A read-only query captured deterministic SHA-256 fingerprints from the live project for these schema categories:

| Category | Objects | Live fingerprint |
|---|---:|---|
| Public columns | 170 | `557cf04098d8519f16d8cc1a9d145088734cb6ef9cefce7bf3dcc467098719a2` |
| Public constraints | 92 | `33c1dc63ba89a52e68e4d54ea54e2ee971269dfcd3821b339fcdbc499e09ebf2` |
| Postgres default ACLs (global/public) | 3 | `22b6455fc66b7493530b32ae5b6c884685dcbbbe8e430d686e82c989a42949c4` |
| Public enum labels | 28 | `e42d1fab480c15e989b9c1ed6bb57176c1c2f3bf3440817df91e39bbe59a40a4` |
| Public/private functions (definition, identity args, security config and ACL) | 16 | `91eb2351ce145e8313d7b0db461200b916dd229dc7c367ff16f1fddd71bb484e` |
| Public indexes | 60 | `9d67f1e13fcaca28de634af6810f33d0b478806b62b6c49b69d4a2469a7e8a1d` |
| Public RLS policies | 14 | `55e32a204770348638ee3366e69ec6e77b590dfcaedd97a46e31cbe12e1b65dd` |
| Public/private RLS table flags | 15 | `ea231962c74cee2034e24221b023b7bcf79a01a0aa32550fc22eb6c413fd752a` |
| Public table ACLs | 15 | `7307bd5015e41b8209d48e8a309ee1c4c2b0a315a9c365b40d38244281b5ab84` |
| Public/private non-internal triggers | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

The isolated PostgreSQL workflow now applies the baseline and the 13 historical timestamp markers, runs `rewardloop_live_schema_parity.test.sql`, and only then applies later feature/security migrations. The fingerprint test compares counts and signatures for all categories above, including function bodies, policy expressions, index definitions, constraint definitions, table ACLs, and default ACLs.

This is a stricter gate than comparing object names and counts, but it is still a fingerprint of the listed catalog surfaces—not a physical backup or proof of runtime behavior. The workflow must pass before considering the baseline equivalent. Do not run history repair or push migrations solely because this file contains the expected hashes.

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
