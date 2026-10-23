-- Provider payment attempts are separate from the RewardLoop points ledger,
-- campaign liability ledger, and partner settlement accounting.
CREATE TABLE private.saas_payment_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  subscription_id uuid REFERENCES private.saas_tenant_subscriptions(id) ON DELETE RESTRICT,
  provider text NOT NULL DEFAULT 'razorpay' CHECK (provider = 'razorpay'),
  idempotency_key text NOT NULL
    CHECK (length(btrim(idempotency_key)) BETWEEN 8 AND 255),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  provider_order_id text
    CHECK (provider_order_id IS NULL OR length(btrim(provider_order_id)) BETWEEN 1 AND 255),
  provider_payment_id text
    CHECK (provider_payment_id IS NULL OR length(btrim(provider_payment_id)) BETWEEN 1 AND 255),
  status text NOT NULL DEFAULT 'initiated'
    CHECK (status IN ('initiated', 'authorized', 'captured', 'failed', 'refunded', 'partially_refunded')),
  failure_code text CHECK (failure_code IS NULL OR length(failure_code) <= 120),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  authorized_at timestamptz,
  captured_at timestamptz,
  refunded_at timestamptz,
  CONSTRAINT saas_payment_attempts_tenant_idempotency_unique
    UNIQUE (tenant_id, provider, idempotency_key),
  CONSTRAINT saas_payment_attempts_captured_timestamp_check
    CHECK ((status = 'captured' AND captured_at IS NOT NULL) OR status <> 'captured'),
  CONSTRAINT saas_payment_attempts_failed_code_check
    CHECK (status <> 'failed' OR failure_code IS NOT NULL),
  CONSTRAINT saas_payment_attempts_refund_timestamp_check
    CHECK (
      (status IN ('refunded', 'partially_refunded') AND refunded_at IS NOT NULL)
      OR status NOT IN ('refunded', 'partially_refunded')
    )
);

CREATE UNIQUE INDEX saas_payment_attempts_provider_order_idx
  ON private.saas_payment_attempts (provider, provider_order_id)
  WHERE provider_order_id IS NOT NULL;

CREATE UNIQUE INDEX saas_payment_attempts_provider_payment_idx
  ON private.saas_payment_attempts (provider, provider_payment_id)
  WHERE provider_payment_id IS NOT NULL;

CREATE INDEX saas_payment_attempts_tenant_history_idx
  ON private.saas_payment_attempts (tenant_id, created_at DESC);

CREATE INDEX saas_payment_attempts_subscription_history_idx
  ON private.saas_payment_attempts (subscription_id, created_at DESC)
  WHERE subscription_id IS NOT NULL;

ALTER TABLE private.saas_payment_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.saas_payment_attempts FORCE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE private.saas_payment_attempts
  FROM PUBLIC, anon, authenticated;
GRANT ALL PRIVILEGES ON TABLE private.saas_payment_attempts TO service_role;
