import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const sql = readFileSync(
  new URL("../diagnostics/production_schema_fingerprint.sql", import.meta.url),
  "utf8",
);

test("production schema diagnostic is query-only", () => {
  const statements = sql
    .split(";")
    .map((statement) => statement.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n").trim())
    .filter(Boolean);
  assert.equal(statements.length, 4);
  for (const statement of statements) {
    assert.ok(statement.startsWith("WITH ") || statement.startsWith("SELECT "));
  }
});

test("production schema diagnostic covers expected catalog surfaces", () => {
  for (const fragment of [
    "'columns'",
    "'constraints'",
    "'enums'",
    "'indexes'",
    "'policies'",
    "'rls'",
    "'triggers'",
    "information_schema.columns",
    "pg_get_constraintdef",
    "pg_indexes",
    "pg_policies",
    "pg_trigger",
    "aclexplode(c.relacl)",
    "supabase_migrations.schema_migrations",
  ]) {
    assert.ok(sql.includes(fragment), "missing diagnostic fragment: " + fragment);
  }
});
