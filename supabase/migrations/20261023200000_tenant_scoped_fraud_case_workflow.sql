-- Tenant-scoped manual fraud/risk case workflow.
-- This migration is source-only until the controlled production release gate is approved.

CREATE TABLE public.fraud_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  title text NOT NULL,
  reason_code text NOT NULL,
  severity text NOT NULL DEFAULT 'medium',
  status text NOT NULL DEFAULT 'open',
  summary text,
  partner_id uuid REFERENCES public.partners(id) ON DELETE SET NULL,
  claim_id uuid REFERENCES public.claims(id) ON DELETE SET NULL,
  scan_event_id uuid REFERENCES public.scan_events(id) ON DELETE SET NULL,
  assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  opened_by uuid NOT NULL REFERENCES auth.users(id),
  resolved_by uuid REFERENCES auth.users(id),
  resolution_code text,
  resolution_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  CONSTRAINT fraud_cases_title_length CHECK (length(trim(title)) BETWEEN 3 AND 160),
  CONSTRAINT fraud_cases_reason_code_format CHECK (reason_code ~ '^[a-z][a-z0-9_]{2,63}$'),
  CONSTRAINT fraud_cases_severity_check CHECK (severity IN ('low','medium','high','critical')),
  CONSTRAINT fraud_cases_status_check CHECK (status IN ('open','investigating','confirmed_fraud','resolved_legitimate','dismissed')),
  CONSTRAINT fraud_cases_summary_length CHECK (summary IS NULL OR length(summary) <= 2000),
  CONSTRAINT fraud_cases_resolution_code_format CHECK (resolution_code IS NULL OR resolution_code ~ '^[a-z][a-z0-9_]{2,63}$'),
  CONSTRAINT fraud_cases_resolution_notes_length CHECK (resolution_notes IS NULL OR length(trim(resolution_notes)) <= 2000)
);

CREATE INDEX fraud_cases_tenant_status_created_idx
  ON public.fraud_cases (tenant_id, status, created_at DESC, id DESC);
CREATE INDEX fraud_cases_tenant_partner_idx
  ON public.fraud_cases (tenant_id, partner_id, created_at DESC)
  WHERE partner_id IS NOT NULL;

ALTER TABLE public.fraud_cases ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.fraud_cases FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.fraud_cases TO service_role;

