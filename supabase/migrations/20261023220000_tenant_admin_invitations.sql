-- Tenant-admin invitations use one-time random tokens. Only SHA-256 token hashes are persisted.
-- The invited user must authenticate with a confirmed email that matches the invitation.

CREATE TABLE public.tenant_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  email text NOT NULL CHECK (email = lower(btrim(email)) AND length(email) BETWEEN 6 AND 254),
  role text NOT NULL CHECK (role = 'brand_admin'),
  token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[a-f0-9]{64}$'),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','revoked')),
  invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  accepted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tenant_invitations_lifecycle_check CHECK (
    (status = 'pending' AND accepted_by IS NULL AND accepted_at IS NULL AND revoked_at IS NULL)
    OR (status = 'accepted' AND accepted_by IS NOT NULL AND accepted_at IS NOT NULL AND revoked_at IS NULL)
    OR (status = 'revoked' AND revoked_at IS NOT NULL AND accepted_at IS NULL)
  )
);

CREATE UNIQUE INDEX tenant_invitations_pending_email_idx
  ON public.tenant_invitations (tenant_id, lower(email))
  WHERE status = 'pending';
CREATE INDEX tenant_invitations_tenant_created_idx
  ON public.tenant_invitations (tenant_id, created_at DESC, id DESC);

ALTER TABLE public.tenant_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_invitations FORCE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.tenant_invitations FROM PUBLIC, anon, authenticated;
GRANT ALL PRIVILEGES ON TABLE public.tenant_invitations TO service_role;

