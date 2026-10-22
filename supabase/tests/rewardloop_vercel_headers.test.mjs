import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const config = JSON.parse(readFileSync(new URL("../../vercel.json", import.meta.url), "utf8"));

test("Vercel static deployment applies baseline browser security headers to every route", () => {
  assert.equal(config.headers.length, 1);
  assert.equal(config.headers[0].source, "/(.*)");
  const headers = Object.fromEntries(config.headers[0].headers.map(({ key, value }) => [key.toLowerCase(), value]));
  assert.equal(headers["x-content-type-options"], "nosniff");
  assert.equal(headers["x-frame-options"], "DENY");
  assert.equal(headers["referrer-policy"], "strict-origin-when-cross-origin");
  assert.match(headers["permissions-policy"], /camera=\(self\)/);
  assert.match(headers["permissions-policy"], /geolocation=\(\)/);
  assert.match(headers["strict-transport-security"], /^max-age=31536000/);
});
