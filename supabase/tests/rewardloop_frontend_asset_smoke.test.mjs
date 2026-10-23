import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const read = (name) => readFileSync(new URL(name, root), "utf8");

test("all browser JavaScript entry points exist", () => {
  for (const name of ["app.js", "admin.js", "admin-settings.js", "admin-billing.js", "sw.js"]) {
    assert.ok(existsSync(new URL(name, root)), name + " exists");
  }
});

test("all first-party assets referenced by HTML exist", () => {
  const htmlFiles = ["index.html", "admin.html", "admin-settings.html", "admin-billing.html"];
  const refs = [];
  for (const file of htmlFiles) {
    const html = read(file);
    for (const match of html.matchAll(/(?:src|href)\s*=\s*["']([^"'#]+)["']/gi)) {
      const value = match[1].trim();
      if (!value || /^(?:https?:|data:|mailto:|tel:|javascript:|\/\/)/i.test(value)) continue;
      const path = value.split(/[?#]/, 1)[0].replace(/^\//, "");
      if (!path || path.startsWith("http")) continue;
      refs.push({ file, path });
    }
  }
  const missing = refs.filter(({ path }) => !existsSync(new URL(path, root)));
  assert.deepEqual(missing, [], "Missing local assets: " + JSON.stringify(missing));
});

test("web manifest is valid JSON and references existing icons", () => {
  const manifest = JSON.parse(read("manifest.webmanifest"));
  assert.ok(manifest.name || manifest.short_name, "manifest must have a name");
  assert.ok(Array.isArray(manifest.icons) && manifest.icons.length > 0, "manifest must define icons");
  for (const icon of manifest.icons) {
    assert.equal(typeof icon.src, "string");
    const path = icon.src.replace(/^\//, "");
    assert.ok(existsSync(new URL(path, root)), "missing manifest icon: " + icon.src);
  }
});

test("app HTML includes viewport and module entry point", () => {
  const html = read("index.html");
  assert.match(html, /name=["']viewport["']/i);
  assert.match(html, /type=["']module["'][^>]*src=["']\/app\.js["']/i);
});

test("admin pages load their own module and stylesheet", () => {
  assert.match(read("admin.html"), /src=["']\/admin\.js["']/i);
  assert.match(read("admin-settings.html"), /src=["']\/admin-settings\.js["']/i);
  assert.match(read("admin.html"), /href=["']\/admin\.css["']/i);
});
