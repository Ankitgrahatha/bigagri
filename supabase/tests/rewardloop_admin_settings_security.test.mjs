import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL("../functions/rewardloop-admin-settings/index.ts", import.meta.url),
  "utf8",
);

test("admin settings function verifies the caller JWT and active tenant admin membership", () => {
  assert.match(source, /auth\.getUser\(\)/);
  assert.match(source, /\.eq\("tenant_id",tenant\.id\)\.eq\("user_id",user\.id\)\.eq\("status","active"\)/);
  assert.match(source, /\.in\("role",\["brand_admin","super_admin"\]\)/);
});

test("admin settings function never writes SMTP passwords to application storage", () => {
  assert.match(source, /Never persist SMTP passwords in application tables/);
  assert.match(source, /if\(passwordProvided\) return respond\(409/);
  assert.doesNotMatch(source, /allowed\.smtp_password\s*=/);
  assert.doesNotMatch(source, /smtp_password:\s*s\.smtp_password/);
});

test("admin settings function allowlists fields and validates redirect URL scheme", () => {
  assert.match(source, /invalid_redirect_urls/);
  assert.match(source, /https:\\\/\\\//);
  assert.match(source, /allowed\.updated_by=user\.id/);
  assert.match(source, /unknown_action/);
});
