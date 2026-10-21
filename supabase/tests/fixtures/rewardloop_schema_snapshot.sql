-- TEST-ONLY SCHEMA FIXTURE generated from live RewardLoop schema metadata. No tenant/claim/reward rows are included.
-- DO NOT use as a production migration. This is an isolated test bootstrap only.
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

CREATE TYPE public.campaign_status AS ENUM ('draft', 'scheduled', 'active', 'paused', 'ended', 'archived');

CREATE TYPE public.claim_status AS ENUM ('accepted', 'rejected', 'review', 'reversed');

CREATE TYPE public.ledger_entry_type AS ENUM ('earn', 'redeem_reserve', 'redeem_capture', 'redeem_release', 'expire', 'reverse', 'adjust');

CREATE TYPE public.partner_role AS ENUM ('farmer', 'retailer', 'distributor', 'brand_admin', 'support_agent', 'super_admin');

CREATE TYPE public.qr_status AS ENUM ('created', 'active', 'claimed', 'revoked', 'expired');

CREATE TABLE public.audit_logs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid,
  actor_user_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  request_id uuid,
  reason text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.campaigns (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  status campaign_status DEFAULT 'draft'::campaign_status NOT NULL,
  starts_at timestamp with time zone,
  ends_at timestamp with time zone,
  budget_minor_units bigint DEFAULT 0 NOT NULL,
  currency character(3) DEFAULT 'INR'::bpchar NOT NULL,
  rules_version integer DEFAULT 1 NOT NULL,
  rules jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.claims (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  qr_code_id uuid NOT NULL,
  partner_id uuid NOT NULL,
  campaign_id uuid,
  status claim_status NOT NULL,
  points_awarded integer DEFAULT 0 NOT NULL,
  rule_version integer DEFAULT 1 NOT NULL,
  idempotency_key text NOT NULL,
  reason_code text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  reviewed_by uuid,
  reviewed_at timestamp with time zone
);

CREATE TABLE public.partners (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  user_id uuid,
  role partner_role NOT NULL,
  display_name text NOT NULL,
  phone_e164 text,
  preferred_locale text DEFAULT 'hi-IN'::text NOT NULL,
  verification_status text DEFAULT 'unverified'::text NOT NULL,
  external_ref text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.points_ledger (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  partner_id uuid NOT NULL,
  claim_id uuid,
  entry_type ledger_entry_type NOT NULL,
  points_delta bigint NOT NULL,
  idempotency_key text NOT NULL,
  reason_code text NOT NULL,
  actor_user_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE public.production_batches (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  batch_code text NOT NULL,
  manufactured_on date,
  expires_on date,
  status text DEFAULT 'active'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.products (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  sku text NOT NULL,
  name text NOT NULL,
  pack_size text,
  active boolean DEFAULT true NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.qr_codes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  batch_id uuid,
  campaign_id uuid,
  token_hash text NOT NULL,
  status qr_status DEFAULT 'created'::qr_status NOT NULL,
  entitlement_role partner_role DEFAULT 'farmer'::partner_role NOT NULL,
  points_value integer DEFAULT 0 NOT NULL,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  activated_at timestamp with time zone,
  expires_at timestamp with time zone,
  claimed_at timestamp with time zone,
  revoked_at timestamp with time zone,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  issuance_batch_id uuid
);

CREATE TABLE public.qr_issuance_batches (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  campaign_id uuid NOT NULL,
  created_by uuid NOT NULL,
  requested_count integer NOT NULL,
  points_value integer NOT NULL,
  entitlement_role partner_role NOT NULL,
  status text DEFAULT 'creating'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  completed_at timestamp with time zone
);

CREATE TABLE public.redemptions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  partner_id uuid NOT NULL,
  reward_id uuid NOT NULL,
  points_cost integer NOT NULL,
  status text DEFAULT 'reserved'::text NOT NULL,
  request_key text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  fulfilled_at timestamp with time zone,
  cancellation_reason text
);

CREATE TABLE public.rewardloop_admin_settings (
  tenant_id uuid NOT NULL,
  email_provider text DEFAULT 'gmail'::text NOT NULL,
  sender_email text,
  sender_name text DEFAULT 'Growta RewardLoop'::text NOT NULL,
  smtp_host text,
  smtp_port integer DEFAULT 587 NOT NULL,
  smtp_username text,
  site_url text DEFAULT 'https://bigagri.vercel.app'::text NOT NULL,
  redirect_urls text[] DEFAULT ARRAY['https://bigagri.vercel.app/**'::text] NOT NULL,
  signup_enabled boolean DEFAULT true NOT NULL,
  email_confirmation_required boolean DEFAULT true NOT NULL,
  confirmation_subject text DEFAULT 'Confirm your Growta RewardLoop account'::text NOT NULL,
  confirmation_body text DEFAULT 'Welcome to Growta RewardLoop. Confirm your email address to activate your account.'::text NOT NULL,
  recovery_subject text DEFAULT 'Reset your Growta RewardLoop password'::text NOT NULL,
  recovery_body text DEFAULT 'We received a request to reset your password. Follow the secure link to continue.'::text NOT NULL,
  smtp_configured boolean DEFAULT false NOT NULL,
  updated_by uuid,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.rewards (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  slug text NOT NULL,
  name text NOT NULL,
  name_hi text,
  description text,
  description_hi text,
  category text DEFAULT 'general'::text NOT NULL,
  points_cost integer NOT NULL,
  stock_quantity integer,
  active boolean DEFAULT false NOT NULL,
  is_demo boolean DEFAULT false NOT NULL,
  sort_order integer DEFAULT 100 NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.scan_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  qr_code_id uuid,
  actor_user_id uuid,
  outcome text NOT NULL,
  request_id uuid NOT NULL,
  app_version text,
  device_ref_hash text,
  coarse_region text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tenant_memberships (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role partner_role NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tenants (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  slug text NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  default_locale text DEFAULT 'hi-IN'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.audit_logs ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);
ALTER TABLE public.campaigns ADD CONSTRAINT campaigns_pkey PRIMARY KEY (id);
ALTER TABLE public.claims ADD CONSTRAINT claims_pkey PRIMARY KEY (id);
ALTER TABLE public.partners ADD CONSTRAINT partners_pkey PRIMARY KEY (id);
ALTER TABLE public.points_ledger ADD CONSTRAINT points_ledger_pkey PRIMARY KEY (id);
ALTER TABLE public.production_batches ADD CONSTRAINT production_batches_pkey PRIMARY KEY (id);
ALTER TABLE public.products ADD CONSTRAINT products_pkey PRIMARY KEY (id);
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_pkey PRIMARY KEY (id);
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_pkey PRIMARY KEY (id);
ALTER TABLE public.redemptions ADD CONSTRAINT redemptions_pkey PRIMARY KEY (id);
ALTER TABLE public.rewardloop_admin_settings ADD CONSTRAINT rewardloop_admin_settings_pkey PRIMARY KEY (tenant_id);
ALTER TABLE public.rewards ADD CONSTRAINT rewards_pkey PRIMARY KEY (id);
ALTER TABLE public.scan_events ADD CONSTRAINT scan_events_pkey PRIMARY KEY (id);
ALTER TABLE public.tenant_memberships ADD CONSTRAINT tenant_memberships_pkey PRIMARY KEY (id);
ALTER TABLE public.tenants ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);
ALTER TABLE public.claims ADD CONSTRAINT claims_tenant_id_idempotency_key_key UNIQUE (tenant_id, idempotency_key);
ALTER TABLE public.partners ADD CONSTRAINT partners_tenant_id_external_ref_key UNIQUE (tenant_id, external_ref);
ALTER TABLE public.partners ADD CONSTRAINT partners_tenant_id_user_id_key UNIQUE (tenant_id, user_id);
ALTER TABLE public.points_ledger ADD CONSTRAINT points_ledger_tenant_id_idempotency_key_key UNIQUE (tenant_id, idempotency_key);
ALTER TABLE public.production_batches ADD CONSTRAINT production_batches_tenant_id_batch_code_key UNIQUE (tenant_id, batch_code);
ALTER TABLE public.products ADD CONSTRAINT products_tenant_id_sku_key UNIQUE (tenant_id, sku);
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_tenant_id_token_hash_key UNIQUE (tenant_id, token_hash);
ALTER TABLE public.redemptions ADD CONSTRAINT redemptions_tenant_id_request_key_key UNIQUE (tenant_id, request_key);
ALTER TABLE public.rewards ADD CONSTRAINT rewards_tenant_id_slug_key UNIQUE (tenant_id, slug);
ALTER TABLE public.scan_events ADD CONSTRAINT scan_events_tenant_id_request_id_key UNIQUE (tenant_id, request_id);
ALTER TABLE public.tenant_memberships ADD CONSTRAINT tenant_memberships_tenant_id_user_id_role_key UNIQUE (tenant_id, user_id, role);
ALTER TABLE public.tenants ADD CONSTRAINT tenants_slug_key UNIQUE (slug);
ALTER TABLE public.campaigns ADD CONSTRAINT campaigns_budget_minor_units_check CHECK ((budget_minor_units >= 0));
ALTER TABLE public.campaigns ADD CONSTRAINT campaigns_check CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at > starts_at)));
ALTER TABLE public.campaigns ADD CONSTRAINT campaigns_rules_version_check CHECK ((rules_version > 0));
ALTER TABLE public.claims ADD CONSTRAINT claims_points_awarded_check CHECK ((points_awarded >= 0));
ALTER TABLE public.partners ADD CONSTRAINT partners_display_name_check CHECK (((length(TRIM(BOTH FROM display_name)) >= 1) AND (length(TRIM(BOTH FROM display_name)) <= 160)));
ALTER TABLE public.partners ADD CONSTRAINT partners_role_check CHECK ((role = ANY (ARRAY['farmer'::partner_role, 'retailer'::partner_role, 'distributor'::partner_role])));
ALTER TABLE public.partners ADD CONSTRAINT partners_verification_status_check CHECK ((verification_status = ANY (ARRAY['unverified'::text, 'pending'::text, 'verified'::text, 'rejected'::text, 'suspended'::text])));
ALTER TABLE public.points_ledger ADD CONSTRAINT points_ledger_points_delta_check CHECK ((points_delta <> 0));
ALTER TABLE public.production_batches ADD CONSTRAINT production_batches_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'suspended'::text, 'recalled'::text, 'closed'::text])));
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_check CHECK (((expires_at IS NULL) OR (expires_at > issued_at)));
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_entitlement_role_check CHECK ((entitlement_role = ANY (ARRAY['farmer'::partner_role, 'retailer'::partner_role, 'distributor'::partner_role])));
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_points_value_check CHECK ((points_value >= 0));
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_entitlement_role_check CHECK ((entitlement_role = ANY (ARRAY['farmer'::partner_role, 'retailer'::partner_role, 'distributor'::partner_role])));
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_points_value_check CHECK (((points_value >= 1) AND (points_value <= 1000000)));
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_requested_count_check CHECK (((requested_count >= 1) AND (requested_count <= 1000)));
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_status_check CHECK ((status = ANY (ARRAY['creating'::text, 'issued'::text, 'failed'::text, 'revoked'::text])));
ALTER TABLE public.redemptions ADD CONSTRAINT redemptions_points_cost_check CHECK ((points_cost > 0));
ALTER TABLE public.redemptions ADD CONSTRAINT redemptions_status_check CHECK ((status = ANY (ARRAY['reserved'::text, 'approved'::text, 'fulfilled'::text, 'cancelled'::text, 'rejected'::text])));
ALTER TABLE public.rewardloop_admin_settings ADD CONSTRAINT rewardloop_admin_settings_email_provider_check CHECK ((email_provider = ANY (ARRAY['gmail'::text, 'resend'::text, 'custom'::text])));
ALTER TABLE public.rewardloop_admin_settings ADD CONSTRAINT rewardloop_admin_settings_smtp_port_check CHECK (((smtp_port >= 1) AND (smtp_port <= 65535)));
ALTER TABLE public.rewards ADD CONSTRAINT rewards_name_check CHECK (((length(TRIM(BOTH FROM name)) >= 2) AND (length(TRIM(BOTH FROM name)) <= 160)));
ALTER TABLE public.rewards ADD CONSTRAINT rewards_points_cost_check CHECK (((points_cost >= 1) AND (points_cost <= 100000000)));
ALTER TABLE public.rewards ADD CONSTRAINT rewards_stock_quantity_check CHECK (((stock_quantity IS NULL) OR (stock_quantity >= 0)));
ALTER TABLE public.scan_events ADD CONSTRAINT scan_events_outcome_check CHECK ((outcome = ANY (ARRAY['detected'::text, 'accepted'::text, 'duplicate'::text, 'invalid'::text, 'revoked'::text, 'expired'::text, 'ineligible'::text, 'rate_limited'::text, 'error'::text, 'review'::text])));
ALTER TABLE public.tenant_memberships ADD CONSTRAINT tenant_memberships_status_check CHECK ((status = ANY (ARRAY['invited'::text, 'active'::text, 'suspended'::text, 'removed'::text])));
ALTER TABLE public.tenants ADD CONSTRAINT tenants_name_check CHECK (((length(TRIM(BOTH FROM name)) >= 2) AND (length(TRIM(BOTH FROM name)) <= 160)));
ALTER TABLE public.tenants ADD CONSTRAINT tenants_slug_check CHECK ((slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'::text));
ALTER TABLE public.tenants ADD CONSTRAINT tenants_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'closed'::text])));
ALTER TABLE public.audit_logs ADD CONSTRAINT audit_logs_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.audit_logs ADD CONSTRAINT audit_logs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.campaigns ADD CONSTRAINT campaigns_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.campaigns ADD CONSTRAINT campaigns_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.claims ADD CONSTRAINT claims_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE RESTRICT;
ALTER TABLE public.claims ADD CONSTRAINT claims_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE RESTRICT;
ALTER TABLE public.claims ADD CONSTRAINT claims_qr_code_id_fkey FOREIGN KEY (qr_code_id) REFERENCES qr_codes(id) ON DELETE RESTRICT;
ALTER TABLE public.claims ADD CONSTRAINT claims_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.claims ADD CONSTRAINT claims_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.partners ADD CONSTRAINT partners_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.partners ADD CONSTRAINT partners_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE public.points_ledger ADD CONSTRAINT points_ledger_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.points_ledger ADD CONSTRAINT points_ledger_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES claims(id) ON DELETE RESTRICT;
ALTER TABLE public.points_ledger ADD CONSTRAINT points_ledger_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE RESTRICT;
ALTER TABLE public.points_ledger ADD CONSTRAINT points_ledger_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.production_batches ADD CONSTRAINT production_batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;
ALTER TABLE public.production_batches ADD CONSTRAINT production_batches_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.products ADD CONSTRAINT products_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES production_batches(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_issuance_batch_id_fkey FOREIGN KEY (issuance_batch_id) REFERENCES qr_issuance_batches(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_codes ADD CONSTRAINT qr_codes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;
ALTER TABLE public.qr_issuance_batches ADD CONSTRAINT qr_issuance_batches_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.redemptions ADD CONSTRAINT redemptions_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE RESTRICT;
ALTER TABLE public.redemptions ADD CONSTRAINT redemptions_reward_id_fkey FOREIGN KEY (reward_id) REFERENCES rewards(id) ON DELETE RESTRICT;
ALTER TABLE public.redemptions ADD CONSTRAINT redemptions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.rewardloop_admin_settings ADD CONSTRAINT rewardloop_admin_settings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE public.rewards ADD CONSTRAINT rewards_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.scan_events ADD CONSTRAINT scan_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.scan_events ADD CONSTRAINT scan_events_qr_code_id_fkey FOREIGN KEY (qr_code_id) REFERENCES qr_codes(id) ON DELETE RESTRICT;
ALTER TABLE public.scan_events ADD CONSTRAINT scan_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.tenant_memberships ADD CONSTRAINT tenant_memberships_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.tenant_memberships ADD CONSTRAINT tenant_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;




























































































CREATE INDEX audit_logs_actor_user_idx ON public.audit_logs USING btree (actor_user_id);

CREATE INDEX audit_logs_tenant_time_idx ON public.audit_logs USING btree (tenant_id, created_at DESC);

CREATE INDEX campaigns_created_by_idx ON public.campaigns USING btree (created_by);

CREATE INDEX campaigns_tenant_status_idx ON public.campaigns USING btree (tenant_id, status, starts_at);

CREATE INDEX claims_campaign_idx ON public.claims USING btree (campaign_id);

CREATE UNIQUE INDEX claims_one_accepted_per_qr_idx ON public.claims USING btree (qr_code_id) WHERE (status = 'accepted'::claim_status);

CREATE INDEX claims_partner_created_idx ON public.claims USING btree (partner_id, created_at DESC);

CREATE INDEX claims_reviewed_by_idx ON public.claims USING btree (reviewed_by);

CREATE INDEX claims_tenant_created_idx ON public.claims USING btree (tenant_id, created_at DESC);

CREATE INDEX partners_tenant_role_idx ON public.partners USING btree (tenant_id, role, verification_status);

CREATE INDEX partners_user_id_idx ON public.partners USING btree (user_id);

CREATE INDEX points_ledger_actor_user_idx ON public.points_ledger USING btree (actor_user_id);

CREATE INDEX points_ledger_claim_idx ON public.points_ledger USING btree (claim_id);

CREATE INDEX points_ledger_partner_idx ON public.points_ledger USING btree (partner_id);

CREATE INDEX points_ledger_partner_time_idx ON public.points_ledger USING btree (tenant_id, partner_id, created_at DESC);

CREATE INDEX production_batches_product_idx ON public.production_batches USING btree (product_id);

CREATE INDEX qr_codes_batch_idx ON public.qr_codes USING btree (batch_id);

CREATE INDEX qr_codes_campaign_idx ON public.qr_codes USING btree (campaign_id);

CREATE INDEX qr_codes_campaign_status_idx ON public.qr_codes USING btree (tenant_id, campaign_id, status);

CREATE INDEX qr_codes_issuance_batch_idx ON public.qr_codes USING btree (issuance_batch_id);

CREATE INDEX qr_codes_product_idx ON public.qr_codes USING btree (product_id);

CREATE INDEX qr_issuance_batches_campaign_idx ON public.qr_issuance_batches USING btree (campaign_id);

CREATE INDEX qr_issuance_batches_created_by_idx ON public.qr_issuance_batches USING btree (created_by);

CREATE INDEX qr_issuance_batches_product_idx ON public.qr_issuance_batches USING btree (product_id);

CREATE INDEX qr_issuance_batches_tenant_time_idx ON public.qr_issuance_batches USING btree (tenant_id, created_at DESC);

CREATE INDEX redemptions_partner_idx ON public.redemptions USING btree (partner_id);

CREATE INDEX redemptions_partner_time_idx ON public.redemptions USING btree (tenant_id, partner_id, created_at DESC);

CREATE INDEX redemptions_reward_idx ON public.redemptions USING btree (reward_id);

CREATE INDEX rewards_catalog_idx ON public.rewards USING btree (tenant_id, active, sort_order);

CREATE INDEX scan_events_actor_user_idx ON public.scan_events USING btree (actor_user_id);

CREATE INDEX scan_events_qr_code_idx ON public.scan_events USING btree (qr_code_id);

CREATE INDEX scan_events_tenant_time_idx ON public.scan_events USING btree (tenant_id, created_at DESC);

CREATE INDEX tenant_memberships_user_idx ON public.tenant_memberships USING btree (user_id, tenant_id) WHERE (status = 'active'::text);

CREATE OR REPLACE FUNCTION private.claim_qr(p_actor_user_id uuid, p_token text, p_request_id uuid, p_app_version text DEFAULT NULL::text, p_device_ref_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
declare v_qr public.qr_codes%rowtype; v_partner public.partners%rowtype; v_campaign public.campaigns%rowtype; v_claim_id uuid; v_existing public.claims%rowtype;
begin
 if p_actor_user_id is null or p_request_id is null then return jsonb_build_object('ok',false,'outcome','invalid_request','points_awarded',0); end if;
 if p_token is null or length(p_token)<16 or length(p_token)>512 then return jsonb_build_object('ok',false,'outcome','invalid_code','points_awarded',0); end if;
 select q.* into v_qr from public.qr_codes q where q.token_hash=encode(digest(convert_to(p_token,'UTF8'),'sha256'),'hex') limit 1;
 if not found then return jsonb_build_object('ok',false,'outcome','invalid_code','points_awarded',0); end if;
 select q.* into v_qr from public.qr_codes q where q.id=v_qr.id for update;
 select c.* into v_existing from public.claims c where c.tenant_id=v_qr.tenant_id and c.idempotency_key=('claim:'||p_request_id::text) limit 1;
 if found then return jsonb_build_object('ok',v_existing.status='accepted','outcome',case when v_existing.status='accepted' then 'accepted' else 'rejected' end,'claim_id',v_existing.id,'points_awarded',v_existing.points_awarded,'replayed',true); end if;
 select p.* into v_partner from public.partners p where p.tenant_id=v_qr.tenant_id and p.user_id=p_actor_user_id and p.verification_status='verified' and p.role=v_qr.entitlement_role limit 1;
 if not found then
  insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash) values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'ineligible',p_request_id,p_app_version,p_device_ref_hash) on conflict(tenant_id,request_id) do nothing;
  return jsonb_build_object('ok',false,'outcome','ineligible','points_awarded',0);
 end if;
 if v_qr.status='claimed' then
  insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash) values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'duplicate',p_request_id,p_app_version,p_device_ref_hash) on conflict(tenant_id,request_id) do nothing;
  return jsonb_build_object('ok',false,'outcome','already_claimed','points_awarded',0);
 elsif v_qr.status='revoked' then
  insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash) values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'revoked',p_request_id,p_app_version,p_device_ref_hash) on conflict(tenant_id,request_id) do nothing;
  return jsonb_build_object('ok',false,'outcome','revoked','points_awarded',0);
 elsif v_qr.status='expired' or (v_qr.expires_at is not null and v_qr.expires_at<=now()) then
  insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash) values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'expired',p_request_id,p_app_version,p_device_ref_hash) on conflict(tenant_id,request_id) do nothing;
  return jsonb_build_object('ok',false,'outcome','expired','points_awarded',0);
 elsif v_qr.status<>'active' then
  insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash) values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'invalid',p_request_id,p_app_version,p_device_ref_hash) on conflict(tenant_id,request_id) do nothing;
  return jsonb_build_object('ok',false,'outcome','not_activated','points_awarded',0);
 end if;
 if v_qr.campaign_id is null then return jsonb_build_object('ok',false,'outcome','campaign_missing','points_awarded',0); end if;
 select c.* into v_campaign from public.campaigns c where c.id=v_qr.campaign_id and c.tenant_id=v_qr.tenant_id;
 if not found or v_campaign.status<>'active' or (v_campaign.starts_at is not null and v_campaign.starts_at>now()) or (v_campaign.ends_at is not null and v_campaign.ends_at<=now()) then
  insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash) values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'ineligible',p_request_id,p_app_version,p_device_ref_hash) on conflict(tenant_id,request_id) do nothing;
  return jsonb_build_object('ok',false,'outcome','campaign_inactive','points_awarded',0);
 end if;
 if v_qr.points_value<=0 then return jsonb_build_object('ok',false,'outcome','no_reward_value','points_awarded',0); end if;
 update public.qr_codes set status='claimed',claimed_at=now() where id=v_qr.id and status='active';
 if not found then
  insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash) values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'duplicate',p_request_id,p_app_version,p_device_ref_hash) on conflict(tenant_id,request_id) do nothing;
  return jsonb_build_object('ok',false,'outcome','already_claimed','points_awarded',0);
 end if;
 insert into public.claims(tenant_id,qr_code_id,partner_id,campaign_id,status,points_awarded,rule_version,idempotency_key) values(v_qr.tenant_id,v_qr.id,v_partner.id,v_qr.campaign_id,'accepted',v_qr.points_value,v_campaign.rules_version,'claim:'||p_request_id::text) returning id into v_claim_id;
 insert into public.points_ledger(tenant_id,partner_id,claim_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id) values(v_qr.tenant_id,v_partner.id,v_claim_id,'earn',v_qr.points_value,'earn:'||v_claim_id::text,'verified_qr_claim',p_actor_user_id);
 insert into public.scan_events(tenant_id,qr_code_id,actor_user_id,outcome,request_id,app_version,device_ref_hash) values(v_qr.tenant_id,v_qr.id,p_actor_user_id,'accepted',p_request_id,p_app_version,p_device_ref_hash) on conflict(tenant_id,request_id) do nothing;
 insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,request_id,after_data) values(v_qr.tenant_id,p_actor_user_id,'qr_claim_accepted','claim',v_claim_id,p_request_id,jsonb_build_object('points_awarded',v_qr.points_value,'campaign_id',v_qr.campaign_id));
 return jsonb_build_object('ok',true,'outcome','accepted','claim_id',v_claim_id,'points_awarded',v_qr.points_value,'replayed',false);