CREATE OR REPLACE FUNCTION private.create_rewardloop_fraud_case(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_title text,
  p_reason_code text,
  p_severity text DEFAULT 'medium',
  p_summary text DEFAULT NULL,
  p_partner_id uuid DEFAULT NULL,
  p_claim_id uuid DEFAULT NULL,
  p_scan_event_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_case public.fraud_cases%rowtype;
  v_title text := trim(coalesce(p_title, ''));
  v_reason text := lower(trim(coalesce(p_reason_code, '')));
  v_severity text := lower(trim(coalesce(p_severity, 'medium')));
  v_summary text := nullif(trim(coalesce(p_summary, '')), '');
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL
     OR length(v_title) < 3 OR length(v_title) > 160
     OR v_reason !~ '^[a-z][a-z0-9_]{2,63}$'
     OR v_severity NOT IN ('low','medium','high','critical')
     OR length(coalesce(v_summary,'')) > 2000 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_fraud_case_details');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_actor_user_id
      AND m.status='active' AND m.role IN ('brand_admin','super_admin')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id=p_tenant_id AND t.status='active') THEN
    RETURN jsonb_build_object('ok',false,'error','tenant_inactive');
  END IF;
  IF p_partner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.partners p WHERE p.id=p_partner_id AND p.tenant_id=p_tenant_id
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','partner_not_found');
  END IF;
  IF p_claim_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.claims c WHERE c.id=p_claim_id AND c.tenant_id=p_tenant_id
      AND (p_partner_id IS NULL OR c.partner_id=p_partner_id)
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','claim_not_found');
  END IF;
  IF p_scan_event_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.scan_events s WHERE s.id=p_scan_event_id AND s.tenant_id=p_tenant_id
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','scan_event_not_found');
  END IF;

  INSERT INTO public.fraud_cases(
    tenant_id,title,reason_code,severity,status,summary,partner_id,claim_id,scan_event_id,opened_by
  ) VALUES (
    p_tenant_id,v_title,v_reason,v_severity,'open',v_summary,p_partner_id,p_claim_id,p_scan_event_id,p_actor_user_id
  ) RETURNING * INTO v_case;

  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,after_data)
  VALUES (
    p_tenant_id,p_actor_user_id,'fraud_case_opened','fraud_case',v_case.id,
    'Manual risk case opened',
    jsonb_build_object('severity',v_case.severity,'reason_code',v_case.reason_code,
      'partner_id',v_case.partner_id,'claim_id',v_case.claim_id,'scan_event_id',v_case.scan_event_id)
  );

  RETURN jsonb_build_object('ok',true,'case',jsonb_build_object(
    'id',v_case.id,'tenant_id',v_case.tenant_id,'title',v_case.title,'reason_code',v_case.reason_code,
    'severity',v_case.severity,'status',v_case.status,'summary',v_case.summary,
    'partner_id',v_case.partner_id,'claim_id',v_case.claim_id,'scan_event_id',v_case.scan_event_id,
    'assigned_to',v_case.assigned_to,'opened_by',v_case.opened_by,'created_at',v_case.created_at
  ));
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.create_rewardloop_fraud_case(uuid,uuid,text,text,text,text,uuid,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.create_rewardloop_fraud_case(uuid,uuid,text,text,text,text,uuid,uuid,uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_create_fraud_case_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_title text,
  p_reason_code text,
  p_severity text DEFAULT 'medium',
  p_summary text DEFAULT NULL,
  p_partner_id uuid DEFAULT NULL,
  p_claim_id uuid DEFAULT NULL,
  p_scan_event_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.create_rewardloop_fraud_case(
    p_actor_user_id,p_tenant_id,p_title,p_reason_code,p_severity,p_summary,p_partner_id,p_claim_id,p_scan_event_id
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_create_fraud_case_internal(uuid,uuid,text,text,text,text,uuid,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_create_fraud_case_internal(uuid,uuid,text,text,text,text,uuid,uuid,uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION private.update_rewardloop_fraud_case(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_case_id uuid,
  p_new_status text,
  p_assigned_to uuid DEFAULT NULL,
  p_resolution_code text DEFAULT NULL,
  p_resolution_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_case public.fraud_cases%rowtype;
  v_status text := lower(trim(coalesce(p_new_status,'')));
  v_resolution_code text := lower(trim(coalesce(p_resolution_code,'')));
  v_resolution_notes text := trim(coalesce(p_resolution_notes,''));
  v_terminal boolean;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_case_id IS NULL
     OR v_status NOT IN ('open','investigating','confirmed_fraud','resolved_legitimate','dismissed')
     OR length(v_resolution_code) > 64 OR length(v_resolution_notes) > 2000 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_fraud_case_update');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_actor_user_id
      AND m.status='active' AND m.role IN ('brand_admin','super_admin')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  IF p_assigned_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_assigned_to
      AND m.status='active' AND m.role IN ('brand_admin','super_admin','support_agent')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','assignee_not_authorized');
  END IF;

  SELECT * INTO v_case FROM public.fraud_cases
   WHERE id=p_case_id AND tenant_id=p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'error','fraud_case_not_found');
  END IF;

  v_terminal := v_case.status IN ('confirmed_fraud','resolved_legitimate','dismissed');
  IF v_terminal AND v_status <> v_case.status THEN
    RETURN jsonb_build_object('ok',false,'error','fraud_case_terminal');
  END IF;
  IF v_status IN ('confirmed_fraud','resolved_legitimate','dismissed')
     AND (v_resolution_code !~ '^[a-z][a-z0-9_]{2,63}$' OR length(v_resolution_notes) < 5) THEN
    RETURN jsonb_build_object('ok',false,'error','resolution_details_required');
  END IF;

  UPDATE public.fraud_cases
     SET status=v_status,
         assigned_to=p_assigned_to,
         resolution_code=CASE WHEN v_status IN ('confirmed_fraud','resolved_legitimate','dismissed') THEN v_resolution_code ELSE NULL END,
         resolution_notes=CASE WHEN v_status IN ('confirmed_fraud','resolved_legitimate','dismissed') THEN v_resolution_notes ELSE NULL END,
         resolved_by=CASE WHEN v_status IN ('confirmed_fraud','resolved_legitimate','dismissed') THEN p_actor_user_id ELSE NULL END,
         resolved_at=CASE WHEN v_status IN ('confirmed_fraud','resolved_legitimate','dismissed') THEN now() ELSE NULL END,
         updated_at=now()
   WHERE id=v_case.id
   RETURNING * INTO v_case;

  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  VALUES (
    p_tenant_id,p_actor_user_id,'fraud_case_updated','fraud_case',v_case.id,
    CASE WHEN v_case.resolution_notes IS NULL THEN 'Fraud case status or assignment updated' ELSE v_case.resolution_notes END,
    jsonb_build_object('status',CASE WHEN v_terminal THEN v_case.status ELSE NULL END),
    jsonb_build_object('status',v_case.status,'severity',v_case.severity,'assigned_to',v_case.assigned_to,
      'resolution_code',v_case.resolution_code)
  );

  RETURN jsonb_build_object('ok',true,'case_id',v_case.id,'status',v_case.status,
    'assigned_to',v_case.assigned_to,'resolved_at',v_case.resolved_at);
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.update_rewardloop_fraud_case(uuid,uuid,uuid,text,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.update_rewardloop_fraud_case(uuid,uuid,uuid,text,uuid,text,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_update_fraud_case_internal(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_case_id uuid,
  p_new_status text,
  p_assigned_to uuid DEFAULT NULL,
  p_resolution_code text DEFAULT NULL,
  p_resolution_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.update_rewardloop_fraud_case(
    p_actor_user_id,p_tenant_id,p_case_id,p_new_status,p_assigned_to,p_resolution_code,p_resolution_notes
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_update_fraud_case_internal(uuid,uuid,uuid,text,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_update_fraud_case_internal(uuid,uuid,uuid,text,uuid,text,text)
  TO service_role;
