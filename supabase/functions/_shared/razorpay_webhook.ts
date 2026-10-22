/**
 * Razorpay webhook signature verification.
 *
 * Verify the exact raw request bytes before JSON parsing. This helper deliberately
 * does not persist events or change subscriptions; callers must durably record
 * verified events and process them idempotently before acknowledging delivery.
 */
const encoder = new TextEncoder();

function decodeHex(value: string): Uint8Array | null {
  if (!/^[0-9a-f]{64}$/i.test(value)) return null;
  const bytes = new Uint8Array(32);
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = Number.parseInt(value.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let i = 0; i < left.length; i += 1) mismatch |= left[i] ^ right[i];
  return mismatch === 0;
}

/**
 * Returns false for missing/malformed inputs and any cryptographic failure.
 * Pass the unmodified request body text and the configured webhook secret.
 */
export async function verifyRazorpayWebhookSignature(
  rawBody: string,
  signatureHeader: string | null,
  webhookSecret: string,
): Promise<boolean> {
  if (!rawBody || !webhookSecret || !signatureHeader) return false;
  const supplied = decodeHex(signatureHeader.trim());
  if (!supplied) return false;

  try {
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(webhookSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const expected = new Uint8Array(
      await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody)),
    );
    return constantTimeEqual(expected, supplied);
  } catch {
    return false;
  }
}
