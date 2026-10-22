import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const sql = readFileSync(
  new URL("../diagnostics/production_schema_fingerprint.sql", import.meta.url),
  "utf8",
);

// Split only on semicolons that are SQL statement delimiters, not inside
// quoted literals or line comments. The diagnostic contains a literal ';'.
function splitSqlStatements(source) {
  const statements = [];
  let current = "";
  let inSingleQuote = false;
  let inLineComment = false;

  for (let i = 0; i < source.length; i += 1) {
    const char = source[i];
    const next = source[i + 1];

    if (inLineComment) {
      if (char === "\n") {
        inLineComment = false;
        current += char;
      }
      continue;
    }

    if (!inSingleQuote && char === "-" && next === "-") {
      inLineComment = true;
      i += 1;
      continue;
    }

    if (char === "'") {
      current += char;
      if (inSingleQuote && next === "'") {
        current += next;
        i += 1;
        continue;
      }
      inSingleQuote = !inSingleQuote;
      continue;
    }

    if (char === ";" && !inSingleQuote) {
      if (current.trim()) statements.push(current.trim());
      current = "";
      continue;
    }

    current += char;
  }

  if (current.trim()) statements.push(current.trim());
  assert.equal(inSingleQuote, false, "SQL contains an unterminated string literal");
  return statements;
}

test("production schema diagnostic is query-only", () => {
  const statements = splitSqlStatements(sql);
  assert.equal(statements.length, 4);
  for (const statement of statements) {
    assert.match(statement, /^(WITH|SELECT)\s/i);
    assert.doesNotMatch(statement, /\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE)\b/i);
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
