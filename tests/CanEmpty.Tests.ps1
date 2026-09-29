# Tests for which columns the grid offers "Set empty" for, run against the UI inline in NOBSSQL.ps1.
#
# The JavaScript below is the same test file the Tauri edition (nobs-sql-editor,
# tests/ui/can-empty.test.mjs) runs against its ui/index.html - both editions share the UI, so they share
# the test. Generated from that file; keep the two in step.
#
#   pwsh -NoProfile -File tests/CanEmpty.Tests.ps1 ./NOBSSQL.ps1

param([Parameter(Mandatory)][string]$ScriptPath)

if (-not (Test-Path $ScriptPath)) { "  FAIL  script not found: $ScriptPath"; exit 1 }
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { "  FAIL  node not found on PATH - this UI is JavaScript and needs it to run"; exit 1 }

$test = @'
// Which columns the grid offers "Set empty" for.
//
// "Set N picked cells to empty" counted every picked cell and put '' into all of them - into an INT,
// a DATE or an ENUM too, where strict mode refuses it and non-strict mode quietly makes it 0 or a
// zero date. The menu now offers empty only where the column's type has an empty value.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// NOBS_UI_SOURCE lets the PowerShell edition run this same file against NOBSSQL.ps1, which carries
// the identical UI inline.
const html = readFileSync(process.env.NOBS_UI_SOURCE ||
  join(dirname(fileURLToPath(import.meta.url)), '../../ui/index.html'), 'utf8').replace(/\r\n/g, '\n');

function extractFunction(src, name) {
  const start = src.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `function ${name} not found - was it renamed?`);
  let depth = 0;
  for (let j = src.indexOf('{', start); j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}' && --depth === 0) return src.slice(start, j + 1);
  }
  throw new Error(`unbalanced braces while extracting ${name}`);
}

const canEmptyFor = (colTypes, colGen = {}) => {
  const t = { colTypes, colGen };
  return new Function('T', extractFunction(html, 'isGenCol') + '\n' + extractFunction(html, 'canEmpty') + '\nreturn canEmpty;')(() => t);
};

test('text-like columns can be set empty', () => {
  const types = { a: 'varchar(10)', b: 'char(3)', c: 'text', d: 'longtext', e: 'varbinary(8)', f: 'blob', g: "set('x','y')" };
  const canEmpty = canEmptyFor(types);
  for (const c of Object.keys(types)) assert.equal(canEmpty(1, c), true, types[c]);
});

test('numbers, dates, BIT, JSON and spatial columns cannot', () => {
  const types = { a: 'int(11)', b: 'bigint unsigned', c: 'decimal(10,2)', d: 'double', e: 'tinyint(1)', f: 'bit(1)',
    g: 'date', h: 'datetime(3)', i: 'timestamp', j: 'time', k: 'year(4)', l: 'json', m: 'point', n: 'geometry', o: 'uuid', p: 'inet6' };
  const canEmpty = canEmptyFor(types);
  for (const c of Object.keys(types)) assert.equal(canEmpty(1, c), false, types[c]);
});

test("an ENUM only when '' is one of its members", () => {
  const canEmpty = canEmptyFor({ a: "enum('x','y')", b: "enum('','x')", c: "enum('x','')", d: "enum('it''s','x')", e: "enum('''','x')" });
  assert.equal(canEmpty(1, 'a'), false);
  assert.equal(canEmpty(1, 'b'), true);
  assert.equal(canEmpty(1, 'c'), true);
  assert.equal(canEmpty(1, 'd'), false);
  assert.equal(canEmpty(1, 'e'), false);
});

test('a generated column cannot, and an unknown one is left to the server', () => {
  const canEmpty = canEmptyFor({ a: 'varchar(10)' }, { a: true });
  assert.equal(canEmpty(1, 'a'), false);
  assert.equal(canEmpty(1, 'nope'), true);
  assert.equal(canEmptyFor(undefined)(1, 'a'), true);
});
'@
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("CanEmpty-" + [Guid]::NewGuid().ToString('N') + ".test.mjs")
$code = 1
try {
    [IO.File]::WriteAllText($tmp, $test, (New-Object System.Text.UTF8Encoding($false)))
    $env:NOBS_UI_SOURCE = (Resolve-Path $ScriptPath).Path
    & $node.Source --test $tmp
    $code = $LASTEXITCODE
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\NOBS_UI_SOURCE -ErrorAction SilentlyContinue
}
if ($code -ne 0) { "`n  FAILED"; exit 1 } else { "`n  all passed"; exit 0 }