import { readFileSync } from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";

const admin = readFileSync(new URL("../../admin.js", import.meta.url), "utf8");
const html = readFileSync(new URL("../../admin.html", import.meta.url), "utf8");
const css = readFileSync(new URL("../../admin.css", import.meta.url), "utf8");

test("admin console builds navigation only from sections actually rendered for the tenant", () => {
  assert.match(admin, /root\.querySelectorAll\("\.admin-panel"\)/);
  assert.match(admin, /section\.querySelector\("h2"\)/);
  assert.match(admin, /section\.id=id/);
  assert.match(admin, /data-admin-nav-link/);
  assert.match(admin, /trailingNodes\.filter\(node=>node!==sectionNav\)/);
});

test("admin workspace navigation has a stable accessible name, link state, and safe labels", () => {
  assert.match(admin, /sectionNav\.setAttribute\("aria-label","Workspace navigation"\)/);
  assert.match(admin, /esc\(label\)/);
  assert.match(admin, /link\.setAttribute\("aria-current","location"\)/);
  assert.match(admin, /link\.removeAttribute\("aria-current"\)/);
  assert.match(admin, /navLinks\.find\(link=>link\.hash===window\.location\.hash\)/);
});

test("admin page declares the dedicated workspace layout without changing authenticated API actions", () => {
  assert.match(html, /class="app-shell admin-app-shell"/);
  assert.match(html, /class="main-content admin-console"/);
  assert.match(admin, /const ADMIN_SCOPED_ACTIONS=new Set/);
  assert.match(admin, /const tenantScope=ADMIN_SCOPED_ACTIONS\.has\(action\)&&selectedTenantSlug/);
});

test("enterprise sidebar, content area, and KPI cards have responsive desktop layouts", () => {
  assert.match(css, /\.admin-workspace\{display:grid;grid-template-columns:232px minmax\(0,1fr\)/);
  assert.match(css, /\.admin-content-stack\{display:grid;gap:18px;min-width:0\}/);
  assert.match(css, /\.admin-stats\{display:grid;grid-template-columns:repeat\(6,minmax\(0,1fr\)\)/);
  assert.match(css, /@media\(max-width:900px\)/);
  assert.match(css, /\.admin-console \.admin-workspace\{grid-template-columns:1fr;gap:15px\}/);
  assert.match(css, /\.admin-section-nav\{display:flex;align-items:center;gap:6px;flex-wrap:nowrap;overflow-x:auto/);
});

test("admin controls retain visible keyboard focus and reduced-motion support", () => {
  assert.match(css, /\.admin-section-nav a:focus-visible/);
  assert.match(css, /\.primary-button:focus-visible/);
  assert.match(css, /@media\(prefers-reduced-motion:reduce\)/);
});
