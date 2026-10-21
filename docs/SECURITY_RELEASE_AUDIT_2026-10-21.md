# RewardLoop Security and Release Audit — 2026-10-21

## Scope and evidence

Reviewed the current `main` branch Edge Function, three operational migrations available in the repository, live Supabase migration history, live RLS policies/function grants, Supabase security/performance advisors, and recent Vercel deployments. This is a static/configuration audit, not an end-to-end penetration test.

## Verified deployment status

- Vercel production deployments for the two PRD/status-document commits are both `READY`.
- Supabase reports the RewardLoop foundation, QR/claim, catalog/redemption, operational access, demo protections, QR indexes, admin verification, redemption operations, campaign operations, demo-campaign activation protection, and admin-settings migrations as applied.
- The current Edge Function validates the caller's JWT with Supabase Auth and does not accept a client-supplied user ID for claim/redeem. Privileged mutations go through server-side RPCs.
- Live database grants show the `rewardloop_*_internal` RPC wrappers checked here are executable by `service_role`, and not by `anon` or `authenticated`. Continue to keep the service-role key server-side only.

## Findings

### SEC-001 — Leaked-password protection disabled (WARN)

Supabase Security Advisor reports Auth leaked-password protection is disabled. Enable it in Auth password security settings before inviting real users. This reduces use of known compromised passwords.

Reference: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

### SEC-002 — Admin settings table has no RLS policies (INFO; validate intended access)

Advisor reports `public.rewardloop_admin_settings` has RLS enabled but no policies. This is safe only if client roles are intentionally denied direct table access and the application uses a tightly scoped server-side service-role function. Confirm grants and test anonymous/authenticated direct reads/writes are denied. Do not add broad policies just to silence the advisor.

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

### AUTH-001 — Email confirmation and delivery remain a launch blocker

Earlier auth observations showed rate limiting, unconfirmed email, and invalid/expired confirmation-link symptoms. A super-admin membership alone does not prove the account can sign in. Configure a production SMTP provider, verify sender-domain SPF/DKIM (and DMARC where appropriate), and run a clean signup → email confirmation → login → admin authorization test. The admin settings screen currently does not apply live Supabase Auth SMTP configuration.

References:
- https://supabase.com/docs/guides/auth/auth-smtp
- https://supabase.com/docs/guides/auth/rate-limits
- https://supabase.com/docs/guides/deployment/going-into-prod

### QA-001 — Core reward flows need automated integration tests

No evidence of an automated test suite was found during this review. Before a real-value campaign, test at minimum:

1. Valid QR claim grants exactly one ledger credit.
2. Repeated claim with same request ID is idempotent; replay with a different request ID does not grant a second credit.
3. Two concurrent claims for the same QR result in one winner.
4. Invalid, revoked, expired, wrong-tenant, or role-mismatched QR entitlement is rejected without ledger mutation.
5. Redemption atomically checks balance, reserves points, and decrements stock; insufficient balance/stock leaves no partial writes.
6. Duplicate redemption request key does not reserve points twice.
7. Cancellation/rejection refunds exactly once and restores stock exactly once; fulfilling a redemption does not refund.
8. Tenant A's admin cannot read or mutate tenant B's records through any action or RPC.
9. Anonymous/authenticated users cannot directly mutate QR codes, claims, points ledger, redemptions, or admin settings.
10. Demo campaigns and demo rewards cannot be activated/redeemed in UI *or* server-side RPCs.

Run these in a disposable Supabase project or isolated test tenant with rollback/cleanup. Do not use real users, production QR codes, or real reward balances for concurrency tests.

### ARCH-001 — Single tenant slug is currently hardcoded

The Edge Function uses `TENANT_SLUG = "growta-rewardloop"`. That is acceptable for a tightly scoped single-tenant pilot, but it is not yet a complete multi-tenant SaaS control plane. Before onboarding multiple brands, derive tenant scope from verified membership/tenant routing and enforce tenant scope in every operation; never trust an arbitrary tenant ID supplied by the browser.

### OPS-001 — Public launch not approved

Do not enable an unrestricted campaign with real-value rewards until auth delivery, the above automated tests, recovery/restore readiness, operational alerts, reward budget enforcement, and fulfilment reconciliation have evidence of passing.

## Next implementation sequence

1. Add automated tests for RPC contracts and tenant isolation in an isolated test environment.
2. Verify database grants and RLS for every sensitive table, including `rewardloop_admin_settings`.
3. Complete the production auth/email path and test end-to-end.
4. Test campaign budget enforcement and atomic claim/redemption concurrency.
5. Add pilot runbook, reconciliation and incident-response procedures.
6. Only then open a controlled pilot.

## Important limitation

The findings above are based on observed database metadata, advisor output and source inspection. They do not claim that concurrent claims/redemptions, real email delivery, or complete user journeys have already passed.
