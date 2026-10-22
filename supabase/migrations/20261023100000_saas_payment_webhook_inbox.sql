-- Durable, private inbox for verified Razorpay webhook deliveries.
-- A receipt is not a subscription state change: a processor must apply verified
-- events idempotently and transactionally before marking them processed.
CREATE TABLE private.saas_payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL CHECK (provider = 'razorpay'),
  provider_event_id text NOT NULL
    CHECK (length(btrim(provider_event_id)) BETWEEN 1 AND 255),
  event_type text NOT NULL
    CHECK (length(btrim(event_type)) BETWEEN 1 AND 160),
  payload jsonb NOT NULL
    CHECK (jsonb_typeof(payload) = 'object'),
  signature_verified_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'received'
    CHECK (status IN ('received', 'processing', 'processed', 'failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  received_at timestamptz NOT NULL DEFAULT now(),
  processing_started_at timestamptz,
  processed_at timestamptz,
  last_error_code text
    CHECK (last_error_code IS NULL OR length(last_error_code) <= 120),
  CONSTRAINT saas_payment_webhook_events_provider_event_unique
    UNIQUE (provider, provider_event_id),
  CONSTRAINT saas_payment_webhook_events_processed_state_check
    CHECK (
      (status = 'processed' AND processed_at IS NOT NULL)
      OR (status <> 'processed' AND processed_at IS NULL)
    )
);

CREATE INDEX saas_payment_webhook_events_pending_idx
  ON private.saas_payment_webhook_events (received_at, id)
  WHERE status IN ('received', 'failed');

CREATE INDEX saas_payment_webhook_events_processing_idx
  ON private.saas_payment_webhook_events (processing_started_at)
  WHERE status = 'processing';

ALTER TABLE private.saas_payment_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.saas_payment_webhook_events FORCE ROW LEVEL SECURITY;

-- This inbox contains provider payloads and is not a client-facing data surface.
-- No client policies are created; application access is service-role only.
REVOKE ALL PRIVILEGES ON TABLE private.saas_payment_webhook_events
  FROM PUBLIC, anon, authenticated;
GRANT ALL PRIVILEGES ON TABLE private.saas_payment_webhook_events TO service_role;
