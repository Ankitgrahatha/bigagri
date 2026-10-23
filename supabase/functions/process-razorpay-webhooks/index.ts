import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });

function constantTimeEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  let mismatch = leftBytes.length ^ rightBytes.length;
  const maxLength = Math.max(leftBytes.length, rightBytes.length);
  for (let i = 0; i < maxLength; i += 1) {
    mismatch |= (leftBytes[i] ?? 0) ^ (rightBytes[i] ?? 0);
  }
  return mismatch === 0;
}

async function readLimitedBody(req: Request, maxBytes: number): Promise<Uint8Array | null> {
  const reader = req.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel().catch(() => {});
        return null;
      }
      chunks.push(value);
    }
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return respond(405, { ok: false, error: "method_not_allowed" });

  const expectedSecret = Deno.env.get("RAZORPAY_PROCESSOR_SECRET") ?? "";
  const suppliedSecret = req.headers.get("x-processor-secret") ?? "";
  if (!expectedSecret || !suppliedSecret || !constantTimeEqual(suppliedSecret, expectedSecret)) {
    return respond(401, { ok: false, error: "unauthorized" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return respond(503, { ok: false, error: "service_not_configured" });
  }

  let limit = 25;
  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 4096) {
    return respond(413, { ok: false, error: "payload_too_large" });
  }
  // Enforce the cap while reading too: Content-Length can be absent for streamed
  // requests, so the header alone is not a reliable request-size boundary.
  const bodyBytes = await readLimitedBody(req, 4096);
  if (!bodyBytes) return respond(413, { ok: false, error: "payload_too_large_or_unreadable" });
  if (bodyBytes.byteLength > 0) {
    let body: unknown;
    try {
      body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes));
    } catch {
      return respond(400, { ok: false, error: "invalid_request" });
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return respond(400, { ok: false, error: "invalid_request" });
    }
    const input = body as Record<string, unknown>;
    if (Object.keys(input).some((key) => key !== "limit")) {
      return respond(400, { ok: false, error: "invalid_request" });
    }
    const requestedLimit = input.limit;
    if (requestedLimit !== undefined) {
      if (!Number.isInteger(requestedLimit) || Number(requestedLimit) < 1 || Number(requestedLimit) > 100) {
        return respond(400, { ok: false, error: "invalid_batch_size" });
      }
      limit = Number(requestedLimit);
    }
  }

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await db.rpc("process_saas_payment_webhook_batch_internal", {
    p_limit: limit,
  });
  if (error) {
    console.error("razorpay_webhook_batch_failed", { code: error.code ?? "unknown" });
    return respond(503, { ok: false, error: "processor_unavailable" });
  }

  const result = data as Record<string, unknown> | null;
  if (!result || result.ok !== true) {
    return respond(500, { ok: false, error: "processor_failed" });
  }
  // Health is aggregate-only. If the metrics query fails, preserve the completed
  // batch result and surface the missing telemetry rather than replaying the batch.
  const { data: healthData, error: healthError } = await db.rpc("get_saas_payment_webhook_health_internal");
  const health = healthData as Record<string, unknown> | null;
  if (healthError || !health || health.ok !== true) {
    console.error("razorpay_webhook_health_metrics_unavailable", { code: healthError?.code ?? "invalid_health_result" });
  }
  return respond(200, {
    ok: true,
    processed: result.processed,
    failed: result.failed,
    exhausted: result.exhausted,
    batch_size: result.batch_size,
    health_metrics_available: !healthError && health?.ok === true,
    ...(healthError || !health || health.ok !== true ? {} : {
      pending_received: health.received,
      retryable_failed: health.retryable_failed,
      exhausted_total: health.exhausted,
      stale_processing: health.stale_processing,
      oldest_unprocessed_age_seconds: health.oldest_unprocessed_age_seconds,
    }),
  });
});
