# Tests for viewIndices, the grid's row filtering and sorting. It decides the order every result
# grid is displayed in, and it is JavaScript embedded in NOBSSQL.ps1 rather than a PowerShell
# function - so unlike the other tests here it cannot be lifted out with the PowerShell AST and
# run in-process. It is extracted by brace-matching and run under node instead, which
# windows-latest (this repo's CI image) already ships.
#
# The function is NOT copied into this file: a copy would happily keep passing while the real one
# regressed. Everything below runs the code that actually ships.
#
#   pwsh -NoProfile -File tests/ViewIndices.Tests.ps1 ./NOBSSQL.ps1

param([Parameter(Mandatory)][string]$ScriptPath)

if (-not (Test-Path $ScriptPath)) { "  FAIL  script not found: $ScriptPath"; exit 1 }

# No node means these tests cannot run. Say so and fail, rather than reporting success for work
# that never happened - a test that silently passes when it did not execute is worse than no test.
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { "  FAIL  node not found on PATH - viewIndices is JavaScript and needs it to run"; exit 1 }

$harness = @'
import { readFileSync } from 'node:fs';

function extractFunction(src, name) {
  const start = src.indexOf(`function ${name}(`);
  if (start === -1) throw new Error(`function ${name} not found - was it renamed?`);
  let depth = 0;
  for (let j = src.indexOf('{', start); j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}' && --depth === 0) return src.slice(start, j + 1);
  }
  throw new Error('unbalanced braces while extracting ' + name);
}

const src = readFileSync(process.argv[2], 'utf8');
const viewIndicesSrc = extractFunction(src, 'viewIndices') + '\n' + extractFunction(src, 'viewIndicesFresh');
const rowHasTextSrc = extractFunction(src, 'rowHasText');
const stepSrc = extractFunction(src, 'gridSearchStep');

function sortColumn(values, { dir = 1, filters = {} } = {}) {
  const tab = { rows: values.map(v => [v]), filters, sortCol: 0, sortDir: dir };
  const viewIndices = new Function('T', `${viewIndicesSrc}\nreturn viewIndices;`)(() => tab);
  return viewIndices('t1').map(ri => tab.rows[ri][0]);
}

let fail = 0;
const eq = (got, want, label) => {
  const g = JSON.stringify(got), w = JSON.stringify(want);
  if (g !== w) { console.log(`  FAIL  ${label} -> got ${g}, want ${w}`); fail++; }
  else console.log(`  ok    ${label}`);
};

// The regression: parseFloat("1000.10") is 1000.1, so a per-pair "does it round-trip?" test fails
// for that value and falls back to string comparison, while "1.37" and "2.74" pass and compare
// numerically. Mixing both rules in one sort is an inconsistent comparator, and "1000.10" came
// back between "1.37" and "2.74".
eq(sortColumn(['0.00','1.37','1000.10','2.74','20.00','999.90']),
   ['0.00','1.37','2.74','20.00','999.90','1000.10'],
   'DECIMAL column with trailing zeros sorts numerically');

const vals = ['0.00','1.37','1000.10','2.74','20.00','999.90'];
eq(sortColumn(vals, { dir: -1 }), [...sortColumn(vals)].reverse(),
   'descending is exactly the reverse of ascending');

const mono = sortColumn(['9.50','10.00','100.10','2','0.30','1000','99.99','3.00']).map(Number);
eq(mono.every((v,i) => i === 0 || mono[i-1] <= v), true,
   'sorted output is monotonic - one consistent order');

eq(sortColumn(['1','2','10','20','100']), ['1','2','10','20','100'],
   'integers sort numerically, not as text');

eq(sortColumn(['banana','apple','cherry']), ['apple','banana','cherry'],
   'a genuinely textual column still sorts as text');

// parseFloat("1abc") is 1, which is why the numeric test matches the WHOLE string. One
// non-numeric value puts the whole column on the text path, so the order stays defined.
eq(sortColumn(['10','9','1abc']), ['10','1abc','9'],
   'a column that only looks numeric is not treated as numeric');

eq(sortColumn(['10.00', null, '2.00']), ['2.00','10.00',null],
   'NULLs sort last and do not make the column non-numeric');

