# The text sizes and fonts of Settings -> General, run against the UI inline in
# NOBSSQL.ps1.
#
# The JavaScript below is the same test file the Tauri edition (nobs-sql-editor,
# tests/ui/ui-settings.test.mjs) runs against its ui/index.html - both editions share the UI, so they share
# the test. Generated from that file; keep the two in step.
#
#   pwsh -NoProfile -File tests/UiSettings.Tests.ps1 ./NOBSSQL.ps1
param([Parameter(Mandatory)][string]$ScriptPath)

if (-not (Test-Path $ScriptPath)) { "  FAIL  script not found: $ScriptPath"; exit 1 }
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { "  FAIL  node not found on PATH - this UI is JavaScript and needs it to run"; exit 1 }

$test = @'
// Settings -> General: the text sizes and the fonts kept on this computer (ui/index.html) - what is
// read back from storage, what is refused, and the font stacks the page is given.
//
// As in the other tests here, the functions are lifted out of the page and run, rather than
// copied, so a regression in the page is a failure here.
//
// Run: node --test tests/ui/     (or npm test)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const html = readFileSync(process.env.NOBS_UI_SOURCE || join(root, 'ui', 'index.html'), 'utf8');

function extractFunction(src, name) {
  const start = src.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `function ${name} not found - was it renamed?`);
  let i = src.indexOf('{', start), depth = 0;
  for (let j = i; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}' && --depth === 0) return src.slice(start, j + 1);
  }
  throw new Error(`unbalanced braces while extracting ${name}`);
}
// A const statement, from its name to the ';' closing it at the top level.
function extractConst(src, name) {
  const start = src.indexOf(`const ${name}=`);
  assert.notEqual(start, -1, `const ${name} not found - was it renamed?`);
  let depth = 0;
  for (let j = start; j < src.length; j++) {
    const c = src[j];
    if ('{[('.includes(c)) depth++;
    else if ('}])'.includes(c)) depth--;
    else if (c === ';' && depth === 0) return src.slice(start, j + 1);
  }
  throw new Error(`no end to const ${name}`);
}

// localStorage as a plain map, and one that throws (a private window, blocked site data)
const store = new Map();
const localStorage = { getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
let applied = 0;
const lib = new Function('localStorage', 'uiSizesApply',
  ['UI_SIZES', 'UI_MONO', 'UI_FONTS'].map(n => extractConst(html, n)).join('\n') + '\n' +
  ['uiSizeKey', 'uiSizeGet', 'uiSizeSet', 'uiFontStack', 'uiFontGet', 'uiFontSet'].map(n => extractFunction(html, n)).join('\n') +
  '\nreturn {UI_SIZES, UI_MONO, UI_SANS, UI_FONTS, uiSizeGet, uiSizeSet, uiFontStack, uiFontGet, uiFontSet};');
const S = lib(localStorage, () => applied++);
const broken = lib({ getItem() { throw new Error('denied'); }, setItem() { throw new Error('denied'); }, removeItem() { throw new Error('denied'); } }, () => {});

test('a text size is read back within its range, else the default', () => {
  store.clear();
  assert.equal(S.uiSizeGet('ed'), 13);
  store.set('edFontSize', '18'); assert.equal(S.uiSizeGet('ed'), 18);
  store.set('edFontSize', '99'); assert.equal(S.uiSizeGet('ed'), 13, 'out of range');
  store.set('edFontSize', 'big'); assert.equal(S.uiSizeGet('ed'), 13, 'not a number');
  store.set('gridFontSize', '22'); assert.equal(S.uiSizeGet('grid'), 13, 'the results stop at 18');
});

test('setting a size clamps and rounds it, and applies it', () => {
  store.clear(); const n = applied;
  S.uiSizeSet('ed', 40); assert.equal(store.get('edFontSize'), '22');
  S.uiSizeSet('ed', 2); assert.equal(store.get('edFontSize'), '10');
  S.uiSizeSet('grid', 14.6); assert.equal(store.get('gridFontSize'), '15');
  assert.equal(applied - n, 3);
});

test('a font is kept only when it is on its list', () => {
  store.clear();
  S.uiFontSet('ed', 'Consolas'); assert.equal(S.uiFontGet('ed'), 'Consolas');
  S.uiFontSet('ui', 'Wingdings'); assert.equal(S.uiFontGet('ui'), '');
  assert.equal(store.has('uiFont'), false, 'and nothing is stored for it');
  S.uiFontSet('ui', 'Consolas'); assert.equal(S.uiFontGet('ui'), '', 'a code font is not an interface font');
  S.uiFontSet('grid', 'Consolas'); assert.equal(S.uiFontGet('grid'), 'Consolas', 'the results may have either kind');
  store.set('edFont', '"x";}body{display:none'); assert.equal(S.uiFontGet('ed'), '', 'a stored value off the list is not used');
  S.uiFontSet('ed', ''); assert.equal(store.has('edFont'), false, 'Default removes it');
});

test('a font stack falls back to the same kind of font', () => {
  assert.equal(S.uiFontStack('Consolas'), '"Consolas",Consolas,monospace');
  assert.equal(S.uiFontStack('Verdana'), '"Verdana","Segoe UI",sans-serif');
  assert.ok(S.UI_FONTS.ui.list.every(n => !S.UI_MONO.includes(n)));
  assert.ok(S.UI_FONTS.ed.list.every(n => S.UI_MONO.includes(n)));
});

test('with storage blocked, the defaults, and no error', () => {
  assert.equal(broken.uiSizeGet('ed'), 13);
  assert.equal(broken.uiFontGet('ed'), '');
  assert.doesNotThrow(() => { broken.uiSizeSet('ed', 15); broken.uiFontSet('ed', 'Consolas'); });
});
'@
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("UiSettings-" + [Guid]::NewGuid().ToString('N') + ".test.mjs")
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