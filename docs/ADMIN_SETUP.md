# RewardLoop Admin Setup

## First administrator bootstrap

The Supabase project currently has no verified owner account and no tenant memberships. One unconfirmed Auth account exists; the admin console is intentionally closed until the accountable owner verifies their email and is explicitly granted a role.

1. Open the deployed farmer app and create an account with the owner/operator email you control.
2. Complete email verification if Supabase requests it.
3. In Supabase SQL Editor for project `guhhuqxrobhuumwrypnc`, locate that exact account and copy its UUID:
   ```sql
   select id, email from auth.users where lower(email) = lower('YOUR_OWNER_EMAIL');
   ```
4. Grant the minimum required tenant role. Replace `YOUR_AUTH_USER_UUID` with the exact UUID returned above:
   ```sql
   insert into public.tenant_memberships (tenant_id, user_id, role, status)
   select t.id, 'YOUR_AUTH_USER_UUID'::uuid, 'super_admin', 'active'
   from public.tenants t
   where t.slug = 'growta-rewardloop' and t.status = 'active'
     and not exists (
       select 1 from public.tenant_memberships m
       where m.tenant_id = t.id and m.user_id = 'YOUR_AUTH_USER_UUID'::uuid
     );
   ```
5. Open `/admin.html` on the deployed domain and sign in with that account.

Only grant `super_admin` to the accountable system owner. Give other operators the narrower `brand_admin` role where possible. Never publish this SQL with a real user's email/UUID or grant admin membership based on unverified self-reported details.

## Release gates

- The demo campaign is paused intentionally. Do not activate it for real claims.
- Create and approve a production campaign and replace the demo catalogue before issuing live QR tokens.
- QR token CSVs contain claim secrets. Transfer them securely to the approved print/packaging workflow and do not commit them to GitHub.
- Admin API calls require a valid Supabase session and active `brand_admin` or `super_admin` tenant membership. Privileged database functions also check membership before changing partner status or issuing/revoking codes.


## Redemption operations

The admin console lists redemption requests with partner and reward names. For requests in `reserved` or `approved` state:
- **Mark fulfilled** records fulfilment without refunding spent points.
- **Cancel & refund** requires a reason, changes the status to cancelled, refunds the points through the ledger, restores finite reward stock, and records an audit event.
- Resolution is transactional and row-locked; resolved requests cannot be processed a second time.


## Campaign operations

- Create new campaigns from the admin console; new campaigns are always created in `draft`.
- Configure the start/end dates and budget before activation.
- Activation is blocked if the campaign has not started, has expired, or the tenant has no active product.
- Pause/archive actions require a reason and are written to the audit log.
- Campaign transitions are executed through service-role-only RPC wrappers and re-check active admin membership server-side.
- A draft campaign does not accept QR claims. Do not activate a campaign for real packaging until the offer, budget, eligible products, QR batch and fulfilment process are approved.
