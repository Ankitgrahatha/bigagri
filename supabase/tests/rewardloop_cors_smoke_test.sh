#!/usr/bin/env bash
# Safe, read-only smoke tests for RewardLoop API CORS/auth boundaries.
# Requires curl. Does not submit claims, redemptions, or other mutations.
set -euo pipefail

API_URL="${API_URL:-https://guhhuqxrobhuumwrypnc.supabase.co/functions/v1/rewardloop-api}"
ALLOWED_ORIGIN="${ALLOWED_ORIGIN:-https://bigagri.vercel.app}"
BLOCKED_ORIGIN="${BLOCKED_ORIGIN:-https://untrusted-origin.invalid}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Allowed production origin should receive preflight success and exact ACAO.
allowed_status="$(curl -sS -o "$tmp/allowed.body" -D "$tmp/allowed.headers" -w '%{http_code}' \
  -X OPTIONS "$API_URL" \
  -H "Origin: $ALLOWED_ORIGIN" \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization,content-type')"
if [[ "$allowed_status" != "204" ]]; then
  echo "FAIL allowed preflight: expected 204, got $allowed_status"
  exit 1
fi
if ! grep -Eiq "^Access-Control-Allow-Origin: ${ALLOWED_ORIGIN//./\\.}[[:space:]]*\r?$" "$tmp/allowed.headers"; then
  echo "FAIL allowed preflight: exact Access-Control-Allow-Origin header missing"
  exit 1
fi

# Unapproved browser origin should be rejected before business logic.
blocked_status="$(curl -sS -o "$tmp/blocked.body" -D "$tmp/blocked.headers" -w '%{http_code}' \
  -X OPTIONS "$API_URL" \
  -H "Origin: $BLOCKED_ORIGIN" \
  -H 'Access-Control-Request-Method: POST')"
if [[ "$blocked_status" != "403" ]]; then
  echo "FAIL blocked preflight: expected 403, got $blocked_status"
  exit 1
fi
if grep -Eiq '^Access-Control-Allow-Origin:[[:space:]]*\*' "$tmp/blocked.headers"; then
  echo "FAIL blocked origin received wildcard CORS"
  exit 1
fi

# POST with no bearer token must be rejected. No action or payload is supplied.
unauth_status="$(curl -sS -o "$tmp/unauth.body" -w '%{http_code}' \
  -X POST "$API_URL" \
  -H "Origin: $ALLOWED_ORIGIN" \
  -H 'Content-Type: application/json' \
  --data '{}')"
if [[ "$unauth_status" != "401" ]]; then
  echo "FAIL unauthenticated POST: expected 401, got $unauth_status"
  exit 1
fi

echo "PASS: allowed preflight, blocked-origin preflight, and missing-token rejection."