CREATE OR REPLACE FUNCTION private.create_tenant_invitation(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_email text,
  p_role text,
  p_token_hash text,
  p_expires_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_email text := lower(trim(coalesce(p_email,'')));
  v_invitation public.tenant_invitations%rowtype;
  v_expired record;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL
     OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
     OR length(v_email) > 254 OR p_role IS DISTINCT FROM 'brand_admin'
     OR p_token_hash IS NULL OR p_token_hash !~ '^[a-f0-9]{64}$'
     OR p_expires_at IS NULL OR p_expires_at <= now()
     OR p_expires_at > now() + interval '7 days' THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_invitation_request');
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
  IF EXISTS (
    SELECT 1 FROM auth.users u JOIN public.tenant_memberships m ON m.user_id=u.id
    WHERE lower(u.email)=v_email AND m.tenant_id=p_tenant_id
      AND m.status='active' AND m.role='brand_admin'
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','already_tenant_admin');
  END IF;

  -- Expired pending invites must not permanently block a replacement invitation.
  FOR v_expired IN
    UPDATE public.tenant_invitations
       SET status='revoked',revoked_at=now(),updated_at=now()
     WHERE tenant_id=p_tenant_id AND lower(email)=v_email
       AND status='pending' AND expires_at <= now()
     RETURNING id,email
  LOOP
    INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,after_data)
    VALUES (p_tenant_id,p_actor_user_id,'tenant_invitation_expired','tenant_invitation',v_expired.id,
      'Expired invitation replaced',jsonb_build_object('email',v_expired.email,'status','revoked'));
  END LOOP;

  INSERT INTO public.tenant_invitations(tenant_id,email,role,token_hash,invited_by,expires_at)
  VALUES (p_tenant_id,v_email,p_role,p_token_hash,p_actor_user_id,p_expires_at)
  RETURNING * INTO v_invitation;

  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,after_data)
  VALUES (p_tenant_id,p_actor_user_id,'tenant_invitation_created','tenant_invitation',v_invitation.id,
    'Tenant admin invitation created',jsonb_build_object('email',v_invitation.email,'role',v_invitation.role,'expires_at',v_invitation.expires_at));

  RETURN jsonb_build_object('ok',true,'invitation',jsonb_build_object(
    'id',v_invitation.id,'email',v_invitation.email,'role',v_invitation.role,
    'status',v_invitation.status,'expires_at',v_invitation.expires_at,'created_at',v_invitation.created_at));
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('ok',false,'error','invitation_already_pending');
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.create_tenant_invitation(uuid,uuid,text,text,text,timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.create_tenant_invitation(uuid,uuid,text,text,text,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_create_tenant_invitation_internal(
  p_actor_user_id uuid,p_tenant_id uuid,p_email text,p_role text,p_token_hash text,p_expires_at timestamptz
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.create_tenant_invitation(p_actor_user_id,p_tenant_id,p_email,p_role,p_token_hash,p_expires_at);
$function$;
REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_create_tenant_invitation_internal(uuid,uuid,text,text,text,timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_create_tenant_invitation_internal(uuid,uuid,text,text,text,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION private.revoke_tenant_invitation(
  p_actor_user_id uuid,p_tenant_id uuid,p_invitation_id uuid,p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_invitation public.tenant_invitations%rowtype;
  v_reason text := trim(coalesce(p_reason,''));
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_invitation_id IS NULL OR length(v_reason) < 5 OR length(v_reason) > 500 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_invitation_revoke_request');
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

  SELECT * INTO v_invitation FROM public.tenant_invitations
   WHERE id=p_invitation_id AND tenant_id=p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','invitation_not_found'); END IF;
  IF v_invitation.status='accepted' THEN RETURN jsonb_build_object('ok',false,'error','invitation_already_accepted'); END IF;
  IF v_invitation.status='revoked' THEN RETURN jsonb_build_object('ok',true,'unchanged',true,'invitation_id',v_invitation.id); END IF;
  IF v_invitation.expires_at <= now() THEN RETURN jsonb_build_object('ok',false,'error','invitation_expired'); END IF;

  UPDATE public.tenant_invitations SET status='revoked',revoked_at=now(),updated_at=now()
   WHERE id=v_invitation.id RETURNING * INTO v_invitation;
  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  VALUES (p_tenant_id,p_actor_user_id,'tenant_invitation_revoked','tenant_invitation',v_invitation.id,v_reason,
    jsonb_build_object('status','pending','email',v_invitation.email),
    jsonb_build_object('status','revoked','email',v_invitation.email));
  RETURN jsonb_build_object('ok',true,'invitation_id',v_invitation.id,'status',v_invitation.status);
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.revoke_tenant_invitation(uuid,uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.revoke_tenant_invitation(uuid,uuid,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_revoke_tenant_invitation_internal(
  p_actor_user_id uuid,p_tenant_id uuid,p_invitation_id uuid,p_reason text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.revoke_tenant_invitation(p_actor_user_id,p_tenant_id,p_invitation_id,p_reason);
$function$;
REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_revoke_tenant_invitation_internal(uuid,uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_revoke_tenant_invitation_internal(uuid,uuid,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION private.accept_tenant_invitation(
  p_actor_user_id uuid,p_token_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_invitation public.tenant_invitations%rowtype;
  v_user_email text;
  v_email_confirmed_at timestamptz;
  v_membership public.tenant_memberships%rowtype;
BEGIN
  IF p_actor_user_id IS NULL OR p_token_hash IS NULL OR p_token_hash !~ '^[a-f0-9]{64}$' THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_invitation');
  END IF;
  SELECT lower(email),email_confirmed_at INTO v_user_email,v_email_confirmed_at
    FROM auth.users WHERE id=p_actor_user_id;
  IF NOT FOUND OR v_user_email IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_invitation');
  END IF;
  IF v_email_confirmed_at IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','email_not_confirmed');
  END IF;

  SELECT * INTO v_invitation FROM public.tenant_invitations
   WHERE token_hash=p_token_hash FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','invalid_invitation'); END IF;
  IF v_invitation.status='accepted' AND v_invitation.accepted_by=p_actor_user_id THEN
    RETURN jsonb_build_object('ok',true,'already_accepted',true,'tenant_id',v_invitation.tenant_id,'tenant_slug',(SELECT slug FROM public.tenants WHERE id=v_invitation.tenant_id),'role',v_invitation.role);
  END IF;
  IF v_invitation.status <> 'pending' THEN RETURN jsonb_build_object('ok',false,'error','invalid_invitation'); END IF;
  IF v_invitation.expires_at <= now() THEN RETURN jsonb_build_object('ok',false,'error','invitation_expired'); END IF;
  IF v_invitation.email <> v_user_email THEN RETURN jsonb_build_object('ok',false,'error','invitation_email_mismatch'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id=v_invitation.tenant_id AND t.status='active') THEN
    RETURN jsonb_build_object('ok',false,'error','tenant_inactive');
  END IF;

  SELECT * INTO v_membership FROM public.tenant_memberships
   WHERE tenant_id=v_invitation.tenant_id AND user_id=p_actor_user_id AND role=v_invitation.role::public.partner_role FOR UPDATE;
  IF FOUND THEN
    IF v_membership.status <> 'active' THEN
      RETURN jsonb_build_object('ok',false,'error','membership_conflict');
    END IF;
  ELSE
    INSERT INTO public.tenant_memberships(tenant_id,user_id,role,status)
    VALUES (v_invitation.tenant_id,p_actor_user_id,v_invitation.role::public.partner_role,'active')
    RETURNING * INTO v_membership;
  END IF;

  UPDATE public.tenant_invitations SET status='accepted',accepted_by=p_actor_user_id,
    accepted_at=now(),updated_at=now() WHERE id=v_invitation.id RETURNING * INTO v_invitation;
  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  VALUES (v_invitation.tenant_id,p_actor_user_id,'tenant_invitation_accepted','tenant_invitation',v_invitation.id,
    'Invitation accepted by verified email owner',jsonb_build_object('status','pending'),
    jsonb_build_object('status','accepted','email',v_invitation.email,'role',v_invitation.role,'membership_id',v_membership.id));
  RETURN jsonb_build_object('ok',true,'tenant_id',v_invitation.tenant_id,'role',v_invitation.role,
    'tenant_slug',(SELECT slug FROM public.tenants WHERE id=v_invitation.tenant_id));
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.accept_tenant_invitation(uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.accept_tenant_invitation(uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.rewardloop_accept_tenant_invitation_internal(
  p_actor_user_id uuid,p_token_hash text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.accept_tenant_invitation(p_actor_user_id,p_token_hash);
$function$;
REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_accept_tenant_invitation_internal(uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_accept_tenant_invitation_internal(uuid,text) TO service_role;
