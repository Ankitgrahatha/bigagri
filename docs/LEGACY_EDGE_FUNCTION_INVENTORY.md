# Legacy RewardLoop Edge Function Inventory

Reviewed: 2026-10-22
Project: `guhhuqxrobhuumwrypnc`

These files are **archive-only copies** retrieved from the connected Supabase project's deployed source. They are intentionally stored under `supabase/functions-legacy/`, not `supabase/functions/`, so a routine Edge Function deployment does not pick them up as canonical functions.

| Legacy route | Deployed version | Verified source characteristics | Risk / next action |
|---|---:|---|---|
| `claim-qr` | 1 | Validates bearer JWT via Auth; invokes internal claim RPC; wildcard CORS | Check caller logs and client references; migrate/retire only after evidence of zero dependency |
| `onboard-farmer` | 2 | Validates JWT, but directly inserts partner profile with service role; wildcard CORS; writes `verification_status='unverified'` while canonical API uses `pending` | Highest priority for route consolidation because duplicate onboarding logic bypasses the canonical profile RPC/action and may drift from current constraints |
| `issue-qr-batch` | 1 | Validates JWT; invokes internal QR batch RPC; wildcard CORS | Check caller logs and client references before retirement |
| `revoke-qr-batch` | 1 | Validates JWT; invokes internal revoke RPC; wildcard CORS | Check caller logs and client references before retirement |
| `redeem-reward` | 1 | Validates JWT; invokes internal redemption RPC; wildcard CORS | Check caller logs and client references before retirement |
| `verify-partner` | 1 | Validates JWT; invokes internal partner verification RPC; wildcard CORS | Check caller logs and client references before retirement |

## Security observations

- All six legacy routes have Supabase `verify_jwt=false`; they manually call `auth.getUser()` on a bearer token. This is not the same as rejecting unauthenticated invocations at the platform gateway. Do not disable the manual validation or change gateway settings until the migration path is ready.
- All six return `Access-Control-Allow-Origin: *`. CORS is not authentication, but wildcard origins increase the browser attack surface when a caller has a valid token.
- `onboard-farmer` writes directly with the service-role client and is not routed through the canonical `rewardloop-api` profile action. Its profile state differs from the canonical implementation.
- The copies include a SHA-256 identifier reported by Supabase metadata. They are for audit and source control only; do not deploy from this archive folder.

## Safe retirement sequence

1. Search the entire repository for each legacy route name and inspect any client, mobile, external automation, or third-party caller.
2. Query Supabase Edge Function request logs for each route over a meaningful observation window and identify authenticated caller IDs only through approved privacy-safe logging.
3. If any route has traffic, migrate that caller to `rewardloop-api` and run acceptance tests.
4. Monitor after caller migration, then retire one route at a time with a rollback plan.
5. Verify the route is no longer invoked, then remove its live deployment. Do not retire routes based only on a short quiet log window.

## What this review does not claim

The inventory does not prove that the six routes are unused, nor does it prove all underlying RPCs are correct. No legacy route was disabled or redeployed during this audit.
