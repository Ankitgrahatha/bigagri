-- Aggregate-only operational health for the private Razorpay webhook inbox.
-- This endpoint returns counts/age only; provider payloads and customer data never leave the private schema.
CREATE OR REPLACE FUNCTION private.get_saas_payment_webhook_health()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT jsonb_build_object(
    'ok', true,
    'received', count(*) FILTER (WHERE status = 'received'),
    'retryable_failed', count(*) FILTER (WHERE status = 'failed' AND attempts < 8),
    'exhausted', count(*) FILTER (WHERE status = 'failed' AND attempts >= 8),
    'stale_processing', count(*) FILTER (
      WHERE status = 'processing'
        AND (processing_started_at IS NULL OR processing_started_at < now() - interval '10 minutes')
    ),
    'oldest_unprocessed_age_seconds',
      COALESCE(floor(extract(epoch FROM (now() - min(received_at))))::bigint, 0)
  )
  FROM private.saas_payment_webhook_events
  WHERE status <> 'processed';
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.get_saas_payment_webhook_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.get_saas_payment_webhook_health() TO service_role;

CREATE OR REPLACE FUNCTION public.get_saas_payment_webhook_health_internal()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.get_saas_payment_webhook_health();
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.get_saas_payment_webhook_health_internal()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_saas_payment_webhook_health_internal() TO service_role;
