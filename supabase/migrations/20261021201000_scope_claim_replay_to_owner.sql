-- A request UUID is not an authorization credential. Never return a claim result to
-- a different user just because they reuse/guess the original idempotency key.
CREATE OR REPLACE FUNCTION private.claim_qr(
  p_actor_user_id uuid,
  p_token text,
  p_request_id uuid,
  p_app_version text DEFAULT NULL::text,
  p_device_ref_hash text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
DECLARE
  v_qr public.qr_codes%rowtype;
  v_partner public.partners%rowtype;
  v_campaign public.campaigns%rowtype;
  v_claim_id uuid;
  v_existing public.claims%rowtype;
BEGIN
  IF p_actor_user_id IS NULL OR p_request_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'outcome','invalid_request','points_awarded',0);
  END IF;
  IF p_token IS NULL OR length(p_token)<16 OR length(p_token)>512 THEN
    RETURN jsonb_build_object('ok',false,'outcome','invalid_code','points_awarded',0);
  END IF;

  SELECT q.* INTO v_qr
    FROM public.qr_codes q
   WHERE q.token_hash=encode(digest(convert_to(p_token,'UTF8'),'sha256'),'hex')
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'outcome','invalid_code','points_awarded',0);
  END IF;

  SELECT q.* INTO v_qr FROM public.qr_codes q WHERE q.id=v_qr.id FOR UPDATE;

  -- Replay results are visible only to the owner of the partner credited by the claim.
  SELECT c.* INTO v_existing
    FROM public.claims c
    JOIN public.partners p
      ON p.id=c.partner_id
     AND p.tenant_id=c.tenant_id
   WHERE c.tenant_id=v_qr.tenant_id
     AND c.idempotency_key='claim:'||p_request_id::text
     AND p.user_id=p_actor_user_id
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok',v_existing.status='accepted',
      'outcome',CASE WHEN v_existing.status='accepted' THEN 'accepted' ELSE 'rejected' END,
      'claim_id',v_existing.id,
      'points_awarded',v_existing.points_awarded,
      'replayed',true
    );
  END IF;

  -- The key is already bound to another claim. Do not reveal its owner/result and
  -- do not proceed to a second insert that would collide with the tenant-wide unique key.
  IF EXISTS (
    SELECT 1 FROM public.claims c
     WHERE c.tenant_id=v_qr.tenant_id
       AND c.idempotency_key='claim:'||p_request_id::text
  ) THEN
    RETURN jsonb_build_object('ok',false,'outcome','request_id_conflict','points_awarded',0,'replayed',false);
  END IF;

  SELECT p.* INTO v_partner
    FROM public.partners p
   WHERE p.tenant_id=v_qr.tenant_id
     AND p.user_id=p_actor_user_id
     AND p.verification_status='verified'
     AND p.role=v_qr.entitlement_role
   LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    VALUES(v_qr.tenant_id,v_qr.id,p_actor_user_id,'ineligible',p_request_id,p_app_version,p_device_ref_hash)
    ON CONFLICT(tenant_id,request_id) DO NOTHING;
    RETURN jsonb_build_object('ok',false,'outcome','ineligible','points_awarded',0);
  END IF;

  IF v_qr.status='claimed' THEN
    INSERT INTO public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    VALUES(v_qr.tenant_id,v_qr.id,p_actor_user_id,'duplicate',p_request_id,p_app_version,p_device_ref_hash)
    ON CONFLICT(tenant_id,request_id) DO NOTHING;
    RETURN jsonb_build_object('ok',false,'outcome','already_claimed','points_awarded',0);
  ELSIF v_qr.status='revoked' THEN
    INSERT INTO public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    VALUES(v_qr.tenant_id,v_qr.id,p_actor_user_id,'revoked',p_request_id,p_app_version,p_device_ref_hash)
    ON CONFLICT(tenant_id,request_id) DO NOTHING;
    RETURN jsonb_build_object('ok',false,'outcome','revoked','points_awarded',0);
  ELSIF v_qr.status='expired' OR (v_qr.expires_at IS NOT NULL AND v_qr.expires_at<=now()) THEN
    INSERT INTO public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    VALUES(v_qr.tenant_id,v_qr.id,p_actor_user_id,'expired',p_request_id,p_app_version,p_device_ref_hash)
    ON CONFLICT(tenant_id,request_id) DO NOTHING;
    RETURN jsonb_build_object('ok',false,'outcome','expired','points_awarded',0);
  ELSIF v_qr.status<>'active' THEN
    INSERT INTO public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    VALUES(v_qr.tenant_id,v_qr.id,p_actor_user_id,'invalid',p_request_id,p_app_version,p_device_ref_hash)
    ON CONFLICT(tenant_id,request_id) DO NOTHING;
    RETURN jsonb_build_object('ok',false,'outcome','not_activated','points_awarded',0);
  END IF;

  IF v_qr.campaign_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'outcome','campaign_missing','points_awarded',0);
  END IF;

  SELECT c.* INTO v_campaign
    FROM public.campaigns c
   WHERE c.id=v_qr.campaign_id AND c.tenant_id=v_qr.tenant_id;
  IF NOT FOUND OR v_campaign.status<>'active'
     OR (v_campaign.starts_at IS NOT NULL AND v_campaign.starts_at>now())
     OR (v_campaign.ends_at IS NOT NULL AND v_campaign.ends_at<=now()) THEN
    INSERT INTO public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    VALUES(v_qr.tenant_id,v_qr.id,p_actor_user_id,'ineligible',p_request_id,p_app_version,p_device_ref_hash)
    ON CONFLICT(tenant_id,request_id) DO NOTHING;
    RETURN jsonb_build_object('ok',false,'outcome','campaign_inactive','points_awarded',0);
  END IF;

  IF v_qr.points_value<=0 THEN
    RETURN jsonb_build_object('ok',false,'outcome','no_reward_value','points_awarded',0);
  END IF;

  UPDATE public.qr_codes SET status='claimed',claimed_at=now()
   WHERE id=v_qr.id AND status='active';
  IF NOT FOUND THEN
    INSERT INTO public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
    VALUES(v_qr.tenant_id,v_qr.id,p_actor_user_id,'duplicate',p_request_id,p_app_version,p_device_ref_hash)
    ON CONFLICT(tenant_id,request_id) DO NOTHING;
    RETURN jsonb_build_object('ok',false,'outcome','already_claimed','points_awarded',0);
  END IF;

  INSERT INTO public.claims(tenant_id,qr_code_id,partner_id,campaign_id,status,points_awarded,rule_version,idempotency_key)
  VALUES(v_qr.tenant_id,v_qr.id,v_partner.id,v_qr.campaign_id,'accepted',v_qr.points_value,v_campaign.rules_version,'claim:'||p_request_id::text)
  RETURNING id INTO v_claim_id;

  INSERT INTO public.points_ledger(tenant_id,partner_id,claim_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id)
  VALUES(v_qr.tenant_id,v_partner.id,v_claim_id,'earn',v_qr.points_value,'earn:'||v_claim_id::text,'verified_qr_claim',p_actor_user_id);

  INSERT INTO public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash)
  VALUES(v_qr.tenant_id,v_qr.id,p_actor_user_id,'accepted',p_request_id,p_app_version,p_device_ref_hash)
  ON CONFLICT(tenant_id,request_id) DO NOTHING;

  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,request_id,after_data)
  VALUES(v_qr.tenant_id,p_actor_user_id,'qr_claim_accepted','claim',v_claim_id,p_request_id,
    jsonb_build_object('points_awarded',v_qr.points_value,'campaign_id',v_qr.campaign_id));

  RETURN jsonb_build_object('ok',true,'outcome','accepted','claim_id',v_claim_id,
    'points_awarded',v_qr.points_value,'replayed',false);
END
$function$;