eq(sortColumn(['alpha','beta','alphabet'], { filters: { 0: 'alpha' } }), ['alpha','alphabet'],
   'filtering still narrows the view');


// The toolbar's search: rows holding the text in any column, ignoring case; NULL never matches, an
// empty search keeps everything, and a column filter still has to match as well.
function search(rows, q, filters = {}) {
  const tab = { rows, filters, sortCol: -1, sortDir: 1, search: q };
  const viewIndices = new Function('T', `${rowHasTextSrc}
${viewIndicesSrc}
return viewIndices;`)(() => tab);
  return viewIndices('t1');
}
const people = [['1','Alice','Zurich'], ['2','Bob','Bern'], ['3','Carol','ZUG'], ['4',null,'Basel']];
eq(search(people, 'zu'), [0,2], 'the search keeps the rows holding the text in any column, ignoring case');
eq(search(people, 'nobody'), [], 'a search nothing holds keeps no rows');
eq(search([['a',null],['b','null']], ''), [0,1], 'an empty search keeps every row');
eq(search([['a',null],['b','null']], 'null'), [1], 'a NULL never matches the search');
eq(search([['alpha','x'],['alpha','y'],['beta','x']], 'x', { 0: 'alpha' }), [0],
   'the search and a column filter must both match');


// Enter / Shift+Enter in the search box: which cell it goes to next.
function stepper(rows, q, extra = {}) {
  const tab = { rows, filters: {}, sortCol: -1, sortDir: 1, search: q, ...extra };
  const gridFocus = {};
  const make = new Function('T', 'gridFocus', 'gridSetFocus', 'updatePager', '$',
    `${rowHasTextSrc}
${viewIndicesSrc}
${stepSrc}
return gridSearchStep;`);
  const step = make(() => tab, gridFocus, (id, ri, ci) => { gridFocus[id] = { ri, ci }; }, () => {}, () => ({ focus() {} }));
  return dir => { step('t1', dir); const f = gridFocus.t1; return [f.ri, f.ci, ...tab._hitAt]; };
}
{
  const step = stepper([['zug','x'], ['y','y'], ['a','Zurich']], 'zu');
  eq([step(1), step(1), step(1), step(-1)], [[0,0,1,2], [2,1,2,2], [0,0,1,2], [2,1,2,2]],
     'Enter goes through the matching cells in order, and wraps round');
  const step2 = stepper([['zu','zu','old']], 'zu', { hiddenCols: new Set([0]), pending: { upd: { '0:2': 'zulu' } } });
  eq([step2(1), step2(1)], [[0,1,1,2], [0,2,2,2]], 'a hidden column is stepped over, and an edit is what is searched');
}


// The status line's "LIMIT n in the query": only a LIMIT at the end of the statement limits the
// result, and it reads the row count (LIMIT offset,n and LIMIT n OFFSET m alike).
{
  const trailingLimit = new Function(`${extractFunction(src, 'trailingLimit')}
return trailingLimit;`)();
  const cases = [
  ['SELECT * FROM t LIMIT 1000', 1000],
  ['select * from t limit 10, 20;', 20],
  ['SELECT * FROM t LIMIT 5 OFFSET 10 ;  ', 5],
  ['SELECT * FROM t WHERE id IN (SELECT id FROM u LIMIT 3)', null],
  ['SELECT * FROM (SELECT 1 LIMIT 3) x', null],
  ['SELECT * FROM t', null],
  ['SELECT limit_col FROM t', null],
];
  eq(cases.map(([q]) => trailingLimit(q)), cases.map(c => c[1]), 'only a trailing LIMIT limits the result, read as its row count');
}

process.exit(fail ? 1 : 0);
'@

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "viewindices-harness-$PID.mjs"
try {
  Set-Content -LiteralPath $tmp -Value $harness -Encoding utf8
  & node $tmp (Resolve-Path $ScriptPath).Path
  $code = $LASTEXITCODE
} finally {
  Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}
if ($code -ne 0) { "`n  FAILED"; exit 1 } else { "`n  all passed"; exit 0 }
