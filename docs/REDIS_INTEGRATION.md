# Optional Upstash Redis burst limiting

## Current verified state (2026-10-23)

- The Upstash `growta-rewardloop` Redis database is active in `ap-south-1`, on the free plan, with TLS enabled.
- A read-only `PING` returned `PONG`; `DBSIZE` returned `0`. No app key data was present at the time of the check.
- The measured 7-day stats showed no application traffic before the diagnostic ping. This confirms the resource existed but was not being used by RewardLoop at that time.
- Vercel project environment metadata returned no configured project environment variables. This does not prove whether Supabase Edge Function secrets are configured; the Edge Function is the runtime for this limiter.

## What this change adds

The shared `rewardloop-api` Edge Function can optionally use the Upstash REST API for atomic fixed-window per-actor burst limits. Keys include the tenant slug, action, and authenticated actor ID. Raw QR tokens, request payloads, emails, phone numbers, balances and reward stock are not stored in Redis.

The Redis check is defence in depth only. Existing database transaction controls, the invalid-QR attempt counter, idempotency constraints, tenant membership checks and ledger/stock invariants remain authoritative. When Redis is absent or unavailable, the function fails open to those existing controls; when Redis is working and an actor exceeds the configured limit, the API returns HTTP 429 with `Retry-After`.

Initial limits are deliberately conservative and must be validated against real usage before launch: profile 30/min, claim 30/min, redeem 15/min, admin dashboard 60/min, partner verification 30/min, QR issue/revoke 10/min, redemption resolution 30/min, campaign status 20/min, campaign creation 10/min, and admin audit/export 30/min or 10/min as coded.

## Activation gate

This code is not active in production until both server-side Supabase Edge Function secrets are configured:

- `UPSTASH_REDIS_REST_URL` — HTTPS REST endpoint for the existing database.
- `UPSTASH_REDIS_REST_TOKEN` — read/write token for that database, stored only as a Supabase secret.

Do not put these values in frontend JavaScript, the Git repository, chat, browser local storage or a public Vercel environment variable. The current Supabase connector does not expose a secret-management action, so setting these secrets requires the trusted Supabase CLI or Dashboard. After setting them, deploy the reviewed Edge Function, run the isolated/production read-only smoke checks, and verify a test actor receives 429 after the configured threshold. Do not create a new paid Redis resource.

## Limitations

- Fixed-window limits can allow a burst around a window boundary; use a sliding-window/token-bucket strategy only if observed traffic warrants the complexity.
- Fail-open behaviour preserves availability if Redis has an outage. Database correctness is still enforced, but the additional burst guard is temporarily unavailable.
- This is not a substitute for network/IP-level abuse controls or database-side transaction invariants.
- Redis must never be the source of truth for points, stock, campaign budgets, membership, roles, entitlements, or redemption status.
