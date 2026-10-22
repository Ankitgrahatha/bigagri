# Public tenant storefront routing

## URL contract

The farmer PWA keeps the existing storefront as the default:

- `https://bigagri.vercel.app/` → `growta-rewardloop`
- `https://bigagri.vercel.app/?tenant=<public-tenant-slug>` → an explicitly published tenant catalog

The slug is a public routing identifier only. It is not authorization. The browser checks that the tenant is active and `public_catalog_enabled=true`; the API independently validates the slug and checks the same opt-in before creating/updating a farmer profile. Catalog table RLS remains the data boundary. Claim ownership, balances, redemption eligibility, and admin authorization continue to be derived from database rows and verified identity, not the URL.

## Publishing requirements

- New tenants default to `public_catalog_enabled=false`; their catalog stays private until an authorized publishing workflow enables it.
- Tenant creation and public-catalog publishing are not implemented by this change.
- Before using query-string tenant links for confirmed signup or password recovery, configure and test the exact Supabase Auth redirect URLs for those links. Do not add a broad wildcard without a reviewed redirect policy.
- No production Edge Function has been deployed by this change. The deployed API must receive the matching source before tenant-specific profile creation works end to end.
