-- Fix refund writes to use the existing ledger_entry_type enum value.
-- The enum contains redeem_release, not redeem_refund. Without this fix, cancel/reject
-- can fail while inserting the compensation entry and will roll back the whole operation.

CREATE OR REPLACE FUNCTION private.resolve_redemption(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_redemption_id uuid,
  p_new_status text,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'extensions', 'public', 'private'
AS $function$
DECLARE
  v_redemption public.redemptions%rowtype;
  v_reward public.rewards%rowtype;
  v_balance bigint;
BEGIN
  IF p_actor_user_id IS NULL OR p_tenant_id IS NULL OR p_redemption_id IS NULL
     OR p_new_status NOT IN ('fulfilled','cancelled','rejected')
     OR (p_new_status IN ('cancelled','rejected') AND length(trim(coalesce(p_reason,''))) < 5) THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_request');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=p_actor_user_id
      AND m.status='active' AND m.role IN ('brand_admin','super_admin')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_redemption
  FROM public.redemptions
  WHERE id=p_redemption_id AND tenant_id=p_tenant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'error','redemption_not_found');
  END IF;

  IF v_redemption.status NOT IN ('reserved','approved') THEN
    RETURN jsonb_build_object('ok',false,'error','redemption_already_resolved','status',v_redemption.status);
  END IF;

  IF p_new_status='fulfilled' THEN
    UPDATE public.redemptions
      SET status='fulfilled', fulfilled_at=now(), updated_at=now(), cancellation_reason=NULL
      WHERE id=v_redemption.id;
  ELSE
    UPDATE public.redemptions
      SET status=p_new_status, updated_at=now(), cancellation_reason=trim(p_reason)
      WHERE id=v_redemption.id;

    -- Refund exactly once because the row is locked and only reserved/approved
    -- redemptions can enter this branch. Use the enum's release/compensation value.
    INSERT INTO public.points_ledger(
      tenant_id,partner_id,entry_type,points_delta,idempotency_key,reason_code,actor_user_id,metadata
    ) VALUES (
      p_tenant_id,v_redemption.partner_id,'redeem_release',v_redemption.points_cost,
      'redemption-refund:'||v_redemption.id::text,
      CASE WHEN p_new_status='rejected' THEN 'reward_redemption_rejected_refund'
           ELSE 'reward_redemption_cancelled_refund' END,
      p_actor_user_id,
      jsonb_build_object('redemption_id',v_redemption.id,'reward_id',v_redemption.reward_id,'reason',trim(p_reason))
    );

    SELECT * INTO v_reward FROM public.rewards
      WHERE id=v_redemption.reward_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF FOUND AND v_reward.stock_quantity IS NOT NULL THEN
      UPDATE public.rewards SET stock_quantity=stock_quantity+1,updated_at=now()
        WHERE id=v_reward.id;
    END IF;
  END IF;

  SELECT coalesce(sum(points_delta),0) INTO v_balance
    FROM public.points_ledger
    WHERE tenant_id=p_tenant_id AND partner_id=v_redemption.partner_id;

  INSERT INTO public.audit_logs(tenant_id,actor_user_id,action,entity_type,entity_id,reason,before_data,after_data)
  VALUES(
    p_tenant_id,p_actor_user_id,
    CASE WHEN p_new_status='fulfilled' THEN 'redemption_fulfilled'
         WHEN p_new_status='rejected' THEN 'redemption_rejected_refunded'
         ELSE 'redemption_cancelled_refunded' END,
    'redemption',v_redemption.id,nullif(trim(coalesce(p_reason,'')),''),
    jsonb_build_object('status',v_redemption.status),
    jsonb_build_object('status',p_new_status,'points_refunded',CASE WHEN p_new_status='fulfilled' THEN 0 ELSE v_redemption.points_cost END)
  );

  RETURN jsonb_build_object(
    'ok',true,'redemption_id',v_redemption.id,'status',p_new_status,
    'points_refunded',CASE WHEN p_new_status='fulfilled' THEN 0 ELSE v_redemption.points_cost END,
    'balance_after',v_balance
  );
END
$function$;
