import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../../app.js", import.meta.url), "utf8");

test("password recovery requests use a fixed first-party redirect and generic response", () => {
  assert.match(app, /resetPasswordForEmail\(email,\s*\{\s*redirectTo:\s*\`\$\{window\.location\.origin\}\/\?auth=reset\`/);
  assert.match(app, /recoverySent:"If an account exists for this email/);
  assert.match(app, /recoverySent:"अगर यह ईमेल पंजीकृत है/);
});

test("recovery callback renders a reset form and requires matching passwords before update", () => {
  assert.match(app, /event === "PASSWORD_RECOVERY"/);
  assert.match(app, /password !== confirmation/);
  assert.match(app, /supabase\.auth\.updateUser\(\{ password \}\)/);
  assert.match(app, /state\.authMode === "reset"\) renderAuth\(\)/);
});

test("confirmation resend uses Supabase's signup resend API with the entered email", () => {
  assert.match(app, /supabase\.auth\.resend\(\{\s*type:"signup",\s*email,/);
  assert.match(app, /resend-confirmation/);
});

test("recovery exits the recovery session after success and clears the URL query", () => {
  assert.match(app, /history\.replaceState\(\{\}, "", window\.location\.pathname\)/);
  assert.match(app, /passwordResetSuccess/);
});

test("recovery methods are present in both Hindi and English", () => {
  for (const key of ["forgotPassword", "resendConfirmation", "recoverTitle", "resetTitle", "passwordMismatch"]) {
    assert.ok(app.includes(key + ":"), "missing localized key " + key);
  }
});
