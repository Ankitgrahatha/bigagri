-- Prevent anonymous/authenticated clients from enumerating every tenant's active catalog.
-- Public catalog exposure is opt-in per tenant, not implied merely by the tenant being active.
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS public_catalog_enabled boolean NOT NULL DEFAULT false;

-- Preserve the existing Growta RewardLoop storefront only. New tenants remain private
-- until an authorized onboarding/publishing flow explicitly enables public catalog access.
UPDATE public.tenants
   SET public_catalog_enabled = true,
       updated_at = now()
 WHERE slug = 'growta-rewardloop'
   AND status = 'active'
   AND public_catalog_enabled = false;

DROP POLICY IF EXISTS "active tenants are discoverable" ON public.tenants;
CREATE POLICY "public catalog tenants are discoverable"
  ON public.tenants
  FOR SELECT
  TO anon, authenticated
  USING (status = 'active' AND public_catalog_enabled);

DROP POLICY IF EXISTS "active campaigns are readable" ON public.campaigns;
CREATE POLICY "active public catalog campaigns are readable"
  ON public.campaigns
  FOR SELECT
  TO anon, authenticated
  USING (
    status = 'active'
    AND (starts_at IS NULL OR starts_at <= now())
    AND (ends_at IS NULL OR ends_at > now())
    AND EXISTS (
      SELECT 1
        FROM public.tenants t
       WHERE t.id = campaigns.tenant_id
         AND t.status = 'active'
         AND t.public_catalog_enabled
    )
  );

DROP POLICY IF EXISTS "active products are readable" ON public.products;
CREATE POLICY "active public catalog products are readable"
  ON public.products
  FOR SELECT
  TO anon, authenticated
  USING (
    active
    AND EXISTS (
      SELECT 1
        FROM public.tenants t
       WHERE t.id = products.tenant_id
         AND t.status = 'active'
         AND t.public_catalog_enabled
    )
  );

DROP POLICY IF EXISTS "active rewards are readable" ON public.rewards;
CREATE POLICY "active public catalog rewards are readable"
  ON public.rewards
  FOR SELECT
  TO anon, authenticated
  USING (
    active
    AND EXISTS (
      SELECT 1
        FROM public.tenants t
       WHERE t.id = rewards.tenant_id
         AND t.status = 'active'
         AND t.public_catalog_enabled
    )
  );
