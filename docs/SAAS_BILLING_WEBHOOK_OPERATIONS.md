# SaaS billing webhook operations (implementation foundation)

## Current scope

The repository now contains a Razorpay callback receiver, a private durable event inbox, a service-role-only processing RPC, a bounded batch worker endpoint, versioned plan/pricing tables, tenant subscriptions, payment-attempt records, a fail-closed entitlement resolver, authenticated subscription checkout, and a tenant-scoped billing portal.

This is **not a live-payment launch approval**. No production migration, Edge Function, Razorpay dashboard, secret, or scheduled job has been changed by this code change.

## Required server-side secrets

Configure these only in the Supabase project’s Edge Function secrets store:

- `RAZORPAY_WEBHOOK_SECRET`: the secret configured for the Razorpay webhook endpoint.
- `RAZORPAY_PROCESSOR_SECRET`: a separate high-entropy secret used by the internal batch worker endpoint.
- `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET`: test-mode credentials for authenticated subscription checkout creation.
- `RAZORPAY_MONTHLY_TOTAL_COUNT` and `RAZORPAY_YEARLY_TOTAL_COUNT`: explicit billing-cycle caps from 1 to 100; subscriptions stop after the configured count.
- Platform-provided `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` remain server-side only.

Never commit secret values, put them in the PWA, or log webhook bodies/signatures/payment details.

## Checkout behavior and recovery

- The authenticated `create-razorpay-subscription` endpoint requires a valid Supabase user session, active tenant membership, a published plan version, a billing interval, and a caller-supplied idempotency key.
- PostgreSQL reserves the local subscription and payment attempt before the provider API call. Only one incomplete checkout is allowed per tenant.
- A repeated key reuses the stored checkout URL after finalization. A different key cannot create another pending subscription.
- If the provider request times out or returns an ambiguous server failure, the reservation remains blocked and requires manual reconciliation against Razorpay using the local subscription ID in provider notes. Active tenant super-admins can view aged incomplete reservations in the billing portal read-only queue backed by `saas-checkout-reconciliation`. Do not retry with a new key until the provider subscription state is checked; the queue does not mutate billing state.
- A definitive provider 4xx rejection marks the local reservation expired/failed so a fresh attempt can be made.
- Monthly/yearly cycle counts are mandatory configuration and must be chosen deliberately: the provider subscription ends after the configured number of billing cycles.
- The first successful charge webhook updates the reserved payment attempt rather than leaving a duplicate initiated record.

## Deployment order after review

1. Review and reconcile migration history in the target environment. Do not apply the clean-schema baseline to an existing production database.
2. Apply the additive billing migrations through the approved migration process.
3. Set the secrets above in the target Supabase project.
4. Deploy `razorpay-webhook`, `create-razorpay-subscription`, `saas-checkout-reconciliation`, `saas-billing-portal`, and `process-razorpay-webhooks` only after the migrations are confirmed present.
5. Verify `/admin-billing.html` with a test-mode tenant-admin account. Check published-plan visibility, hosted checkout, same-key retry behavior, tenant switching, and the super-admin reconciliation queue.
6. Configure the Razorpay test-mode webhook URL:
   `https://<project-ref>.supabase.co/functions/v1/razorpay-webhook`
7. Subscribe to the required subscription lifecycle events: `subscription.charged`, `subscription.cancelled`, `subscription.completed`, `subscription.halted`, `subscription.paused`, and `payment.failed`.
8. Configure a trusted scheduler to POST to `/functions/v1/process-razorpay-webhooks` with `x-processor-secret` set from a secret store. Use a bounded cadence such as once per minute and alert on repeated failures; do not put the header value in source control or logs.
9. Create test-mode Razorpay plans and populate provider plan IDs on a draft plan version before publishing it. The schema requires monthly and yearly provider plan IDs for published versions.
10. Run duplicate delivery, invalid signature, stale/out-of-order event, amount/currency mismatch, failed payment, cancellation, and restore/reconciliation tests in test mode.

## Processing behavior and safety limits

- The receiver verifies the HMAC against the exact raw body before JSON parsing and acknowledges only after the inbox insert succeeds.
- The unique provider/event ID prevents duplicate delivery from creating duplicate inbox rows.
- The processor locks inbox and subscription rows, checks provider subscription and plan IDs, exact amount/currency, captured payment status, and billing period before activating a subscription.
- Failed payments move a non-terminal subscription to `past_due`; the entitlement resolver fails closed for `past_due`, expired periods, unpublished versions, and missing subscriptions. Grace-period behavior is not implemented.
- Out-of-order events are marked stale; unsupported event types are marked ignored. Invalid events retry up to eight attempts with a bounded backoff of up to five minutes, after which they require operator review. The batch response includes an `exhausted` count; alert if it is non-zero.
- The batch endpoint is not scheduled automatically by this repository change. A scheduler and alerting are operational prerequisites.
- Published plan versions are immutable. Publish a new version instead of changing prices/entitlements in place.

## Explicitly not implemented or not approved

- Tax calculations, GST invoice/credit-note legal formatting, refunds, proration, discounts/coupons, dunning/grace policy, automated provider-side reconciliation/mutation, plan changes, and subscription cancellation controls.
- Live provider credentials, production endpoint deployment, secret provisioning, scheduler configuration, or real-value payment testing. The billing portal UI and checkout endpoint are implemented in source but are not deployed or verified against a real Razorpay test account.

Do not enable live payments until these items have a reviewed policy, verified test-mode evidence, reconciliation coverage, and a rollback/runbook.
