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

Never commit secret values, put them in the PWA, or log webhook bodies/signatures/payment details. Configure `ALLOWED_ORIGINS` as a comma-separated list of exact browser origins for approved Vercel preview/custom domains; do not use a wildcard. Billing endpoints handle `OPTIONS` preflight and allow the checkout `Idempotency-Key` header.

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
- `.github/workflows/rewardloop-billing-webhook-scheduler.yml` provides a five-minute GitHub Actions scheduler, bounded processor calls, aggregate-health checks, and a deduplicated operator issue alert. It is deliberately disabled unless the repository Actions variable `REWARDLOOP_BILLING_MONITOR_ENABLED` is set to `true`. Activate it only after this PR is merged, `RAZORPAY_PROCESSOR_SECRET` is configured as a GitHub Actions secret matching the Supabase Edge Function secret, the migration/function are deployed, and a successful test-mode run is observed. The workflow must not be treated as deployment or secret-provisioning evidence.
- Published plan versions are immutable. Publish a new version instead of changing prices/entitlements in place.

## Explicitly not implemented or not approved

- Tax calculations, GST invoice/credit-note legal formatting, refunds, proration, discounts/coupons, dunning/grace policy, automated provider-side reconciliation/mutation, plan changes, and subscription cancellation controls.
- Live provider credentials, production endpoint deployment, secret provisioning, scheduler configuration, or real-value payment testing. The billing portal UI and checkout endpoint are implemented in source but are not deployed or verified against a real Razorpay test account.

Do not enable live payments until these items have a reviewed policy, verified test-mode evidence, reconciliation coverage, and a rollback/runbook.


## Failed-payment and webhook incident runbook

### Signals to alert on

The scheduler/monitoring system must retain the HTTP status and the JSON counters from every `process-razorpay-webhooks` run, without retaining request secrets or customer/payment payloads. Create alerts with these minimum conditions:

- **Critical — processor unavailable:** any non-2xx response from the processor endpoint for two consecutive scheduled runs, or no successful run for more than three minutes when running once per minute.
- **High — exhausted events:** `exhausted > 0` on any successful response. These events have reached the retry cap and require operator review; a later successful batch does not mean they were repaired.
- **High — backlog:** `failed > 0` for three consecutive runs, or the pending-event count grows for five consecutive observations. Investigate provider/schema mismatch and processor logs before manually replaying anything.
- **High — customer payment failure:** a subscription transitions to `past_due` or a `payment.failed` event is processed. Notify the tenant's billing owner through an approved customer-support channel; do not include payment details in alert payloads.
- **Warning — delivery/processing lag:** the oldest unprocessed webhook is older than five minutes. Confirm the scheduler is running and the processor secret is configured correctly.

Thresholds are initial operational defaults, not provider guarantees. Tune them after observing test-mode volume and actual scheduler cadence. The processor response alone does not report the age of the oldest queued event, so that lag alert requires monitoring against the database through a separately authorized operator query/metric; do not expose private inbox tables to browser roles to implement it.

### When a payment fails

1. Confirm the webhook receipt was durably accepted and the event was processed (or inspect its retry/exhausted state through the approved operator-only database path).
2. Verify the local subscription is `past_due` and that entitlements are denied. Do not manually grant access or change the subscription to `active` based solely on a browser redirect or a customer screenshot.
3. Ask the tenant billing owner to complete payment through the provider-supported customer flow. Do not collect card/bank credentials, copy payment secrets into support tickets, or create a second subscription as a workaround.
4. Verify the provider's subscription/payment state and correlate the provider subscription ID with the local tenant subscription before any manual repair. A captured payment must match the expected provider subscription, provider plan, amount, currency, and billing period before entitlements can be restored.
5. If the provider and local state disagree, preserve the current fail-closed entitlement state and escalate to the billing/platform owner. Record the event ID, local subscription ID, provider subscription ID, timestamps, and redacted error code only.
6. There is no automatic dunning, grace period, customer self-serve payment-retry workflow, refund workflow, or provider-side reconciliation/mutation in this implementation. Do not promise these capabilities to customers.

### When events are exhausted or out of order

- Do not delete inbox rows or reset attempt counters to make an alert disappear.
- Inspect the event type, safe error code, attempt count, local subscription status, and matching provider IDs using an approved service-role/operator session. Never paste full webhook payloads into tickets or chat.
- Correct the underlying configuration/schema issue first. Reprocess only through the supported worker/RPC after a reviewed, documented decision; preserve idempotency and the event's audit trail.
- Out-of-order events may be intentionally marked stale. Confirm current provider state before taking any corrective action; an old `subscription.charged` event must not revive a terminal subscription.

### Test-mode release evidence

Before production approval, attach evidence for each of these cases to the release record:

- Valid webhook signature accepted; invalid signature rejected; database receipt failure returns retryable non-2xx.
- Duplicate event delivery creates one inbox event and does not duplicate payment attempts or ledger/entitlement changes.
- Successful captured charge with matching subscription/plan/amount/currency activates the subscription; amount or currency mismatch does not.
- `payment.failed` moves an eligible subscription to `past_due` and entitlement resolution denies access.
- Out-of-order charge after cancellation/completion does not reactivate a terminal subscription.
- Poison event reaches the bounded retry cap, appears as exhausted, and fires the high-severity alert.
- Worker secret failure is rejected; scheduled worker recovers after secret/configuration repair.
- Checkout timeout remains blocked until a real test-mode provider subscription is verified by the recovery flow; unknown provider ID, plan mismatch, notes mismatch, and unsupported status all fail closed.
- Restore/reconciliation drill proves the operator can compare provider state with local state without granting access based on unverified evidence.

Record the test account/project, timestamp, migration version, deployed function version, sanitized event IDs, and outcomes. Do not record credentials, webhook signatures, raw payloads, or full payment/customer data. A green unit/CI suite is not a substitute for this live test-mode evidence.
