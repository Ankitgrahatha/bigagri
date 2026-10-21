# RewardLoop Repository of Record

Last reviewed: 2026-10-21

## Canonical project

**The active source of truth is `Ankitgrahatha/bigagri`, branch `main`.** RewardLoop application code, admin console, Supabase function source, migration artifacts, tests, and release notes belong here.

- Farmer PWA: https://bigagri.vercel.app/
- Admin console: https://bigagri.vercel.app/admin.html
- Admin settings: https://bigagri.vercel.app/admin-settings.html
- Repository: https://github.com/Ankitgrahatha/bigagri
- Vercel project: `bigagri`; production branch: `main`
- Supabase project: `guhhuqxrobhuumwrypnc`; region `ap-south-1`
- RewardLoop tenant slug: `growta-rewardloop`

## Repository separation

`Ankitgrahatha/growta-rewardloop` is a separate repository and is **not** the active development target. Do not copy changes between repositories, change the Vercel Git integration, or deploy from that repository as part of routine RewardLoop work. Any future consolidation must be a deliberate reviewed migration with a file-by-file diff and deployment rollback plan.

## Release discipline

1. Make changes in a feature branch in `bigagri`.
2. Run source/static checks and the safe CORS/auth smoke test.
3. Review changes and merge only after checks pass.
4. Verify the resulting Vercel production deployment points to the intended `bigagri` commit.
5. Keep real-value reward campaigns disabled until authentication delivery, role/tenant isolation, QR replay/concurrency, redemption atomicity, and recovery tests are evidenced.

## Evidence and limitations from this review

- Live Supabase schema contains the columns used by the current farmer UI for partner profile, reward catalogue, points ledger, and redemption history.
- Live RLS policies include own-profile reads, own-ledger reads, own-redemption reads, active-reward reads, and active-tenant discovery.
- `rewardloop-api` is active with JWT verification enabled. Its privileged operations use the server-side service-role client and internal RPCs.
- Live transactional claim/redeem concurrency tests have **not** been proven by this inspection.
- Network-level smoke checks from this execution environment could not resolve the production Vercel/Supabase hostnames. Do not report those HTTP checks as passed; run the existing GitHub Actions smoke workflow or execute `supabase/tests/rewardloop_cors_smoke_test.sh` from an environment with network access.
- Production authentication email delivery and account confirmation remain unverified. A deployment being READY is not proof of a complete farmer journey.

## Safety rules

- Never commit or expose Supabase service-role credentials.
- Never run mutating claim, redemption, QR issuance, campaign, or fulfilment tests against production.
- Do not create a paid Supabase branch or service without explicit cost approval.
- Do not apply guessed or reconstructed migrations to production. Recover and review canonical migration SQL first.
