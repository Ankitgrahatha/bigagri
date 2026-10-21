# RewardLoop Auth Lifecycle Release Checklist

## Implemented frontend flows

- Password reset request uses `supabase.auth.resetPasswordForEmail` with a first-party redirect to `/?auth=reset`.
- The UI handles the Supabase `PASSWORD_RECOVERY` event, shows a new-password and confirmation form, checks that both entries match, and calls `supabase.auth.updateUser`.
- The user is signed out after a successful password change so they sign in with the new credential.
- Sign-in includes a confirmation-resend action using Supabase's `auth.resend({ type: "signup" })`.
- English and Hindi translations are included. Success messages are generic to reduce account enumeration.

## Required Supabase project configuration

The frontend does not provision SMTP or alter project Auth settings. Before enabling this flow for customers:

1. In Supabase Auth URL Configuration, set the production Site URL to `https://bigagri.vercel.app`.
2. Add the exact production redirect `https://bigagri.vercel.app/?auth=reset` to allowed Redirect URLs, plus the current preview URL only when conducting a controlled test. Do not use a blanket wildcard in production.
3. Configure a verified sender domain and production SMTP provider in Supabase Auth settings; do not store SMTP credentials in browser code or expose them as public environment variables.
4. Keep signup email confirmation enabled for production accounts, subject to an approved onboarding policy.
5. Send a reset message to a controlled test mailbox; verify the message sender, link, redirect, recovery session, password update, sign-out, and subsequent sign-in.
6. Test expired/used recovery links, invalid passwords, rate-limits, missing confirmation, and no-account responses. Keep customer-facing messages generic.
7. Confirm the current production origin and Supabase Auth redirect settings before the final Vercel deployment.

## Verification status

Contract tests are run by GitHub Actions. Real SMTP delivery and the full Supabase Auth email flow remain unverified until tested against a controlled mailbox after project configuration. No Auth settings or credentials are changed by the frontend code.
