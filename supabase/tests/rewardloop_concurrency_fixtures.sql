-- Test-only concurrency fixtures. Run only in the disposable PostgreSQL CI database.
-- Rows are intentionally retained until the job container is discarded.
INSERT INTO auth.users(id) VALUES
  ('00000000-0000-4000-8000-000000008002'),
  ('00000000-0000-4000-8000-000000008003');

INSERT INTO public.tenants(id, name, slug, status, default_locale)
VALUES (
  '00000000-0000-4000-8000-000000008001',
  'Concurrency Test Tenant', 'concurrency-test-tenant', 'active', 'en-IN'
);

INSERT INTO public.partners(id, tenant_id, user_id, role, display_name, verification_status)
VALUES
  ('00000000-0000-4000-8000-000000008004', '00000000-0000-4000-8000-000000008001',
   '00000000-0000-4000-8000-000000008002', 'farmer', 'Concurrency Actor A', 'verified'),
  ('00000000-0000-4000-8000-000000008005', '00000000-0000-4000-8000-000000008001',
   '00000000-0000-4000-8000-000000008003', 'farmer', 'Concurrency Actor B', 'verified');

INSERT INTO public.products(id, tenant_id, sku, name, active, metadata)
VALUES (
  '00000000-0000-4000-8000-000000008006',
  '00000000-0000-4000-8000-000000008001',
  'TEST-CONCURRENCY-001', 'Concurrency Test Product', true, '{}'::jsonb
);

INSERT INTO public.campaigns(
  id, tenant_id, name, status, starts_at, ends_at, budget_minor_units, currency, rules_version, rules
)
VALUES (
  '00000000-0000-4000-8000-000000008007',
  '00000000-0000-4000-8000-000000008001',
  'Concurrency Test Campaign', 'active',
  now() - interval '1 hour', now() + interval '1 day',
  0, 'INR', 1, '{}'::jsonb
);

INSERT INTO public.qr_codes(
  id, tenant_id, product_id, campaign_id, token_hash, status, entitlement_role, points_value, activated_at
)
VALUES
  (
    '00000000-0000-4000-8000-000000008008',
    '00000000-0000-4000-8000-000000008001',
    '00000000-0000-4000-8000-000000008006',
    '00000000-0000-4000-8000-000000008007',
    encode(extensions.digest(convert_to('growta-concurrency-token-claim-same', 'UTF8'), 'sha256'), 'hex'),
    'active', 'farmer', 10, now()
  ),
  (
    '00000000-0000-4000-8000-000000008009',
    '00000000-0000-4000-8000-000000008001',
    '00000000-0000-4000-8000-000000008006',
    '00000000-0000-4000-8000-000000008007',
    encode(extensions.digest(convert_to('growta-concurrency-token-claim-race', 'UTF8'), 'sha256'), 'hex'),
    'active', 'farmer', 10, now()
  );

INSERT INTO public.rewards(
  id, tenant_id, slug, name, category, points_cost, stock_quantity, active, is_demo, sort_order, metadata
)
VALUES (
  '00000000-0000-4000-8000-000000008010',
  '00000000-0000-4000-8000-000000008001',
  'concurrency-test-reward', 'Concurrency Test Reward',
  'general', 30, 4, true, false, 10, '{}'::jsonb
);

INSERT INTO public.points_ledger(
  tenant_id, partner_id, entry_type, points_delta, idempotency_key,
  reason_code, actor_user_id, metadata
)
VALUES
  (
    '00000000-0000-4000-8000-000000008001',
    '00000000-0000-4000-8000-000000008004',
    'earn', 100, 'concurrency-seed:actor-a',
    'test_seed', '00000000-0000-4000-8000-000000008002', '{}'::jsonb
  ),
  (
    '00000000-0000-4000-8000-000000008001',
    '00000000-0000-4000-8000-000000008005',
    'earn', 40, 'concurrency-seed:actor-b',
    'test_seed', '00000000-0000-4000-8000-000000008003', '{}'::jsonb
  );
