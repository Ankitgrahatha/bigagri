-- Fail-closed validation test for redemption resolution; disposable database only.
BEGIN;
DO $redemption_invalid_status_test$
DECLARE
  v_result jsonb;
BEGIN
  v_result := private.resolve_redemption(
    '00000000-0000-4000-8000-00000000a202',
    '00000000-0000-4000-8000-00000000a101',
    '00000000-0000-4000-8000-00000000a501',
    NULL,
    'invalid status test'
  );
  IF v_result->>'ok' <> 'false' OR v_result->>'error' <> 'invalid_request' THEN
    RAISE EXCEPTION 'NULL redemption status did not fail closed: %',v_result;
  END IF;
END;
$redemption_invalid_status_test$;
ROLLBACK;
