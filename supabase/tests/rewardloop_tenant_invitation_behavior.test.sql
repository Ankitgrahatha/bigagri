-- Tenant admin invitation lifecycle regression. Runs only against disposable PostgreSQL in CI.
BEGIN;

DO $tenant_invitation_test$
DECLARE
  v_tenant_a constant uuid := '00000000-0000-4000-8000-00000000a101';
  v_tenant_b constant uuid := '00000000-0000-4000-8000-00000000a102';
  v_admin_a constant uuid := '00000000-0000-4000-8000-00000000a201';
  v_admin_b constant uuid := '00000000-0000-4000-8000-00000000a202';
  v_invitee constant uuid := '00000000-0000-4000-8000-00000000a203';
  v_wrong_email constant uuid := '00000000-0000-4000-8000-00000000a204';
  v_unconfirmed constant uuid := '00000000-0000-4000-8000-00000000a205';
  v_existing_admin constant uuid := '00000000-0000-4000-8000-00000000a206';
  v_suspended_member constant uuid := '00000000-0000-4000-8000-00000000a207';
  v_result jsonb;
  v_invitation_id uuid;
  v_count integer;
BEGIN
  INSERT INTO auth.users(id,email,email_confirmed_at)
  VALUES
    (v_admin_a,'admin-a@example.com',now()),
    (v_admin_b,'admin-b@example.com',now()),
    (v_invitee,'invitee@example.com',now()),
    (v_wrong_email,'wrong@example.com',now()),
    (v_unconfirmed,'unconfirmed-invite@example.com',NULL),
    (v_existing_admin,'existing-admin@example.com',now()),
    (v_suspended_member,'suspended-member@example.com',now());

  INSERT INTO public.tenants(id,name,slug,status,default_locale,public_catalog_enabled)
  VALUES
    (v_tenant_a,'Invitation Tenant A','invitation-tenant-a','active','en-IN',false),
    (v_tenant_b,'Invitation Tenant B','invitation-tenant-b','active','en-IN',false);

  INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
  VALUES
    (v_tenant_a,v_admin_a,'brand_admin','active'),
    (v_tenant_b,v_admin_b,'brand_admin','active'),
    (v_tenant_a,v_existing_admin,'brand_admin','active'),
    (v_tenant_a,v_suspended_member,'brand_admin','suspended');

  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_a,v_tenant_a,'invitee@example.com','brand_admin',repeat('a',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'true' OR v_result->'invitation'->>'status' <> 'pending' THEN
    RAISE EXCEPTION 'valid tenant invitation creation failed: %',v_result;
  END IF;
  v_invitation_id := (v_result->'invitation'->>'id')::uuid;

  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_a,v_tenant_a,'invitee@example.com','brand_admin',repeat('b',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'invitation_already_pending' THEN
    RAISE EXCEPTION 'duplicate pending invitation was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_b,v_tenant_a,'cross-tenant@example.com','brand_admin',repeat('c',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'cross-tenant admin created an invitation: %',v_result;
  END IF;

  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_a,v_tenant_a,'existing-admin@example.com','brand_admin',repeat('d',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'already_tenant_admin' THEN
    RAISE EXCEPTION 'invitation for an active tenant admin was not rejected: %',v_result;
  END IF;

  v_result := public.rewardloop_accept_tenant_invitation_internal(v_wrong_email,repeat('a',64));
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'invitation_email_mismatch' THEN
    RAISE EXCEPTION 'invitation was accepted by a different email owner: %',v_result;
  END IF;

  v_result := public.rewardloop_accept_tenant_invitation_internal(v_invitee,repeat('a',64));
  IF v_result->>'ok' <> 'true'
     OR v_result->>'role' <> 'brand_admin'
     OR v_result->>'tenant_slug' <> 'invitation-tenant-a' THEN
    RAISE EXCEPTION 'confirmed email owner could not accept invitation: %',v_result;
  END IF;

  SELECT count(*) INTO v_count FROM public.tenant_memberships
  WHERE tenant_id=v_tenant_a AND user_id=v_invitee AND role='brand_admin' AND status='active';
  IF v_count <> 1 THEN RAISE EXCEPTION 'acceptance did not create exactly one active tenant membership: %',v_count; END IF;

  v_result := public.rewardloop_accept_tenant_invitation_internal(v_invitee,repeat('a',64));
  IF v_result->>'ok' <> 'true' OR v_result->>'already_accepted' <> 'true'
     OR v_result->>'tenant_slug' <> 'invitation-tenant-a' THEN
    RAISE EXCEPTION 'same-account acceptance retry was not idempotent: %',v_result;
  END IF;

  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_a,v_tenant_a,'unconfirmed-invite@example.com','brand_admin',repeat('e',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'unconfirmed-user test invitation was not created: %',v_result; END IF;
  v_result := public.rewardloop_accept_tenant_invitation_internal(v_unconfirmed,repeat('e',64));
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'email_not_confirmed' THEN
    RAISE EXCEPTION 'unconfirmed email was permitted to accept an invitation: %',v_result;
  END IF;

  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_a,v_tenant_a,'revoke-me@example.com','brand_admin',repeat('f',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'revocation test invitation was not created: %',v_result; END IF;
  v_invitation_id := (v_result->'invitation'->>'id')::uuid;
  v_result := public.rewardloop_revoke_tenant_invitation_internal(v_admin_a,v_tenant_a,v_invitation_id,'Access no longer required');
  IF v_result->>'ok' <> 'true' OR v_result->>'status' <> 'revoked' THEN
    RAISE EXCEPTION 'pending invitation revocation failed: %',v_result;
  END IF;
  v_result := public.rewardloop_accept_tenant_invitation_internal(v_wrong_email,repeat('f',64));
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'invalid_invitation' THEN
    RAISE EXCEPTION 'revoked token remained usable: %',v_result;
  END IF;

  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_a,v_tenant_a,'expired-replace@example.com','brand_admin',repeat('1',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'expiry test invitation was not created: %',v_result; END IF;
  v_invitation_id := (v_result->'invitation'->>'id')::uuid;
  UPDATE public.tenant_invitations SET expires_at=now()-interval '1 second' WHERE id=v_invitation_id;
  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_a,v_tenant_a,'expired-replace@example.com','brand_admin',repeat('2',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'true' OR v_result->'invitation'->>'status' <> 'pending' THEN
    RAISE EXCEPTION 'expired invitation could not be replaced: %',v_result;
  END IF;
  SELECT count(*) INTO v_count FROM public.tenant_invitations
  WHERE tenant_id=v_tenant_a AND email='expired-replace@example.com' AND status='revoked';
  IF v_count <> 1 THEN RAISE EXCEPTION 'expired invitation was not audited/revoked before replacement: %',v_count; END IF;

  v_result := public.rewardloop_create_tenant_invitation_internal(
    v_admin_a,v_tenant_a,'suspended-member@example.com','brand_admin',repeat('3',64),now()+interval '3 days'
  );
  IF v_result->>'ok' <> 'true' THEN RAISE EXCEPTION 'invitation for suspended membership recovery was not created: %',v_result; END IF;
  v_result := public.rewardloop_accept_tenant_invitation_internal(v_suspended_member,repeat('3',64));
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'membership_conflict' THEN
    RAISE EXCEPTION 'acceptance silently reactivated a suspended membership: %',v_result;
  END IF;

  SELECT count(*) INTO v_count FROM public.audit_logs
  WHERE tenant_id=v_tenant_a AND entity_type='tenant_invitation';
  IF v_count < 7 THEN RAISE EXCEPTION 'invitation lifecycle audit coverage is incomplete: %',v_count; END IF;

  IF has_table_privilege('anon','public.tenant_invitations','SELECT')
     OR has_table_privilege('authenticated','public.tenant_invitations','SELECT')
     OR has_table_privilege('authenticated','public.tenant_invitations','INSERT')
     OR has_function_privilege('anon','public.rewardloop_create_tenant_invitation_internal(uuid,uuid,text,text,text,timestamp with time zone)','EXECUTE')
     OR has_function_privilege('authenticated','public.rewardloop_accept_tenant_invitation_internal(uuid,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.rewardloop_create_tenant_invitation_internal(uuid,uuid,text,text,text,timestamp with time zone)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.rewardloop_accept_tenant_invitation_internal(uuid,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.rewardloop_revoke_tenant_invitation_internal(uuid,uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'tenant invitation storage or RPCs are not service-role only';
  END IF;

  RAISE NOTICE 'PASS: invitation creation, tenant isolation, confirmed-email acceptance, idempotency, expiry replacement, revocation, audit trail, and service-role-only privileges';
END
$tenant_invitation_test$;

ROLLBACK;

