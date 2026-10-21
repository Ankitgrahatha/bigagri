# RewardLoop Route Consolidation and Retirement Plan

Date: 2026-10-21  
Scope: route inventory and safe migration planning only. No production routes are changed by this document.

## Current client-to-function map

| Client surface | Function called | Observed pattern | Notes |
|---|---|---|---|
| Main farmer/partner PWA (`app.js`) | `rewardloop-api` | Shared `api(action, payload)` wrapper uses `supabase.functions.invoke(API_FUNCTION, ...)`; `API_FUNCTION = "rewardloop-api"` | Main client path is the canonical API. |
| Admin settings UI (`admin-settings.js`) | `rewardloop-admin-settings` | Shared wrapper invokes the dedicated settings function | Separate protected settings surface; keep distinct until behavior and authorization are reviewed. |
| Legacy `claim-qr`, `onboard-farmer`, `issue-qr-batch`, `revoke-qr-batch`, `redeem-reward`, `verify-partner` | No direct `supabase.functions.invoke("legacy-name")` match found in the focused code searches performed for this audit | Legacy functions remain active in Supabase | This is not proof that no caller exists: dynamic URLs, QR links, older deployed clients, external integrations, and cached PWA bundles must also be checked. |

## Why not disable legacy routes immediately?

The legacy endpoints are live and have previously supported claims, onboarding, QR batch operations, redemption, and partner verification. Disabling them before measuring callers and proving parity could break active or older clients. Their handlers manually validate JWTs, but wildcard CORS remains a hardening issue and the service-role path requires reliable authorization in trusted code/database routines.

## Safe retirement gates

A legacy function may be retired only when every gate below is evidenced:

1. **Static inventory:** search all repository files for function slugs, function URLs, dynamic URL construction, and action-specific calls. Include QR generation/print templates and environment/config files.
2. **Client inventory:** check deployed PWA versions and service-worker cache behavior; identify any older installed clients that may still call the endpoint.
3. **Traffic evidence:** use Edge Function invocation logs/metrics over a meaningful observation window. If reliable per-function traffic metrics are unavailable, do not infer zero traffic from source search.
4. **Contract parity:** run old/new contract tests in an isolated environment for successful and denied requests, request validation, error shapes, idempotency, and tenant isolation.
5. **Authorization proof:** prove role, membership, tenant/resource relationships, and actor binding for every privileged RPC and handler. The service-role client bypasses RLS.
6. **Operational readiness:** document rollback, owner, change window, support impact, and a way to restore the prior route quickly.
7. **One-at-a-time change:** retire one route per change, verify application workflows and logs, then proceed to the next route.

## CORS hardening sequence

- Keep server-side token validation regardless of CORS.
- Establish the actual list of browser origins from the deployed PWA and supported preview/custom domains.
- Apply exact origin allowlisting to the legacy functions, with correct `OPTIONS` handling.
- Add tests for allowed origin, denied origin, missing Origin, preflight, missing bearer token, invalid token, and valid authenticated request.
- Deploy and verify one function at a time. Do not make a blanket change before confirming callers.

CORS is a browser-enforced cross-origin policy, not a substitute for authorization. Non-browser clients can call endpoints directly, so all authorization must remain server-side.

## Near-term implementation order

1. Add a static route inventory test to CI that flags newly introduced direct calls to legacy function names outside an explicit allowlist.
2. Add isolated contract tests for legacy endpoint auth/error behavior and compare them with `rewardloop-api`.
3. Inspect privileged RPC definitions and prove admin role + tenant/resource checks; do not rely on handler validation alone.
4. Review edge logs for legacy usage.
5. Harden CORS after the origin/caller inventory is complete.
6. Retire routes only after all gates pass.

## Release decision

**No production function was changed or disabled by this plan.** No test claims, point balances, rewards, redemptions, QR batches, or partner records were mutated. Real-value launch remains **NO-GO** until transaction and authorization evidence is complete.

## Relevant source locations

- `app.js` — main PWA API wrapper and action calls.
- `admin-settings.js` — dedicated settings API wrapper.
- `supabase/functions/rewardloop-api/index.ts` — canonical application API.
- `supabase/tests/rewardloop_client_api_contract.test.mjs` — API contract tests.
- `supabase/tests/rewardloop_security_contract.sql` — database privilege/RLS contract tests.
- `docs/REWARDLOOP_LEGACY_EDGE_FUNCTION_AUDIT_2026-10-21.md` — live legacy function audit.
