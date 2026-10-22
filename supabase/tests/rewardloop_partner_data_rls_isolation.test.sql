-- Prove partner-facing RLS only exposes the authenticated user's own records.
-- Synthetic rows are rolled back; run only in disposable PostgreSQL CI.
BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-4000-8000-00000000b101'),
  ('00000000-0000-4000-8000-00000000b102');

INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
VALUES
  ('00000000-0000-4000-8000-00000000b201','RLS Tenant A','rls-tenant-a','active','en-IN',false),
  ('00000000-0000-4000-8000-00000000b202','RLS Tenant B','rls-tenant-b','active','en-IN',false);

INSERT INTO public.partners(id,tenant_id,user_id,role,display_name,verification_status)
VALUES
  ('00000000-0000-4000-8000-00000000b301','00000000-0000-4000-8000-00000000b201','00000000-0000-4000-8000-00000000b101','farmer','RLS Partner A','verified'),
  ('00000000-0000-4000-8000-00000000b302','00000000-0000-4000-8000-00000000b202','00000000-0000-4000-8000-00000000b102','farmer','RLS Partner B','verified');

INSERT INTO public.rewards(id,tenant_id,slug,name,category,points_cost,stock_quantity,active,is_demo,sort_order,metadata)
VALUES
  ('00000000-0000-4000-8000-00000000b401','00000000-0000-4000-8000-00000000b201','rls-reward-a','RLS Reward A','general',10,5,true,true,1,'{}'::jsonb),
  ('00000000-0000-4000-8000-00000000b402','00000000-0000-4000-8000-00000000b202','rls-reward-b','RLS Reward B','general',10,5,true,true,1,'{}'::jsonb);

INSERT INTO public.points_ledger(tenant_id,partner_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id,metadata)
VALUES
  ('00000000-0000-4000-8000-00000000b201','00000000-0000-4000-8000-00000000b301','earn',25,'rls-ledger-a','test_seed','00000000-0000-4000-8000-00000000b101','{}'::jsonb),
  ('00000000-0000-4000-8000-00000000b202','00000000-0000-4000-8000-00000000b302','earn',75,'rls-ledger-b','test_seed','00000000-0000-4000-8000-00000000b102','{}'::jsonb);

INSERT INTO public.redemptions(id,tenant_id,partner_id,reward_id,points_cost,status,request_key)
VALUES
  ('00000000-0000-4000-8000-00000000b501','00000000-0000-4000-8000-00000000b201','00000000-0000-4000-8000-00000000b301','00000000-0000-4000-8000-00000000b401',10,'reserved','rls-redemption-a'),
  ('00000000-0000-4000-8000-00000000b502','00000000-0000-4000-8000-00000000b202','00000000-0000-4000-8000-00000000b302','00000000-0000-4000-8000-00000000b402',10,'reserved','rls-redemption-b');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000b101',true);

DO $user_a_isolation$
DECLARE
  v_partners integer;
  v_ledger integer;
  v_redemptions integer;
  v_partner_name text;
  v_points bigint;
BEGIN
  SELECT count(*), min(display_name) INTO v_partners,v_partner_name FROM public.partners;
  SELECT count(*), COALESCE(sum(points_delta),0) INTO v_ledger,v_points FROM public.points_ledger;
  SELECT count(*) INTO v_redemptions FROM public.redemptions;

  IF v_partners <> 1 OR v_partner_name <> 'RLS Partner A'
     OR v_ledger <> 1 OR v_points <> 25 OR v_redemptions <> 1 THEN
    RAISE EXCEPTION 'User A can see unexpected partner data: partners % (name %), ledger % (points %), redemptions %',
      v_partners,v_partner_name,v_ledger,v_points,v_redemptions;
  END IF;
END;
$user_a_isolation$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000b102',true);

DO $user_b_isolation$
DECLARE
  v_partners integer;
  v_ledger integer;
  v_redemptions integer;
  v_partner_name text;
  v_points bigint;
BEGIN
  SELECT count(*), min(display_name) INTO v_partners,v_partner_name FROM public.partners;
  SELECT count(*), COALESCE(sum(points_delta),0) INTO v_ledger,v_points FROM public.points_ledger;
  SELECT count(*) INTO v_redemptions FROM public.redemptions;

  IF v_partners <> 1 OR v_partner_name <> 'RLS Partner B'
     OR v_ledger <> 1 OR v_points <> 75 OR v_redemptions <> 1 THEN
    RAISE EXCEPTION 'User B can see unexpected partner data: partners % (name %), ledger % (points %), redemptions %',
      v_partners,v_partner_name,v_ledger,v_points,v_redemptions;
  END IF;
END;
$user_b_isolation$;

RESET ROLE;
ROLLBACK;
