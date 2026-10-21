# RewardLoop production notes

- Tenant slug: `growta-rewardloop`
- Supabase project ref: `guhhuqxrobhuumwrypnc`
- Supabase region: `ap-south-1`
- Public client configuration is in `app.js` and uses the publishable key only.
- Edge function: `rewardloop-api`; verify JWT must remain enabled.
- Required server-only edge secrets are the platform-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY` (or `SUPABASE_PUBLISHABLE_KEY`), and `SUPABASE_SERVICE_ROLE_KEY`.
- Do not use the service-role key in any static frontend file.
- A profile created through the PWA is `pending` verification by default.
- Demo rewards/campaign remain non-production and must not be advertised as redeemable.
