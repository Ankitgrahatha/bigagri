# RewardLoop Implementation Status

Last reviewed: 2026-10-21
Status: **MVP foundation exists; production launch is not yet approved.**

## Current deployed components

- Production PWA: https://bigagri.vercel.app/
- Admin operations console: https://bigagri.vercel.app/admin.html
- Admin settings console: https://bigagri.vercel.app/admin-settings.html
- GitHub source: https://github.com/Ankitgrahatha/bigagri
- Supabase project ref: `guhhuqxrobhuumwrypnc`

## Implemented in repository / database

- Hindi-first/English-switchable responsive PWA shell.
- Supabase email/password auth and profile onboarding.
- Partner verification admin flow.
- Product and campaign management with explicit campaign lifecycle controls.
- Unique QR batch issuance, one-time token download and batch revocation.
- Server-side QR claim and redemption endpoints using database RPCs.
- Points ledger, scan events, claim records, redemption history and audit tables.
- Admin CSV exports and redemption resolution operations.
- Protected admin settings preference store and settings UI.

## Blockers and unverified areas

- Production Auth email delivery and account confirmation are not verified; current account's email confirmation was previously observed as pending.
- The settings console does not yet apply SMTP, Auth URL, signup policy or email templates to live Supabase Auth. Its test-email action is a placeholder.
- Full automated tests for RLS/tenant isolation, concurrent QR claims, duplicate retries, budget enforcement, redemption timeouts, stock restoration and ledger immutability have not been evidenced in the repository inspection.
- Current client/server configuration is bound to the `growta-rewardloop` tenant slug; customer self-service multi-tenant onboarding is not implemented.
- Reward provider integration, customer billing, usage metering, formal fraud case handling, backup/restore drill and production alerting remain unverified or incomplete.
- The account membership was previously added as super_admin, but membership does not prove that a successful admin login or end-to-end operation has been tested.

## Release decision

**Do not run an unrestricted public rewards campaign yet.** First configure and test production email, verify admin login, test core database RPCs and RLS, and demonstrate that a code can be claimed only once and redemption is financially consistent under retries and concurrent requests.

See [PRD traceability matrix](./REWARDLOOP_PRD_TRACEABILITY.md) for requirements, evidence and the ordered implementation backlog.
