import { readFileSync } from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";

const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const css = readFileSync(new URL("../../admin.css", import.meta.url), "utf8");

test("admin console builds section navigation from the rendered panels", () => {
  assert.match(admin, /root\.querySelectorAll\("\.admin-panel"\)/);
  assert.match(admin, /section\.querySelector\("h2"\)/);
  assert.match(admin, /section\.id=id/);
  assert.match(admin, /insertAdjacentElement\("afterend",sectionNav\)/);
});

test("admin navigation has an accessible name and links to generated section IDs", () => {
  assert.match(admin, /sectionNav\.setAttribute\("aria-label","Admin sections"\)/);
  assert.match(admin, /return '<a href="#'\+id\+'">'\+esc\(label\)\+'<\/a>'/);
  assert.match(admin, /admin-section-/);
});

test("admin navigation remains horizontally usable on narrow screens", () => {
  assert.match(css, /\.admin-section-nav/);
  assert.match(css, /@media\(max-width:760px\)\{\.admin-section-nav\{flex-wrap:nowrap;overflow-x:auto/);
  assert.match(css, /\.admin-panel\{scroll-margin-top:18px\}/);
});
