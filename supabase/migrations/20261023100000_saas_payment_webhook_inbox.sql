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
  last_attempt_at timestamptz,
  processed_at timestamptz,
  processing_result text CHECK (processing_result IS NULL OR processing_result IN ('applied', 'ignored', 'stale')),
  last_error_code text
    CHECK (last_error_code IS NULL OR length(last_error_code) <= 120),
  CONSTRAINT saas_payment_webhook_events_provider_event_unique
    UNIQUE (provider, provider_event_id),
  CONSTRAINT saas_payment_webhook_events_processed_state_check
    CHECK (
      (status = 'processed' AND processed_at IS NOT NULL AND processing_result IS NOT NULL)
      OR (status <> 'processed' AND processed_at IS NULL AND processing_result IS NULL)
    )
);

CREATE INDEX saas_payment_webhook_events_pending_idx
  ON private.saas_payment_webhook_events (status, last_attempt_at, received_at, id)
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

-- The Edge Function uses this narrow RPC because the private schema is not exposed
-- through PostgREST. The RPC records receipts only; it never activates entitlements.
CREATE OR REPLACE FUNCTION private.record_saas_payment_webhook_event(
  p_provider_event_id text,
  p_event_type text,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_inserted integer;
BEGIN
  IF p_provider_event_id IS NULL
     OR length(btrim(p_provider_event_id)) NOT BETWEEN 1 AND 255
     OR p_event_type IS NULL
     OR length(btrim(p_event_type)) NOT BETWEEN 1 AND 160
     OR p_payload IS NULL
     OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_event');
  END IF;

  INSERT INTO private.saas_payment_webhook_events (
    provider, provider_event_id, event_type, payload, signature_verified_at
  )
  VALUES (
    'razorpay', btrim(p_provider_event_id), btrim(p_event_type), p_payload, now()
  )
  ON CONFLICT (provider, provider_event_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'duplicate', v_inserted = 0);
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.record_saas_payment_webhook_event(text,text,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.record_saas_payment_webhook_event(text,text,jsonb)
  TO service_role;

CREATE OR REPLACE FUNCTION public.record_saas_payment_webhook_event_internal(
  p_provider_event_id text,
  p_event_type text,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.record_saas_payment_webhook_event(
    p_provider_event_id, p_event_type, p_payload
  );
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.record_saas_payment_webhook_event_internal(text,text,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_saas_payment_webhook_event_internal(text,text,jsonb)
  TO service_role;