end $function$


CREATE OR REPLACE FUNCTION private.create_rewardloop_campaign(p_actor_user_id uuid, p_tenant_id uuid, p_name text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_budget_minor_units bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
declare v_campaign_id uuid;
begin
  if p_actor_user_id is null or p_tenant_id is null
    or length(trim(coalesce(p_name,''))) < 3 or length(trim(p_name)) > 120
    or p_budget_minor_units is null or p_budget_minor_units < 0
    or (p_starts_at is not null and p_ends_at is not null and p_ends_at <= p_starts_at)
    or (p_ends_at is not null and p_ends_at <= now()) then
    return jsonb_build_object('ok',false,'error','invalid_campaign_details');
  end if;
  if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then
    return jsonb_build_object('ok',false,'error','forbidden');
  end if;
  if not exists(select 1 from public.tenants t where t.id=p_tenant_id and t.status='active') then
    return jsonb_build_object('ok',false,'error','tenant_inactive');
  end if;
  insert into public.campaigns(tenant_id,name,status,starts_at,ends_at,budget_minor_units,currency,rules_version,rules,created_by,created_at,updated_at)
  values(p_tenant_id,trim(p_name),'draft',p_starts_at,p_ends_at,p_budget_minor_units,'INR',1,'{}'::jsonb,p_actor_user_id,now(),now())
  returning id into v_campaign_id;
  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,after_data)
  values(p_tenant_id,p_actor_user_id,'campaign_created','campaign',v_campaign_id,
    jsonb_build_object('name',trim(p_name),'status','draft','starts_at',p_starts_at,'ends_at',p_ends_at,'budget_minor_units',p_budget_minor_units,'currency','INR'));
  return jsonb_build_object('ok',true,'campaign_id',v_campaign_id,'status','draft');
