-- Keep the points ledger immutable after posting.
-- Corrections must be appended as compensating entries; never rewrite history.
-- Applies no data changes and does not alter points balances.

CREATE OR REPLACE FUNCTION private.guard_points_ledger_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'points_ledger is append-only; create a compensating entry instead';
  RETURN NULL;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION private.guard_points_ledger_append_only()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS points_ledger_append_only ON public.points_ledger;

CREATE TRIGGER points_ledger_append_only
  BEFORE UPDATE OR DELETE OR TRUNCATE ON public.points_ledger
  FOR EACH STATEMENT
  EXECUTE FUNCTION private.guard_points_ledger_append_only();
