-- Local-development seed only. Supabase applies this after migrations on local start/reset.
-- No production users, QR secrets, claims, points ledger entries, or redemption rows are seeded.

INSERT INTO public.tenants(id, name, slug, status, default_locale, public_catalog_enabled)
VALUES (
  'd0000000-0000-4000-8000-000000000001',
  'Growta RewardLoop Demo',
  'growta-rewardloop',
  'active',
  'hi-IN',
  true
)
ON CONFLICT (slug) DO UPDATE
  SET status = 'active',
      default_locale = 'hi-IN',
      public_catalog_enabled = true,
      updated_at = now();

INSERT INTO public.rewardloop_admin_settings(tenant_id)
SELECT id FROM public.tenants WHERE slug = 'growta-rewardloop'
ON CONFLICT (tenant_id) DO NOTHING;

INSERT INTO public.products(
  id, tenant_id, sku, name, pack_size, active, metadata
)
SELECT
  'd0000000-0000-4000-8000-000000000002',
  t.id,
  'DEMO-VEG-SEED-001',
  'Hybrid Vegetable Seed (Demo)',
  'Demo pack',
  true,
  jsonb_build_object('demo', true, 'seed_source', 'local-seed')
FROM public.tenants t
WHERE t.slug = 'growta-rewardloop'
ON CONFLICT (tenant_id, sku) DO UPDATE
  SET name = EXCLUDED.name,
      pack_size = EXCLUDED.pack_size,
      active = true,
      metadata = EXCLUDED.metadata;

INSERT INTO public.campaigns(
  id, tenant_id, name, status, starts_at, ends_at,
  budget_minor_units, currency, rules_version, rules
)
SELECT
  'd0000000-0000-4000-8000-000000000003',
  t.id,
  'Local Demo Campaign (Paused)',
  'paused',
  now(),
  now() + interval '30 days',
  0,
  'INR',
  1,
  jsonb_build_object('demo', true, 'note', 'Paused local sample; no real QR claims')
FROM public.tenants t
WHERE t.slug = 'growta-rewardloop'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.rewards(
  id, tenant_id, slug, name, name_hi, description, description_hi,
  category, points_cost, stock_quantity, active, is_demo, sort_order, metadata
)
SELECT
  v.id, t.id, v.slug, v.name, v.name_hi, v.description, v.description_hi,
  'general', v.points_cost, 0, true, true, v.sort_order,
  jsonb_build_object('demo', true, 'seed_source', 'local-seed')
FROM public.tenants t
CROSS JOIN (VALUES
  ('d0000000-0000-4000-8000-000000000004'::uuid, 'seed-guide', 'Seed Growing Guide', 'बीज उगाने की मार्गदर्शिका', 'A sample digital reward for UI testing.', 'UI जाँच के लिए एक नमूना डिजिटल इनाम।', 100, 10),
  ('d0000000-0000-4000-8000-000000000005'::uuid, 'farm-supplies-demo', 'Farm Supplies Voucher (Demo)', 'कृषि सामग्री वाउचर (डेमो)', 'A non-redeemable demonstration reward.', 'एक गैर-रिडीम करने योग्य नमूना इनाम।', 250, 20)
) AS v(id, slug, name, name_hi, description, description_hi, points_cost, sort_order)
WHERE t.slug = 'growta-rewardloop'
ON CONFLICT (tenant_id, slug) DO UPDATE
  SET name = EXCLUDED.name,
      name_hi = EXCLUDED.name_hi,
      description = EXCLUDED.description,
      description_hi = EXCLUDED.description_hi,
      points_cost = EXCLUDED.points_cost,
      active = true,
      is_demo = true,
      sort_order = EXCLUDED.sort_order,
      metadata = EXCLUDED.metadata;