end
$function$;
CREATE OR REPLACE FUNCTION private.issue_qr_batch(p_actor_user_id uuid, p_tenant_id uuid, p_campaign_id uuid, p_product_id uuid, p_count integer, p_points_value integer, p_entitlement_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
declare v_campaign public.campaigns%rowtype; v_product public.products%rowtype; v_tenant public.tenants%rowtype; v_batch_id uuid; v_role public.partner_role; v_token text; v_qr_id uuid; v_codes jsonb:='[]'::jsonb; i integer;
begin
 if p_actor_user_id is null or p_tenant_id is null or p_campaign_id is null or p_product_id is null or p_count is null or p_count<1 or p_count>1000 or p_points_value is null or p_points_value<1 or p_points_value>1000000 or p_entitlement_role not in ('farmer','retailer','distributor') then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
 v_role:=p_entitlement_role::public.partner_role;
 if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
 select t.* into v_tenant from public.tenants t where t.id=p_tenant_id and t.status='active';
 select p.* into v_product from public.products p where p.id=p_product_id and p.tenant_id=p_tenant_id and p.active;
 select c.* into v_campaign from public.campaigns c where c.id=p_campaign_id and c.tenant_id=p_tenant_id;
 if v_tenant.id is null or v_product.id is null or v_campaign.id is null or v_campaign.status<>'active' or (v_campaign.starts_at is not null and v_campaign.starts_at>now()) or (v_campaign.ends_at is not null and v_campaign.ends_at<=now()) then return jsonb_build_object('ok',false,'error','tenant_product_or_campaign_not_active'); end if;
 insert into public.qr_issuance_batches(tenant_id,product_id,campaign_id,created_by,requested_count,points_value,entitlement_role,status) values(p_tenant_id,p_product_id,p_campaign_id,p_actor_user_id,p_count,p_points_value,v_role,'creating') returning id into v_batch_id;
 for i in 1..p_count loop
  v_token:=translate(rtrim(encode(gen_random_bytes(32),'base64'),'='),'+/','-_');
  insert into public.qr_codes(tenant_id,product_id,campaign_id,issuance_batch_id,token_hash,status,entitlement_role,points_value,activated_at,metadata) values(p_tenant_id,p_product_id,p_campaign_id,v_batch_id,encode(digest(convert_to(v_token,'UTF8'),'sha256'),'hex'),'active',v_role,p_points_value,now(),jsonb_build_object('issuance_version',1)) returning id into v_qr_id;
  v_codes:=v_codes||jsonb_build_array(jsonb_build_object('ordinal',i,'qr_id',v_qr_id,'token',v_token,'qr_payload',v_token));
 end loop;
 update public.qr_issuance_batches set status='issued',completed_at=now() where id=v_batch_id;
 insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,after_data) values(p_tenant_id,p_actor_user_id,'qr_batch_issued','qr_issuance_batch',v_batch_id,jsonb_build_object('count',p_count,'product_id',p_product_id,'campaign_id',p_campaign_id,'points_value',p_points_value,'entitlement_role',v_role));
 return jsonb_build_object('ok',true,'batch_id',v_batch_id,'count',p_count,'points_value',p_points_value,'entitlement_role',v_role,'codes',v_codes);
