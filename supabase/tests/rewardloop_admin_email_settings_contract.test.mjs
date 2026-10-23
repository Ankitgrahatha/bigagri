import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const ui = readFileSync(new URL("../../admin-settings.js", import.meta.url), "utf8");
const html = readFileSync(new URL("../../admin-settings.html", import.meta.url), "utf8");
const api = readFileSync(new URL("../../supabase/functions/rewardloop-admin-settings/index.ts", import.meta.url), "utf8");

test("admin UI clearly says preferences do not change live Supabase Auth SMTP", () => {
  assert.match(ui, /live Supabase Auth SMTP and Auth settings are not changed/i);
  assert.match(html, /Live Supabase Auth SMTP is not configured by this form yet/i);
});

test("SMTP password is never persisted to the settings table", () => {
  assert.match(api, /Never persist SMTP passwords in application tables/i);
  assert.match(api, /if\(passwordProvided\) return respond\(409/);
  assert.doesNotMatch(api, /allowed\.smtp_password\s*=/);
});

test("SMTP password field is cleared after successful or failed submission", () => {
  assert.equal((ui.match(/\$\("password"\)\.value="";/g) || []).length, 2);
});

test("test-email placeholder is visibly unavailable and cannot be triggered", () => {
  assert.match(html, /id="testEmail"[^>]*disabled[^>]*aria-disabled="true"/);
  assert.match(html, /Test email unavailable/);
  assert.match(html, /This page cannot send a test message/);
  assert.doesNotMatch(ui, /\$\("testEmail"\)\.addEventListener/);
});

test("authentication controls clearly disclose that values are preferences only", () => {
  assert.match(html, /Authentication preferences/);
  assert.match(html, /do not change Supabase Auth site URL, redirect allowlist, signup policy, or email-confirmation enforcement/i);
  assert.match(html, /Save authentication preferences/);
  assert.match(ui, /they do not change live Supabase Auth configuration/i);
});
