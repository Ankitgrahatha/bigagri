import assert from "node:assert/strict";
import test from "node:test";
import { readLimitedBody } from "../functions/_shared/read_limited_body.mjs";

function streamedRequest(chunks) {
  return new Request("https://example.test/", {
    method: "POST",
    duplex: "half",
    body: new ReadableStream({
      start(controller) {
        for (const chunk of chunks) controller.enqueue(new Uint8Array(chunk));
        controller.close();
      },
    }),
    // Deliberately no Content-Length: the byte cap must work without it.
  });
}

test("bounded reader joins streamed chunks without changing bytes", async () => {
  const expected = new TextEncoder().encode('{"limit":25}');
  const result = await readLimitedBody(streamedRequest([expected.slice(0, 4), expected.slice(4)]), 32);
  assert.deepEqual(result, expected);
});

test("bounded reader accepts a body exactly at the cap", async () => {
  const expected = new Uint8Array([1, 2, 3, 4]);
  assert.deepEqual(await readLimitedBody(streamedRequest([[1, 2], [3, 4]]), 4), expected);
});

test("bounded reader rejects a streamed body that exceeds the cap", async () => {
  assert.equal(await readLimitedBody(streamedRequest([[1, 2, 3], [4, 5]]), 4), null);
});

test("bounded reader supports requests with no body", async () => {
  assert.deepEqual(await readLimitedBody(new Request("https://example.test/", { method: "POST" }), 0), new Uint8Array());
});

test("bounded reader rejects invalid limits before reading", async () => {
  await assert.rejects(() => readLimitedBody(streamedRequest([[1]]), -1), RangeError);
  await assert.rejects(() => readLimitedBody(streamedRequest([[1]]), 1.5), RangeError);
});