end $function$


CREATE OR REPLACE FUNCTION private.redeem_reward(p_actor_user_id uuid, p_reward_id uuid, p_request_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
declare v_partner public.partners%rowtype; v_reward public.rewards%rowtype; v_existing public.redemptions%rowtype; v_balance bigint; v_redemption_id uuid;
begin
 if p_actor_user_id is null or p_reward_id is null or p_request_key is null or length(trim(p_request_key))<8 or length(p_request_key)>160 then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor_user_id::text,0));
 select r.* into v_existing from public.redemptions r where r.request_key=p_request_key and r.tenant_id=(select tenant_id from public.rewards where id=p_reward_id) limit 1;
 if found then return jsonb_build_object('ok',v_existing.status not in ('cancelled','rejected'),'redemption_id',v_existing.id,'status',v_existing.status,'replayed',true); end if;
 select p.* into v_partner from public.partners p where p.user_id=p_actor_user_id and p.verification_status='verified' and p.role='farmer' order by p.created_at limit 1;
 if not found then return jsonb_build_object('ok',false,'error','partner_not_verified'); end if;
 select rw.* into v_reward from public.rewards rw where rw.id=p_reward_id and rw.tenant_id=v_partner.tenant_id and rw.active for update;
 if not found then return jsonb_build_object('ok',false,'error','reward_unavailable'); end if;
 if v_reward.is_demo then return jsonb_build_object('ok',false,'error','demo_reward_not_redeemable'); end if;
 if v_reward.stock_quantity is not null and v_reward.stock_quantity<1 then return jsonb_build_object('ok',false,'error','out_of_stock'); end if;
 select coalesce(sum(l.points_delta),0) into v_balance from public.points_ledger l where l.tenant_id=v_partner.tenant_id and l.partner_id=v_partner.id;
 if v_balance<v_reward.points_cost then return jsonb_build_object('ok',false,'error','insufficient_points','balance',v_balance,'required',v_reward.points_cost); end if;
 insert into public.redemptions(tenant_id,partner_id,reward_id,points_cost,status,request_key) values(v_partner.tenant_id,v_partner.id,v_reward.id,v_reward.points_cost,'reserved',p_request_key) returning id into v_redemption_id;
 insert into public.points_ledger(tenant_id,partner_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id,metadata) values(v_partner.tenant_id,v_partner.id,'redeem_reserve',-v_reward.points_cost,'redeem:'||v_redemption_id::text,'reward_redemption_reserved',p_actor_user_id,jsonb_build_object('redemption_id',v_redemption_id,'reward_id',v_reward.id));
 if v_reward.stock_quantity is not null then update public.rewards set stock_quantity=stock_quantity-1,updated_at=now() where id=v_reward.id; end if;
 insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,after_data) values(v_partner.tenant_id,p_actor_user_id,'reward_redemption_reserved','redemption',v_redemption_id,jsonb_build_object('reward_id',v_reward.id,'points_cost',v_reward.points_cost));
 return jsonb_build_object('ok',true,'redemption_id',v_redemption_id,'status','reserved','points_cost',v_reward.points_cost,'balance_after',v_balance-v_reward.points_cost,'replayed',false);
