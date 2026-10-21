# Growta RewardLoop

Mobile-first, Hindi-first rewards PWA for farmers and agricultural partners. This repository is the single source of truth for the RewardLoop app deployed through the Vercel project `bigagri`.

## Architecture

- **Frontend:** static PWA (HTML, CSS, JavaScript), deployed on Vercel without a build step.
- **Identity:** Supabase Auth email/password.
- **Data:** Supabase Postgres with row-level security; partner records, rewards catalogue, points ledger and redemption history.
- **Privileged actions:** Supabase Edge Function `rewardloop-api`, which verifies the user's JWT before processing profile changes, QR claims and redemption requests.
- **Locale:** Hindi by default, with English toggle and responsive mobile UI.

## Current MVP

- Sign-up and sign-in.
- Farmer profile onboarding; new profiles require team verification.
- Rewards catalogue, points balance and ledger history.
- QR token entry and camera scanning where the browser supports `BarcodeDetector`.
- Server-side, idempotent QR claims and redemption requests.
- Demo rewards are labelled and cannot be redeemed.

## Repository layout

- `index.html` — application shell.
- `styles.css` — responsive design system.
- `app.js` — UI, Supabase Auth and data integration.
- `manifest.webmanifest`, `sw.js` — PWA metadata and static shell caching.
- `supabase/functions/rewardloop-api/index.ts` — versioned Edge Function source.
- `docs/PRODUCTION_NOTES.md` — production configuration and release gates.

## Deployment

Vercel project: `bigagri`; repository: `Ankitgrahatha/bigagri`; production branch: `main`. The Vercel deployment history has confirmed successful production deployments from recent commits on `main`.

Vercel settings should use **Framework Preset: Other**, root directory `.`, no build command, and output directory `.`. Keep Git integration connected to this repository and branch.

## Supabase

- Project ref: `guhhuqxrobhuumwrypnc` (region `ap-south-1`).
- Tenant slug: `growta-rewardloop`.
- Browser config uses only the Supabase URL and publishable key.
- The Edge Function uses platform-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY` (or `SUPABASE_PUBLISHABLE_KEY`) and `SUPABASE_SERVICE_ROLE_KEY`. Never expose the service-role key in frontend code or GitHub.
- The function must keep JWT verification enabled; it also validates the current user before using privileged database operations.

## Launch checklist

- Configure and test production email confirmation and password recovery.
- Verify real partners through the approved admin workflow before allowing QR claims.
- Create an approved production campaign, then issue unique QR tokens through a trusted issuance workflow.
- Replace demo catalogue entries and define fulfilment, returns, support and fraud-review operations.
- Test duplicate scans, replay/idempotency, insufficient points, concurrent stock redemption, mobile camera permissions and RLS isolation.
- Keep the service-role key server-side and review Supabase security/performance advisors before launch.

This is an MVP foundation, not yet a public-ready rewards programme. Demo records are not real offers and must not be represented as redeemable.
