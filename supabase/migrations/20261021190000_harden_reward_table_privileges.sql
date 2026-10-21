-- Reduce client-role privileges on reward-bearing tables.
-- RLS filters rows for SELECT, but does not apply to TRUNCATE and does not replace
-- least-privilege table grants. These are read-only client surfaces; all writes are
-- routed through authenticated server functions and constrained transactional RPCs.

REVOKE ALL PRIVILEGES ON TABLE public.rewards, public.redemptions
  FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.rewards, public.redemptions
  TO anon, authenticated;

REVOKE ALL PRIVILEGES ON TABLE public.rewardloop_admin_settings
  FROM PUBLIC, anon, authenticated;

-- Explicitly close default PUBLIC EXECUTE on every privileged internal function.
-- Keep service_role as the only application role allowed to invoke the RPC layer.
REVOKE ALL PRIVILEGES ON FUNCTION private.claim_qr(uuid,text,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.claim_qr(uuid,text,uuid,text,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.create_rewardloop_campaign(uuid,uuid,text,timestamptz,timestamptz,bigint) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.issue_qr_batch(uuid,uuid,uuid,uuid,integer,integer,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.issue_qr_batch(uuid,uuid,uuid,uuid,integer,integer,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.redeem_reward(uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.redeem_reward(uuid,uuid,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.resolve_redemption(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.resolve_redemption(uuid,uuid,uuid,text,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.revoke_qr_batch(uuid,uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.revoke_qr_batch(uuid,uuid,uuid,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.set_rewardloop_campaign_status(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.set_rewardloop_campaign_status(uuid,uuid,uuid,text,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.verify_partner(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.verify_partner(uuid,uuid,uuid,text,text) TO service_role;

-- The public wrappers are the only intended RPC surface. Keep their grants explicit
-- as well, including wrappers that are SECURITY DEFINER for controlled internal calls.
REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_claim_qr_internal(uuid,text,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_claim_qr_internal(uuid,text,uuid,text,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_create_campaign_internal(uuid,uuid,text,timestamptz,timestamptz,bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_create_campaign_internal(uuid,uuid,text,timestamptz,timestamptz,bigint) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_issue_qr_batch_internal(uuid,uuid,uuid,uuid,integer,integer,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_issue_qr_batch_internal(uuid,uuid,uuid,uuid,integer,integer,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_redeem_internal(uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_redeem_internal(uuid,uuid,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_resolve_redemption_internal(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_resolve_redemption_internal(uuid,uuid,uuid,text,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_revoke_qr_batch_internal(uuid,uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_revoke_qr_batch_internal(uuid,uuid,uuid,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_set_campaign_status_internal(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_set_campaign_status_internal(uuid,uuid,uuid,text,text) TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION public.rewardloop_verify_partner_internal(uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rewardloop_verify_partner_internal(uuid,uuid,uuid,text,text) TO service_role;