end $function$


CREATE OR REPLACE FUNCTION private.resolve_redemption(p_actor_user_id uuid, p_tenant_id uuid, p_redemption_id uuid, p_new_status text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
declare
  v_redemption public.redemptions%rowtype;
  v_reward public.rewards%rowtype;
  v_balance bigint;
begin
  if p_actor_user_id is null or p_tenant_id is null or p_redemption_id is null
     or p_new_status not in ('fulfilled','cancelled','rejected')
     or (p_new_status in ('cancelled','rejected') and length(trim(coalesce(p_reason,''))) < 5) then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;

  if not exists (
    select 1 from public.tenant_memberships m
    where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id
      and m.status='active' and m.role in ('brand_admin','super_admin')
  ) then
    return jsonb_build_object('ok',false,'error','forbidden');
  end if;

  select * into v_redemption
  from public.redemptions
  where id=p_redemption_id and tenant_id=p_tenant_id
  for update;

  if not found then
    return jsonb_build_object('ok',false,'error','redemption_not_found');
  end if;

  if v_redemption.status not in ('reserved','approved') then
    return jsonb_build_object('ok',false,'error','redemption_already_resolved','status',v_redemption.status);
  end if;

  if p_new_status='fulfilled' then
    update public.redemptions
      set status='fulfilled', fulfilled_at=now(), updated_at=now(), cancellation_reason=null
      where id=v_redemption.id;
  else
    update public.redemptions
      set status=p_new_status, updated_at=now(), cancellation_reason=trim(p_reason)
      where id=v_redemption.id;

    -- Refund exactly once because the row is locked and only reserved/approved
    -- redemptions can enter this branch.
    insert into public.points_ledger(
      tenant_id,partner_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id,metadata
    ) values (
      p_tenant_id,v_redemption.partner_id,'redeem_refund',v_redemption.points_cost,
      'redemption-refund:'||v_redemption.id::text,
      case when p_new_status='rejected' then 'reward_redemption_rejected_refund' else 'reward_redemption_cancelled_refund' end,
      p_actor_user_id,
      jsonb_build_object('redemption_id',v_redemption.id,'reward_id',v_redemption.reward_id,'reason',trim(p_reason))
    );

    select * into v_reward from public.rewards
      where id=v_redemption.reward_id and tenant_id=p_tenant_id for update;
    if found and v_reward.stock_quantity is not null then
      update public.rewards set stock_quantity=stock_quantity+1,updated_at=now()
        where id=v_reward.id;
    end if;
  end if;

  select coalesce(sum(points_delta),0) into v_balance
    from public.points_ledger
    where tenant_id=p_tenant_id and partner_id=v_redemption.partner_id;

  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  values(
    p_tenant_id,p_actor_user_id,
    case when p_new_status='fulfilled' then 'redemption_fulfilled'
         when p_new_status='rejected' then 'redemption_rejected_refunded'
         else 'redemption_cancelled_refunded' end,
    'redemption',v_redemption.id,nullif(trim(coalesce(p_reason,'')),''),
    jsonb_build_object('status',v_redemption.status),
    jsonb_build_object('status',p_new_status,'points_refunded',case when p_new_status='fulfilled' then 0 else v_redemption.points_cost end)
  );

  return jsonb_build_object(
    'ok',true,'redemption_id',v_redemption.id,'status',p_new_status,
    'points_refunded',case when p_new_status='fulfilled' then 0 else v_redemption.points_cost end,
    'balance_after',v_balance
  );
end
$function$;
CREATE OR REPLACE FUNCTION private.revoke_qr_batch(p_actor_user_id uuid, p_tenant_id uuid, p_batch_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
declare v_revoked integer;
begin
 if p_actor_user_id is null or p_tenant_id is null or p_batch_id is null or length(trim(coalesce(p_reason,'')))<5 then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
 if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
 perform 1 from public.qr_issuance_batches b where b.id=p_batch_id and b.tenant_id=p_tenant_id for update;
 if not found then return jsonb_build_object('ok',false,'error','batch_not_found'); end if;
 update public.qr_codes set status='revoked',revoked_at=now() where issuance_batch_id=p_batch_id and tenant_id=p_tenant_id and status in ('created','active');
 get diagnostics v_revoked=row_count;
 update public.qr_issuance_batches set status='revoked' where id=p_batch_id and tenant_id=p_tenant_id;
 insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,after_data) values(p_tenant_id,p_actor_user_id,'qr_batch_revoked','qr_issuance_batch',p_batch_id,trim(p_reason),jsonb_build_object('unclaimed_codes_revoked',v_revoked));
 return jsonb_build_object('ok',true,'batch_id',p_batch_id,'unclaimed_codes_revoked',v_revoked);
end $function$


CREATE OR REPLACE FUNCTION private.set_rewardloop_campaign_status(p_actor_user_id uuid, p_tenant_id uuid, p_campaign_id uuid, p_new_status text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
declare v_campaign public.campaigns%rowtype;
begin
  if p_actor_user_id is null or p_tenant_id is null or p_campaign_id is null or p_new_status not in ('active','paused','archived') or (p_new_status in ('paused','archived') and length(trim(coalesce(p_reason,'')))<5) then return jsonb_build_object('ok',false,'error','invalid_campaign_status_request'); end if;
  if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
  select * into v_campaign from public.campaigns where id=p_campaign_id and tenant_id=p_tenant_id for update;
  if not found then return jsonb_build_object('ok',false,'error','campaign_not_found'); end if;
  if v_campaign.status in ('ended','archived') then return jsonb_build_object('ok',false,'error','campaign_terminal_state'); end if;
  if p_new_status='active' then
    if v_campaign.rules->>'demo'='true' then return jsonb_build_object('ok',false,'error','demo_campaign_not_activatable'); end if;
    if v_campaign.status not in ('draft','scheduled','paused') then return jsonb_build_object('ok',false,'error','invalid_campaign_transition'); end if;
    if v_campaign.starts_at is not null and v_campaign.starts_at>now() then return jsonb_build_object('ok',false,'error','campaign_not_started'); end if;
    if v_campaign.ends_at is not null and v_campaign.ends_at<=now() then return jsonb_build_object('ok',false,'error','campaign_expired'); end if;
    if not exists(select 1 from public.products p where p.tenant_id=p_tenant_id and p.active) then return jsonb_build_object('ok',false,'error','active_product_required'); end if;
  elsif p_new_status='paused' then
    if v_campaign.status not in ('active','scheduled','draft') then return jsonb_build_object('ok',false,'error','invalid_campaign_transition'); end if;
  elsif p_new_status='archived' then
    if v_campaign.status not in ('paused','draft','ended') then return jsonb_build_object('ok',false,'error','pause_campaign_before_archive'); end if;
  end if;
  update public.campaigns set status=p_new_status::public.campaign_status,updated_at=now() where id=v_campaign.id;
  insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  values(p_tenant_id,p_actor_user_id,'campaign_status_changed','campaign',v_campaign.id,nullif(trim(coalesce(p_reason,'')),''),jsonb_build_object('status',v_campaign.status),jsonb_build_object('status',p_new_status));
  return jsonb_build_object('ok',true,'campaign_id',v_campaign.id,'status',p_new_status);
end $function$


CREATE OR REPLACE FUNCTION private.verify_partner(p_actor_user_id uuid, p_tenant_id uuid, p_partner_id uuid, p_new_status text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
declare v_partner public.partners%rowtype;
begin
 if p_actor_user_id is null or p_tenant_id is null or p_partner_id is null or p_new_status not in ('verified','rejected','suspended') then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
 if p_new_status in ('rejected','suspended') and length(trim(coalesce(p_reason,'')))<5 then return jsonb_build_object('ok',false,'error','reason_required'); end if;
 if not exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_actor_user_id and m.status='active' and m.role in ('brand_admin','super_admin')) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
 select p.* into v_partner from public.partners p where p.id=p_partner_id and p.tenant_id=p_tenant_id for update;
 if not found then return jsonb_build_object('ok',false,'error','partner_not_found'); end if;
 update public.partners set verification_status=p_new_status,updated_at=now() where id=v_partner.id;
 insert into public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
 values(p_tenant_id,p_actor_user_id,'partner_verification_changed','partner',v_partner.id,nullif(trim(coalesce(p_reason,'')),''),jsonb_build_object('verification_status',v_partner.verification_status),jsonb_build_object('verification_status',p_new_status));
 return jsonb_build_object('ok',true,'partner_id',v_partner.id,'verification_status',p_new_status);
end $function$


CREATE OR REPLACE FUNCTION public.rewardloop_claim_qr_internal(p_actor_user_id uuid, p_token text, p_request_id uuid, p_app_version text DEFAULT NULL::text, p_device_ref_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$ select private.claim_qr(p_actor_user_id,p_token,p_request_id,p_app_version,p_device_ref_hash); $function$


CREATE OR REPLACE FUNCTION public.rewardloop_create_campaign_internal(p_actor_user_id uuid, p_tenant_id uuid, p_name text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_budget_minor_units bigint)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$ select private.create_rewardloop_campaign(p_actor_user_id,p_tenant_id,p_name,p_starts_at,p_ends_at,p_budget_minor_units); $function$


CREATE OR REPLACE FUNCTION public.rewardloop_issue_qr_batch_internal(p_actor_user_id uuid, p_tenant_id uuid, p_campaign_id uuid, p_product_id uuid, p_count integer, p_points_value integer, p_entitlement_role text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$ select private.issue_qr_batch(p_actor_user_id,p_tenant_id,p_campaign_id,p_product_id,p_count,p_points_value,p_entitlement_role); $function$


CREATE OR REPLACE FUNCTION public.rewardloop_redeem_internal(p_actor_user_id uuid, p_reward_id uuid, p_request_key text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$ select private.redeem_reward(p_actor_user_id,p_reward_id,p_request_key); $function$


CREATE OR REPLACE FUNCTION public.rewardloop_resolve_redemption_internal(p_actor_user_id uuid, p_tenant_id uuid, p_redemption_id uuid, p_new_status text, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
  select private.resolve_redemption(p_actor_user_id,p_tenant_id,p_redemption_id,p_new_status,p_reason);
$function$;
CREATE OR REPLACE FUNCTION public.rewardloop_revoke_qr_batch_internal(p_actor_user_id uuid, p_tenant_id uuid, p_batch_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$ select private.revoke_qr_batch(p_actor_user_id,p_tenant_id,p_batch_id,p_reason); $function$


CREATE OR REPLACE FUNCTION public.rewardloop_set_campaign_status_internal(p_actor_user_id uuid, p_tenant_id uuid, p_campaign_id uuid, p_new_status text, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$ select private.set_rewardloop_campaign_status(p_actor_user_id,p_tenant_id,p_campaign_id,p_new_status,p_reason); $function$


CREATE OR REPLACE FUNCTION public.rewardloop_verify_partner_internal(p_actor_user_id uuid, p_tenant_id uuid, p_partner_id uuid, p_new_status text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$ select private.verify_partner(p_actor_user_id,p_tenant_id,p_partner_id,p_new_status,p_reason); $function$


ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.claims ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.points_ledger ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.production_batches ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.qr_codes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.qr_issuance_batches ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.redemptions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.rewardloop_admin_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.rewards ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.scan_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tenant_memberships ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "deny client access to audit logs" ON public.audit_logs AS PERMISSIVE FOR ALL TO anon, authenticated
 USING (false)
 WITH CHECK (false);

CREATE POLICY "active campaigns are readable" ON public.campaigns AS PERMISSIVE FOR SELECT TO anon, authenticated
 USING (((status = 'active'::campaign_status) AND ((starts_at IS NULL) OR (starts_at <= now())) AND ((ends_at IS NULL) OR (ends_at > now())) AND (EXISTS ( SELECT 1
   FROM tenants t
  WHERE ((t.id = campaigns.tenant_id) AND (t.status = 'active'::text))))));

CREATE POLICY "partner reads own claims" ON public.claims AS PERMISSIVE FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM partners p
  WHERE ((p.id = claims.partner_id) AND (p.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "partner reads own profile" ON public.partners AS PERMISSIVE FOR SELECT TO authenticated
 USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "partner reads own points ledger" ON public.points_ledger AS PERMISSIVE FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM partners p
  WHERE ((p.id = points_ledger.partner_id) AND (p.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "deny client access to production batches" ON public.production_batches AS PERMISSIVE FOR ALL TO anon, authenticated
 USING (false)
 WITH CHECK (false);

CREATE POLICY "active products are readable" ON public.products AS PERMISSIVE FOR SELECT TO anon, authenticated
 USING ((active AND (EXISTS ( SELECT 1
   FROM tenants t
  WHERE ((t.id = products.tenant_id) AND (t.status = 'active'::text))))));

CREATE POLICY "deny client access to QR codes" ON public.qr_codes AS PERMISSIVE FOR ALL TO anon, authenticated
 USING (false)
 WITH CHECK (false);

CREATE POLICY "deny client access to QR issuance batches" ON public.qr_issuance_batches AS PERMISSIVE FOR ALL TO anon, authenticated
 USING (false)
 WITH CHECK (false);

CREATE POLICY "partner reads own redemptions" ON public.redemptions AS PERMISSIVE FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM partners p
  WHERE ((p.id = redemptions.partner_id) AND (p.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "active rewards are readable" ON public.rewards AS PERMISSIVE FOR SELECT TO anon, authenticated
 USING ((active AND (EXISTS ( SELECT 1
   FROM tenants t
  WHERE ((t.id = rewards.tenant_id) AND (t.status = 'active'::text))))));

CREATE POLICY "deny client access to scan events" ON public.scan_events AS PERMISSIVE FOR ALL TO anon, authenticated
 USING (false)
 WITH CHECK (false);

CREATE POLICY "users read own tenant memberships" ON public.tenant_memberships AS PERMISSIVE FOR SELECT TO authenticated
 USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "active tenants are discoverable" ON public.tenants AS PERMISSIVE FOR SELECT TO anon, authenticated
 USING ((status = 'active'::text));

COMMENT ON TABLE public.claims IS 'Authoritative claim outcome. Claim + ledger credit must be committed atomically by a trusted server-side transaction.';

COMMENT ON TABLE public.points_ledger IS 'Append-only points accounting. Do not update/delete posted entries; use compensating entries.';

COMMENT ON TABLE public.qr_codes IS 'Store only a hash of high-entropy QR tokens where feasible; raw claim secrets must not be logged.';

COMMENT ON TABLE public.scan_events IS 'Append-only scan attempts, including failures and duplicates. Avoid storing raw QR tokens or unnecessary precise location.';

REVOKE ALL PRIVILEGES ON FUNCTION private.claim_qr(uuid, text, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.create_rewardloop_campaign(uuid, uuid, text, timestamp with time zone, timestamp with time zone, bigint) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.issue_qr_batch(uuid, uuid, uuid, uuid, integer, integer, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.redeem_reward(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.resolve_redemption(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.revoke_qr_batch(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.set_rewardloop_campaign_status(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.verify_partner(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_claim_qr_internal(uuid, text, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_create_campaign_internal(uuid, uuid, text, timestamp with time zone, timestamp with time zone, bigint) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_issue_qr_batch_internal(uuid, uuid, uuid, uuid, integer, integer, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_redeem_internal(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_resolve_redemption_internal(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_revoke_qr_batch_internal(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_set_campaign_status_internal(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_verify_partner_internal(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION private.claim_qr(uuid, text, uuid, text, text) TO service_role;

GRANT EXECUTE ON FUNCTION private.create_rewardloop_campaign(uuid, uuid, text, timestamp with time zone, timestamp with time zone, bigint) TO PUBLIC;

GRANT EXECUTE ON FUNCTION private.issue_qr_batch(uuid, uuid, uuid, uuid, integer, integer, text) TO service_role;

GRANT EXECUTE ON FUNCTION private.redeem_reward(uuid, uuid, text) TO service_role;

GRANT EXECUTE ON FUNCTION private.resolve_redemption(uuid, uuid, uuid, text, text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION private.revoke_qr_batch(uuid, uuid, uuid, text) TO service_role;

GRANT EXECUTE ON FUNCTION private.set_rewardloop_campaign_status(uuid, uuid, uuid, text, text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION private.verify_partner(uuid, uuid, uuid, text, text) TO service_role;

GRANT EXECUTE ON FUNCTION public.rewardloop_claim_qr_internal(uuid, text, uuid, text, text) TO service_role;

GRANT EXECUTE ON FUNCTION public.rewardloop_create_campaign_internal(uuid, uuid, text, timestamp with time zone, timestamp with time zone, bigint) TO service_role;

GRANT EXECUTE ON FUNCTION public.rewardloop_issue_qr_batch_internal(uuid, uuid, uuid, uuid, integer, integer, text) TO service_role;

GRANT EXECUTE ON FUNCTION public.rewardloop_redeem_internal(uuid, uuid, text) TO service_role;

GRANT EXECUTE ON FUNCTION public.rewardloop_resolve_redemption_internal(uuid, uuid, uuid, text, text) TO service_role;

GRANT EXECUTE ON FUNCTION public.rewardloop_revoke_qr_batch_internal(uuid, uuid, uuid, text) TO service_role;

GRANT EXECUTE ON FUNCTION public.rewardloop_set_campaign_status_internal(uuid, uuid, uuid, text, text) TO service_role;

GRANT EXECUTE ON FUNCTION public.rewardloop_verify_partner_internal(uuid, uuid, uuid, text, text) TO service_role;

REVOKE ALL PRIVILEGES ON TABLE public.audit_logs FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.campaigns FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.claims FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.partners FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.points_ledger FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.production_batches FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.products FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.qr_codes FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.qr_issuance_batches FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.redemptions FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.rewardloop_admin_settings FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.rewards FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.scan_events FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.tenant_memberships FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON TABLE public.tenants FROM PUBLIC, anon, authenticated, service_role;

GRANT DELETE ON TABLE public.audit_logs TO service_role;

GRANT INSERT ON TABLE public.audit_logs TO service_role;

GRANT MAINTAIN ON TABLE public.audit_logs TO service_role;

GRANT REFERENCES ON TABLE public.audit_logs TO service_role;

GRANT SELECT ON TABLE public.audit_logs TO service_role;

GRANT TRIGGER ON TABLE public.audit_logs TO service_role;

GRANT TRUNCATE ON TABLE public.audit_logs TO service_role;

GRANT UPDATE ON TABLE public.audit_logs TO service_role;

GRANT SELECT ON TABLE public.campaigns TO anon;

GRANT SELECT ON TABLE public.campaigns TO authenticated;

GRANT DELETE ON TABLE public.campaigns TO service_role;

GRANT INSERT ON TABLE public.campaigns TO service_role;

GRANT MAINTAIN ON TABLE public.campaigns TO service_role;

GRANT REFERENCES ON TABLE public.campaigns TO service_role;

GRANT SELECT ON TABLE public.campaigns TO service_role;

GRANT TRIGGER ON TABLE public.campaigns TO service_role;

GRANT TRUNCATE ON TABLE public.campaigns TO service_role;

GRANT UPDATE ON TABLE public.campaigns TO service_role;

GRANT SELECT ON TABLE public.claims TO authenticated;

GRANT DELETE ON TABLE public.claims TO service_role;

GRANT INSERT ON TABLE public.claims TO service_role;

GRANT MAINTAIN ON TABLE public.claims TO service_role;

GRANT REFERENCES ON TABLE public.claims TO service_role;

GRANT SELECT ON TABLE public.claims TO service_role;

GRANT TRIGGER ON TABLE public.claims TO service_role;

GRANT TRUNCATE ON TABLE public.claims TO service_role;

GRANT UPDATE ON TABLE public.claims TO service_role;

GRANT SELECT ON TABLE public.partners TO authenticated;

GRANT DELETE ON TABLE public.partners TO service_role;

GRANT INSERT ON TABLE public.partners TO service_role;

GRANT MAINTAIN ON TABLE public.partners TO service_role;

GRANT REFERENCES ON TABLE public.partners TO service_role;

GRANT SELECT ON TABLE public.partners TO service_role;

GRANT TRIGGER ON TABLE public.partners TO service_role;

GRANT TRUNCATE ON TABLE public.partners TO service_role;

GRANT UPDATE ON TABLE public.partners TO service_role;

GRANT SELECT ON TABLE public.points_ledger TO authenticated;

GRANT DELETE ON TABLE public.points_ledger TO service_role;

GRANT INSERT ON TABLE public.points_ledger TO service_role;

GRANT MAINTAIN ON TABLE public.points_ledger TO service_role;

GRANT REFERENCES ON TABLE public.points_ledger TO service_role;

GRANT SELECT ON TABLE public.points_ledger TO service_role;

GRANT TRIGGER ON TABLE public.points_ledger TO service_role;

GRANT TRUNCATE ON TABLE public.points_ledger TO service_role;

GRANT UPDATE ON TABLE public.points_ledger TO service_role;

GRANT DELETE ON TABLE public.production_batches TO service_role;

GRANT INSERT ON TABLE public.production_batches TO service_role;

GRANT MAINTAIN ON TABLE public.production_batches TO service_role;

GRANT REFERENCES ON TABLE public.production_batches TO service_role;

GRANT SELECT ON TABLE public.production_batches TO service_role;

GRANT TRIGGER ON TABLE public.production_batches TO service_role;

GRANT TRUNCATE ON TABLE public.production_batches TO service_role;

GRANT UPDATE ON TABLE public.production_batches TO service_role;

GRANT SELECT ON TABLE public.products TO anon;

GRANT SELECT ON TABLE public.products TO authenticated;

GRANT DELETE ON TABLE public.products TO service_role;

GRANT INSERT ON TABLE public.products TO service_role;

GRANT MAINTAIN ON TABLE public.products TO service_role;

GRANT REFERENCES ON TABLE public.products TO service_role;

GRANT SELECT ON TABLE public.products TO service_role;

GRANT TRIGGER ON TABLE public.products TO service_role;

GRANT TRUNCATE ON TABLE public.products TO service_role;

GRANT UPDATE ON TABLE public.products TO service_role;

GRANT DELETE ON TABLE public.qr_codes TO service_role;

GRANT INSERT ON TABLE public.qr_codes TO service_role;

GRANT MAINTAIN ON TABLE public.qr_codes TO service_role;

GRANT REFERENCES ON TABLE public.qr_codes TO service_role;

GRANT SELECT ON TABLE public.qr_codes TO service_role;

GRANT TRIGGER ON TABLE public.qr_codes TO service_role;

GRANT TRUNCATE ON TABLE public.qr_codes TO service_role;

GRANT UPDATE ON TABLE public.qr_codes TO service_role;

GRANT DELETE ON TABLE public.qr_issuance_batches TO service_role;

GRANT INSERT ON TABLE public.qr_issuance_batches TO service_role;

GRANT MAINTAIN ON TABLE public.qr_issuance_batches TO service_role;

GRANT REFERENCES ON TABLE public.qr_issuance_batches TO service_role;

GRANT SELECT ON TABLE public.qr_issuance_batches TO service_role;

GRANT TRIGGER ON TABLE public.qr_issuance_batches TO service_role;

GRANT TRUNCATE ON TABLE public.qr_issuance_batches TO service_role;

GRANT UPDATE ON TABLE public.qr_issuance_batches TO service_role;

GRANT MAINTAIN ON TABLE public.redemptions TO anon;

GRANT REFERENCES ON TABLE public.redemptions TO anon;

GRANT SELECT ON TABLE public.redemptions TO anon;

GRANT TRIGGER ON TABLE public.redemptions TO anon;

GRANT TRUNCATE ON TABLE public.redemptions TO anon;

GRANT MAINTAIN ON TABLE public.redemptions TO authenticated;

GRANT REFERENCES ON TABLE public.redemptions TO authenticated;

GRANT SELECT ON TABLE public.redemptions TO authenticated;

GRANT TRIGGER ON TABLE public.redemptions TO authenticated;

GRANT TRUNCATE ON TABLE public.redemptions TO authenticated;

GRANT DELETE ON TABLE public.redemptions TO service_role;

GRANT INSERT ON TABLE public.redemptions TO service_role;

GRANT MAINTAIN ON TABLE public.redemptions TO service_role;

GRANT REFERENCES ON TABLE public.redemptions TO service_role;

GRANT SELECT ON TABLE public.redemptions TO service_role;

GRANT TRIGGER ON TABLE public.redemptions TO service_role;

GRANT TRUNCATE ON TABLE public.redemptions TO service_role;

GRANT UPDATE ON TABLE public.redemptions TO service_role;

GRANT DELETE ON TABLE public.rewardloop_admin_settings TO service_role;

GRANT INSERT ON TABLE public.rewardloop_admin_settings TO service_role;

GRANT MAINTAIN ON TABLE public.rewardloop_admin_settings TO service_role;

GRANT REFERENCES ON TABLE public.rewardloop_admin_settings TO service_role;

GRANT SELECT ON TABLE public.rewardloop_admin_settings TO service_role;

GRANT TRIGGER ON TABLE public.rewardloop_admin_settings TO service_role;

GRANT TRUNCATE ON TABLE public.rewardloop_admin_settings TO service_role;

GRANT UPDATE ON TABLE public.rewardloop_admin_settings TO service_role;

GRANT MAINTAIN ON TABLE public.rewards TO anon;

GRANT REFERENCES ON TABLE public.rewards TO anon;

GRANT SELECT ON TABLE public.rewards TO anon;

GRANT TRIGGER ON TABLE public.rewards TO anon;

GRANT TRUNCATE ON TABLE public.rewards TO anon;

GRANT MAINTAIN ON TABLE public.rewards TO authenticated;

GRANT REFERENCES ON TABLE public.rewards TO authenticated;

GRANT SELECT ON TABLE public.rewards TO authenticated;

GRANT TRIGGER ON TABLE public.rewards TO authenticated;

GRANT TRUNCATE ON TABLE public.rewards TO authenticated;

GRANT DELETE ON TABLE public.rewards TO service_role;

GRANT INSERT ON TABLE public.rewards TO service_role;

GRANT MAINTAIN ON TABLE public.rewards TO service_role;

GRANT REFERENCES ON TABLE public.rewards TO service_role;

GRANT SELECT ON TABLE public.rewards TO service_role;

GRANT TRIGGER ON TABLE public.rewards TO service_role;

GRANT TRUNCATE ON TABLE public.rewards TO service_role;

GRANT UPDATE ON TABLE public.rewards TO service_role;

GRANT DELETE ON TABLE public.scan_events TO service_role;

GRANT INSERT ON TABLE public.scan_events TO service_role;

GRANT MAINTAIN ON TABLE public.scan_events TO service_role;

GRANT REFERENCES ON TABLE public.scan_events TO service_role;

GRANT SELECT ON TABLE public.scan_events TO service_role;

GRANT TRIGGER ON TABLE public.scan_events TO service_role;

GRANT TRUNCATE ON TABLE public.scan_events TO service_role;

GRANT UPDATE ON TABLE public.scan_events TO service_role;

GRANT SELECT ON TABLE public.tenant_memberships TO authenticated;

GRANT DELETE ON TABLE public.tenant_memberships TO service_role;

GRANT INSERT ON TABLE public.tenant_memberships TO service_role;

GRANT MAINTAIN ON TABLE public.tenant_memberships TO service_role;

GRANT REFERENCES ON TABLE public.tenant_memberships TO service_role;

GRANT SELECT ON TABLE public.tenant_memberships TO service_role;

GRANT TRIGGER ON TABLE public.tenant_memberships TO service_role;

GRANT TRUNCATE ON TABLE public.tenant_memberships TO service_role;

GRANT UPDATE ON TABLE public.tenant_memberships TO service_role;

GRANT SELECT ON TABLE public.tenants TO anon;

GRANT SELECT ON TABLE public.tenants TO authenticated;

GRANT DELETE ON TABLE public.tenants TO service_role;

GRANT INSERT ON TABLE public.tenants TO service_role;

GRANT MAINTAIN ON TABLE public.tenants TO service_role;

GRANT REFERENCES ON TABLE public.tenants TO service_role;

GRANT SELECT ON TABLE public.tenants TO service_role;

GRANT TRIGGER ON TABLE public.tenants TO service_role;

GRANT TRUNCATE ON TABLE public.tenants TO service_role;

GRANT UPDATE ON TABLE public.tenants TO service_role;

REVOKE ALL PRIVILEGES ON SCHEMA private FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON SCHEMA public FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON SCHEMA private TO service_role;

GRANT USAGE ON SCHEMA public TO PUBLIC;

GRANT USAGE ON SCHEMA public TO anon;

GRANT USAGE ON SCHEMA public TO authenticated;

GRANT USAGE ON SCHEMA public TO service_role;
