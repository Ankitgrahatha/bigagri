# Campaign Budget and Point Valuation Rules

Status: implemented in GitHub branch / pull request; **not deployed to the connected production Supabase project**.

## Budget unit

`campaigns.budget_minor_units` is a currency budget, not a points count. The claim system must not compare points directly with this field.

Each tenant may explicitly configure:

- `point_value_minor_units`: integer currency minor units assigned to one awarded point.
- `point_value_currency`: three-letter currency code that must match the campaign currency.

For INR, one rupee is 100 paise. For example, if an authorized tenant admin sets a point value of 100 paise and a QR award is 7 points, the claim reserves 700 paise against the campaign budget. The system does not choose or infer the valuation; a business owner must approve it.

## Atomic claim decision

For an otherwise valid QR claim, the transaction:

1. Checks the request replay key against the same tenant, actor and QR resource.
2. Locks the campaign row before checking cumulative campaign liability. This serializes budget decisions for concurrent claims within the same campaign.
3. Requires a configured point valuation for a campaign with a positive budget and requires the valuation currency to match the campaign currency.
4. Sums prior append-only campaign-liability entries that count against the budget.
5. Rejects a claim when the new award would push liability beyond the cap. In this case the QR remains active and no claim, points-ledger credit or liability row is committed.
6. On success, writes the QR claim, points-ledger earn entry, scan/audit records and immutable campaign-liability entry in the same database transaction.

The liability table records the point valuation used for each claim. Its UPDATE, DELETE and TRUNCATE operations are blocked so historical campaign accounting cannot be silently rewritten.

## Configuration and campaign lifecycle

The admin control room offers a point valuation form, protected by the existing active tenant membership and brand-admin/super-admin authorization checks. Changes are written through a server-side RPC and audit-log event.

A campaign with a positive budget cannot be activated until its tenant has a valid point valuation in the matching currency. The valuation cannot be changed or cleared while a budgeted campaign is active; pause those campaigns first. This prevents one active campaign from calculating the cap against shifting rates.

An unbudgeted campaign (`budget_minor_units = 0`) retains its existing claim behavior. If a valuation is configured, matching-currency claims are still recorded in the liability ledger but do not count against a zero-budget cap. A mismatch on a budgeted campaign fails closed.

## Accounting scope

This first control is a **gross points-awarded budget**. It is not a valuation of reward acquisition cost, shipping/fulfilment expense, payment-gateway cost, or the net outstanding value of a farmer's current points balance. Those are separate accounting models and must not be conflated with this cap.

## Isolated acceptance test

The database regression test creates only synthetic rows in a disposable PostgreSQL service. It configures a 1,000-paise cap and 100-paise-per-point value:

- A 7-point claim reserves 700 paise and posts one 7-point ledger credit.
- A second 7-point QR claim is rejected because 1,400 paise would exceed the cap.
- The second QR stays active; no second claim, points credit or campaign-liability entry is written.
- A non-admin cannot set the valuation.
- The valuation cannot be changed while the budgeted campaign is active.
- A budgeted campaign without a configured valuation cannot be activated.

The CI database applies the full reconciled migration chain before running this test. The test is not production deployment evidence.

## Release procedure

1. Merge only after the SQL behavior test, source contract test, API route guard and safe smoke tests pass.
2. Review the migration diff and take the normal production backup before applying it.
3. Apply the reviewed migration through the controlled Supabase release process—not the GitHub CI database.
4. Configure and approve the point valuation for the tenant; the migration deliberately does not backfill a guessed value.
5. Confirm the production campaign's budget currency matches the configured currency.
6. Run a controlled pre-launch acceptance check without minting synthetic production claims. Do not enable a real-value campaign until the deployed routine and configured valuation have been independently verified.

The Vercel check is separate from database verification: GitHub's current Vercel status has reported a Hobby plan deployment-rate limit. Passing SQL CI does not imply the production Edge Function or frontend has been deployed.
