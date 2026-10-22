-- Unknown QR token brute-force guard; disposable PostgreSQL only.
BEGIN;
DO $claim_invalid_rate_limit_test$
DECLARE
  v_actor constant uuid := '00000000-0000-4000-8000-00000000b101';
  v_result jsonb;
  i integer;
BEGIN
  INSERT INTO auth.users(id) VALUES(v_actor);

  FOR i IN 1..10 LOOP
    v_result := private.claim_qr(
      v_actor,
      'invalid-qr-token-guess-' || lpad(i::text,2,'0'),
      gen_random_uuid(),
      'rate-limit-test',
      NULL
    );
    IF v_result->>'outcome' <> 'invalid_code' THEN
      RAISE EXCEPTION 'invalid attempt % unexpectedly returned: %',i,v_result;
    END IF;
  END LOOP;

  v_result := private.claim_qr(
    v_actor,
    'invalid-qr-token-guess-11',
    gen_random_uuid(),
    'rate-limit-test',
    NULL
  );
  IF v_result->>'outcome' <> 'rate_limited'
     OR v_result->>'retry_after_seconds' <> '900'
     OR v_result->>'points_awarded' <> '0' THEN
    RAISE EXCEPTION '11th invalid attempt was not rate limited: %',v_result;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='private' AND table_name='claim_failed_attempts'
       AND column_name IN ('token','raw_token','token_value')
  ) THEN
    RAISE EXCEPTION 'rate-limit table must not store raw QR token values';
  END IF;

  IF (SELECT count(*) FROM private.claim_failed_attempts WHERE actor_user_id=v_actor) <> 10 THEN
    RAISE EXCEPTION 'expected exactly ten logged failed attempts';
  END IF;

  RAISE NOTICE 'PASS: 10 failed token guesses logged, 11th rate-limited, no raw token stored';
END;
$claim_invalid_rate_limit_test$;
ROLLBACK;
