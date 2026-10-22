# SaaS billing webhook operations (implementation foundation)

## Current scope

The repository now contains a Razorpay callback receiver, a private durable event inbox, a service-role-only processing RPC, a bounded batch worker endpoint, versioned plan/pricing tables, tenant subscriptions, payment-attempt records, and a fail-closed entitlement resolver.

This is **not a live-payment launch approval**. No production migration, Edge Function, Razorpay dashboard, secret, or scheduled job has been changed by this code change.

## Required server-side secrets

Configure these only in the Supabase project’s Edge Function secrets store:

- `RAZORPAY_WEBHOOK_SECRET`: the secret configured for the Razorpay webhook endpoint.
- `RAZORPAY_PROCESSOR_SECRET`: a separate high-entropy secret used by the internal batch worker endpoint.
- Platform-provided `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` remain server-side only.

Never commit secret values, put them in the PWA, or log webhook bodies/signatures/payment details.

## Deployment order after review

1. Review and reconcile migration history in the target environment. Do not apply the clean-schema baseline to an existing production database.
2. Apply the additive billing migrations through the approved migration process.
3. Set the secrets above in the target Supabase project.
4. Deploy `razorpay-webhook` and `process-razorpay-webhooks` only after the migration is confirmed present.
5. Configure the Razorpay test-mode webhook URL:
   `https://<project-ref>.supabase.co/functions/v1/razorpay-webhook`
6. Subscribe to the required subscription lifecycle events: `subscription.charged`, `subscription.cancelled`, `subscription.completed`, `subscription.halted`, `subscription.paused`, and `payment.failed`.
7. Configure a trusted scheduler to POST to `/functions/v1/process-razorpay-webhooks` with `x-processor-secret` set from a secret store. Use a bounded cadence such as once per minute and alert on repeated failures; do not put the header value in source control or logs.
8. Create test-mode Razorpay plans and populate provider plan IDs on a draft plan version before publishing it. The schema requires monthly and yearly provider plan IDs for published versions.
9. Run duplicate delivery, invalid signature, stale/out-of-order event, amount/currency mismatch, failed payment, cancellation, and restore/reconciliation tests in test mode.

## Processing behavior and safety limits

- The receiver verifies the HMAC against the exact raw body before JSON parsing and acknowledges only after the inbox insert succeeds.
- The unique provider/event ID prevents duplicate delivery from creating duplicate inbox rows.
- The processor locks inbox and subscription rows, checks provider subscription and plan IDs, exact amount/currency, captured payment status, and billing period before activating a subscription.
- Failed payments move a non-terminal subscription to `past_due`; the entitlement resolver fails closed for `past_due`, expired periods, unpublished versions, and missing subscriptions. Grace-period behavior is not implemented.
- Out-of-order events are marked stale; unsupported event types are marked ignored. Invalid events retry up to eight attempts, after which they require operator review.
- The batch endpoint is not scheduled automatically by this repository change. A scheduler and alerting are operational prerequisites.
- Published plan versions are immutable. Publish a new version instead of changing prices/entitlements in place.

## Explicitly not implemented or not approved

- Tax calculations, GST invoice/credit-note legal formatting, refunds, proration, discounts/coupons, dunning/grace policy, customer billing portal, automated reconciliation, and customer-facing billing UI.
- Live provider credentials, production endpoint deployment, secret provisioning, scheduler configuration, or real-value payment testing.

Do not enable live payments until these items have a reviewed policy, verified test-mode evidence, reconciliation coverage, and a rollback/runbook.
