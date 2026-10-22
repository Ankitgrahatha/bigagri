import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import { verifyRazorpayWebhookSignature } from "../functions/_shared/razorpay_webhook.ts";

const secret = "test-webhook-secret";
const body = '{"event":"subscription.charged","payload":{"subscription":{"entity":{"id":"sub_test"}}}}';
const signature = (value, key = secret) =>
  createHmac("sha256", key).update(value, "utf8").digest("hex");

test("accepts a valid HMAC signature for the exact raw body", async () => {
  assert.equal(await verifyRazorpayWebhookSignature(body, signature(body), secret), true);
});

test("rejects a signature generated for a different body", async () => {
  assert.equal(await verifyRazorpayWebhookSignature(body, signature(body + " "), secret), false);
});

test("rejects malformed or absent signature headers", async () => {
  for (const candidate of [null, "", "nope", "a".repeat(63), "g".repeat(64)]) {
    assert.equal(await verifyRazorpayWebhookSignature(body, candidate, secret), false);
  }
});

test("rejects missing body or secret", async () => {
  assert.equal(await verifyRazorpayWebhookSignature("", signature(body), secret), false);
  assert.equal(await verifyRazorpayWebhookSignature(body, signature(body), ""), false);
});

test("rejects a signature created with a different secret", async () => {
  assert.equal(await verifyRazorpayWebhookSignature(body, signature(body, "wrong-secret"), secret), false);
});
