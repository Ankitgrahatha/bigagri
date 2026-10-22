-- SaaS subscription billing is separate from RewardLoop loyalty points and campaign budgets.
-- Plan versions become immutable once published; live subscription/payment activation
-- is intentionally handled by a later reviewed processor, not by this schema migration.

CREATE TABLE private.saas_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_key text NOT NULL UNIQUE
    CHECK (plan_key ~ '^[a-z][a-z0-9_-]{1,63}$'),
  display_name text NOT NULL
    CHECK (length(btrim(display_name)) BETWEEN 2 AND 120),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'published', 'retired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE private.saas_plan_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES private.saas_plans(id) ON DELETE RESTRICT,
  version_no integer NOT NULL CHECK (version_no > 0),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  monthly_amount_minor bigint NOT NULL CHECK (monthly_amount_minor >= 0),
  yearly_amount_minor bigint NOT NULL CHECK (yearly_amount_minor >= 0),
  trial_days integer NOT NULL DEFAULT 0 CHECK (trial_days BETWEEN 0 AND 90),
  entitlements jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(entitlements) = 'object'),
  usage_limits jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(usage_limits) = 'object'),
  published_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT saas_plan_versions_plan_version_unique UNIQUE (plan_id, version_no)
);

CREATE INDEX saas_plan_versions_published_idx
  ON private.saas_plan_versions (plan_id, published_at DESC)
  WHERE published_at IS NOT NULL;

CREATE OR REPLACE FUNCTION private.prevent_published_saas_plan_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF OLD.published_at IS NOT NULL THEN
    RAISE EXCEPTION 'published SaaS plan versions are immutable'
      USING ERRCODE = '55000';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER saas_plan_versions_immutable
  BEFORE UPDATE OR DELETE ON private.saas_plan_versions
  FOR EACH ROW
  EXECUTE FUNCTION private.prevent_published_saas_plan_version_mutation();

REVOKE ALL PRIVILEGES ON FUNCTION private.prevent_published_saas_plan_version_mutation()
  FROM PUBLIC, anon, authenticated;

CREATE TABLE private.saas_tenant_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  plan_version_id uuid NOT NULL REFERENCES private.saas_plan_versions(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'incomplete'
    CHECK (status IN ('incomplete', 'trialing', 'active', 'past_due', 'paused', 'canceled', 'expired')),
  provider text NOT NULL DEFAULT 'razorpay'
    CHECK (provider = 'razorpay'),
  provider_customer_id text CHECK (provider_customer_id IS NULL OR length(provider_customer_id) <= 255),
  provider_subscription_id text CHECK (provider_subscription_id IS NULL OR length(provider_subscription_id) <= 255),
  current_period_start timestamptz,
  current_period_end timestamptz,
  trial_end timestamptz,
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  canceled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT saas_subscription_period_order_check
    CHECK (
      current_period_start IS NULL OR current_period_end IS NULL
      OR current_period_end > current_period_start
    ),
  CONSTRAINT saas_subscription_cancel_timestamp_check
    CHECK (
      (status = 'canceled' AND canceled_at IS NOT NULL)
      OR (status <> 'canceled' AND canceled_at IS NULL)
    )
);

CREATE UNIQUE INDEX saas_tenant_subscription_one_current_idx
  ON private.saas_tenant_subscriptions (tenant_id)
  WHERE status IN ('trialing', 'active', 'past_due', 'paused');

CREATE UNIQUE INDEX saas_tenant_subscription_provider_id_idx
  ON private.saas_tenant_subscriptions (provider, provider_subscription_id)
  WHERE provider_subscription_id IS NOT NULL;

CREATE INDEX saas_tenant_subscriptions_tenant_history_idx
  ON private.saas_tenant_subscriptions (tenant_id, created_at DESC);

ALTER TABLE private.saas_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.saas_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE private.saas_plan_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.saas_plan_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE private.saas_tenant_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.saas_tenant_subscriptions FORCE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  private.saas_plans,
  private.saas_plan_versions,
  private.saas_tenant_subscriptions
  FROM PUBLIC, anon, authenticated;
GRANT ALL PRIVILEGES ON TABLE
  private.saas_plans,
  private.saas_plan_versions,
  private.saas_tenant_subscriptions
  TO service_role;
