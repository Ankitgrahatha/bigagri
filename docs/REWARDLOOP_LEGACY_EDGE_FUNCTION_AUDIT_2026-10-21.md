# RewardLoop Legacy Edge Function Audit

Audit date: 2026-10-21  
Environment: live Supabase Edge Function source inspection; no invocations or data mutations performed.  
Project ref: `guhhuqxrobhuumwrypnc`

## Executive summary

Six legacy functions are active with platform `verify_jwt=false` and wildcard `Access-Control-Allow-Origin: *`. All six inspected source files manually validate the bearer token using Supabase Auth `auth.getUser()`, and all create/use a service-role client. Therefore, `verify_jwt=false` alone does **not** establish that these endpoints are unauthenticated. It does mean the gateway does not reject invalid/missing JWTs before handler execution; the handler's own auth checks are a critical security boundary.

Wildcard CORS is not an authentication bypass by itself: non-browser callers can call endpoints regardless of CORS. It does allow any website origin to attempt browser-based requests, subject to browser credential/token availability and handler authorization. The preferred target is a consistent exact-origin allowlist for browser endpoints.

Do not disable these functions or change their JWT settings until callers are mapped, parity tests exist, and replacement routes are verified. A broad emergency change could break farmer onboarding, claims, redemption, or admin workflows.

## Live inventory

| Function | Version | Platform JWT verification | Manual Auth `getUser()` | Wildcard CORS | Privileged client |
|---|---:|---|---|---|---|
| `claim-qr` | 1 | Off | Present | Present | Service role |
| `onboard-farmer` | 2 | Off | Present | Present | Service role |
| `issue-qr-batch` | 1 | Off | Present | Present | Service role |
| `revoke-qr-batch` | 1 | Off | Present | Present | Service role |
| `redeem-reward` | 1 | Off | Present | Present | Service role |
| `verify-partner` | 1 | Off | Present | Present | Service role |

The primary `rewardloop-api` is active at version 9 with platform JWT verification enabled. `rewardloop-admin-settings` is active at version 1 with platform JWT verification enabled.

## Authorization boundary observations

- `claim-qr` passes the verified `user.id` to `rewardloop_claim_qr_internal`.
- `redeem-reward` passes the verified `user.id` to `rewardloop_redeem_internal`.
- `issue-qr-batch`, `revoke-qr-batch`, and `verify-partner` pass the verified caller ID and client-supplied tenant/resource IDs to internal RPCs.
- The six handlers use service-role clients, which bypass RLS. Authorization must therefore be enforced in the trusted handler and/or the privileged database function. The edge source inspection did not prove the full authorization semantics inside every RPC.
- `onboard-farmer` writes through a service-role client after authenticating the caller. Confirm that it only creates/updates the authenticated user's own profile and cannot accept a different user ID or tenant scope from request data.
- No direct edge-handler query to `tenant_memberships` or explicit admin-role check was detected in the six legacy sources. For privileged operations, verify that the internal RPCs enforce active membership, required role, tenant/resource relationship, and actor identity atomically. Do not rely on client-side controls.

## Priority remediation plan

### P0 — verify privileged RPC authorization

For `rewardloop_issue_qr_batch_internal`, `rewardloop_revoke_qr_batch_internal`, and `rewardloop_verify_partner_internal`, inspect their source/migration definitions and prove all of the following:
1. Actor ID is checked against the authenticated execution context or otherwise cannot be spoofed by a caller with direct EXECUTE access.
2. Actor has active membership in the specified tenant and the required admin role.
3. Every campaign, product, batch, and partner belongs to the same tenant.
4. State changes, audit entries, and idempotency are transactionally consistent.
5. Invalid/unauthorized requests produce no partial mutation.

Internal RPCs currently deny EXECUTE to `anon` and `authenticated` and allow `service_role`; preserve that boundary.

### P1 — make CORS consistent

- Define the exact production browser origin list and apply it to browser-invoked legacy endpoints.
- Reject disallowed origins before business logic and return the correct CORS headers only for allowed origins.
- Preserve `OPTIONS` preflight behavior.
- Do not mistake CORS for authorization: retain server-side JWT validation and role/tenant checks.

### P1 — map and test every caller

- Search `app.js`, admin pages, QR scanning flows, and partner flows for every legacy function URL.
- For each caller, record required request fields, expected response schema, authentication mode, and production origin.
- Add contract tests for valid caller, missing/invalid JWT, wrong role, wrong tenant, malformed JSON, replay, and denied origin.
- Compare legacy behavior with `rewardloop-api` before migrating any client.

### P2 — consolidate routes safely

Prefer the canonical `rewardloop-api` for browser workflows after caller parity is verified. Retire legacy functions one at a time only after traffic is absent or migrated, tests pass, and rollback is available. Avoid simultaneous route/JWT/CORS changes.

## Release decision

**NO-GO for unrestricted real-value rewards remains unchanged.** This audit identifies a consistent hardening opportunity and authorization proof gaps; it does not demonstrate a confirmed exploit. No live function was changed, no real user/QR/points/reward data was mutated, and no production settings were altered.

## References

- Supabase Edge Function auth patterns: https://supabase.com/docs/guides/functions/auth
- Supabase Authorization headers and platform JWT behavior: https://supabase.com/docs/guides/functions/auth-headers
- Supabase CORS guidance: https://supabase.com/docs/guides/functions/cors
