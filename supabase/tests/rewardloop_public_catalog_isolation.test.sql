-- Verify tenant catalog opt-in is enforced for anon and authenticated readers.
-- This file uses synthetic rows and rolls all changes back. Run only in disposable CI DB.
BEGIN;

INSERT INTO public.tenants(id, name, slug, status, default_locale, public_catalog_enabled)
VALUES
  ('00000000-0000-4000-8000-000000009001', 'Public Catalog Test', 'test-public-catalog', 'active', 'en-IN', true),
  ('00000000-0000-4000-8000-000000009002', 'Private Catalog Test', 'test-private-catalog', 'active', 'en-IN', false);

INSERT INTO public.products(id, tenant_id, sku, name, active, metadata)
VALUES
  ('00000000-0000-4000-8000-000000009003', '00000000-0000-4000-8000-000000009001', 'PUBLIC-TEST-SKU', 'Public Test Product', true, '{}'::jsonb),
  ('00000000-0000-4000-8000-000000009004', '00000000-0000-4000-8000-000000009002', 'PRIVATE-TEST-SKU', 'Private Test Product', true, '{}'::jsonb);

INSERT INTO public.campaigns(
  id, tenant_id, name, status, starts_at, ends_at, budget_minor_units, currency, rules_version, rules
)
VALUES
  ('00000000-0000-4000-8000-000000009005', '00000000-0000-4000-8000-000000009001',
   'Public Test Campaign', 'active', now() - interval '1 hour', now() + interval '1 day', 1000, 'INR', 1, '{}'::jsonb),
  ('00000000-0000-4000-8000-000000009006', '00000000-0000-4000-8000-000000009002',
   'Private Test Campaign', 'active', now() - interval '1 hour', now() + interval '1 day', 1000, 'INR', 1, '{}'::jsonb);

INSERT INTO public.rewards(
  id, tenant_id, slug, name, category, points_cost, stock_quantity, active, is_demo, sort_order, metadata
)
VALUES
  ('00000000-0000-4000-8000-000000009007', '00000000-0000-4000-8000-000000009001',
   'public-test-reward', 'Public Test Reward', 'general', 10, 5, true, false, 1, '{}'::jsonb),
  ('00000000-0000-4000-8000-000000009008', '00000000-0000-4000-8000-000000009002',
   'private-test-reward', 'Private Test Reward', 'general', 10, 5, true, false, 1, '{}'::jsonb);

SET LOCAL ROLE anon;

DO $anon_catalog_test$
DECLARE
  v_public_tenants integer;
  v_private_tenants integer;
  v_public_products integer;
  v_private_products integer;
  v_public_campaigns integer;
  v_private_campaigns integer;
  v_public_rewards integer;
  v_private_rewards integer;
BEGIN
  SELECT count(*) INTO v_public_tenants FROM public.tenants WHERE id = '00000000-0000-4000-8000-000000009001';
  SELECT count(*) INTO v_private_tenants FROM public.tenants WHERE id = '00000000-0000-4000-8000-000000009002';
  SELECT count(*) INTO v_public_products FROM public.products WHERE id = '00000000-0000-4000-8000-000000009003';
  SELECT count(*) INTO v_private_products FROM public.products WHERE id = '00000000-0000-4000-8000-000000009004';
  SELECT count(*) INTO v_public_campaigns FROM public.campaigns WHERE id = '00000000-0000-4000-8000-000000009005';
  SELECT count(*) INTO v_private_campaigns FROM public.campaigns WHERE id = '00000000-0000-4000-8000-000000009006';
  SELECT count(*) INTO v_public_rewards FROM public.rewards WHERE id = '00000000-0000-4000-8000-000000009007';
  SELECT count(*) INTO v_private_rewards FROM public.rewards WHERE id = '00000000-0000-4000-8000-000000009008';
  IF v_public_tenants <> 1 OR v_private_tenants <> 0
     OR v_public_products <> 1 OR v_private_products <> 0
     OR v_public_campaigns <> 1 OR v_private_campaigns <> 0
     OR v_public_rewards <> 1 OR v_private_rewards <> 0 THEN
    RAISE EXCEPTION 'anon catalog isolation failed: tenants public/private %/%, products %/%, campaigns %/%, rewards %/%',
      v_public_tenants,v_private_tenants,v_public_products,v_private_products,
      v_public_campaigns,v_private_campaigns,v_public_rewards,v_private_rewards;
  END IF;
END;
$anon_catalog_test$;

RESET ROLE;
SET LOCAL ROLE authenticated;

DO $authenticated_catalog_test$
DECLARE
  v_private_products integer;
  v_private_campaigns integer;
  v_private_rewards integer;
BEGIN
  SELECT count(*) INTO v_private_products FROM public.products WHERE id = '00000000-0000-4000-8000-000000009004';
  SELECT count(*) INTO v_private_campaigns FROM public.campaigns WHERE id = '00000000-0000-4000-8000-000000009006';
  SELECT count(*) INTO v_private_rewards FROM public.rewards WHERE id = '00000000-0000-4000-8000-000000009008';
  IF v_private_products <> 0 OR v_private_campaigns <> 0 OR v_private_rewards <> 0 THEN
    RAISE EXCEPTION 'authenticated client can read a private tenant catalog: products %, campaigns %, rewards %',
      v_private_products,v_private_campaigns,v_private_rewards;
  END IF;
END;
$authenticated_catalog_test$;

RESET ROLE;
ROLLBACK;
