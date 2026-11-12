# Tests for the order a set of dump files is imported in (Get-DumpImportOrder), the same as
# nobs-sql-editor's dump_import_order tests in src-tauri/src/main.rs.
#
# A per-table export folder went in by name: a view that reads a view whose name sorts after it
# failed with 1146 and was left out of the restore, and the routines file ran before the tables
# that sort after it, so an event could start running before its tables were there.
#
# Dump files are written as mysqldump and mariadb-dump write them, read back through
# Get-DumpFileInfo, and put in every order a folder or a pick of files can hand them over in. Each
# file also carries a model of what importing it does: what each of its statements needs to be
# there and what it makes. Running the model in the order Import chose decides whether the restore
# is complete, as a server would: a view needs what it reads, a trigger its table, an event its
# tables (it can run the moment it is made), and a file stops at its first error.
#
#   pwsh -NoProfile -File tests/ImportOrder.Tests.ps1 ./NOBSSQL.ps1

param([Parameter(Mandatory)][string]$ScriptPath)

$ErrorActionPreference = 'Stop'

$e=$null;$t=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $ScriptPath).Path,[ref]$t,[ref]$e)
if($e -and $e.Count){ $e | ForEach-Object { "  PARSE ERROR  line $($_.Extent.StartLineNumber): $($_.Message)" }; exit 1 }
$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                        $n.Name -in @('Get-DumpKind','Get-DumpViewOf','Get-DumpFileInfo','Get-DumpImportOrder','Get-DumpFilesInImportOrder')},$true) | ForEach-Object { Invoke-Expression $_.Extent.Text }

$fail = 0
function Check($cond, $label, $detail) { if ($cond) { "  ok    $label" } else { "  FAIL  $label$(if($detail){" -> $detail"})"; $script:fail++ } }

$dir = Join-Path ([IO.Path]::GetTempPath()) "nobs-import-order-$PID"
Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $dir | Out-Null

$HEAD = "-- MySQL dump 10.13  Distrib 8.4.9, for Win64 (x86_64)`n--`n-- Host: 127.0.0.1    Database: d`n-- ------------------------------------------------------`n`n/*!40101 SET NAMES utf8mb4 */;`n/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;`n`n"
$TAIL = "/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;`n`n-- Dump completed on 2026-11-07 10:00:00`n"
function Q($db, $n) { "$db.$n" }
# A step: what a statement needs to be there, and what it makes.
function Step($needs, $makes) { [pscustomobject]@{ Needs = [string[]]@($needs); Makes = [string[]]@($makes) } }

function TableFile($db, $t, $trigger) {
    $text = "$HEAD--`n-- Table structure for table ``$t```n--`n`nDROP TABLE IF EXISTS ``$t``;`nCREATE TABLE ``$t`` (`n  ``id`` int NOT NULL,`n  PRIMARY KEY (``id``)`n);`n`n--`n-- Dumping data for table ``$t```n--`n`nLOCK TABLES ``$t`` WRITE;`nINSERT INTO ``$t`` VALUES (1),(2);`nUNLOCK TABLES;`n"
    $steps = @(Step @() @(Q $db $t))
    if ($trigger) {
        $text += "/*!50003 CREATE*/ /*!50017 DEFINER=``root``@``localhost``*/ /*!50003 TRIGGER ``$trigger`` BEFORE INSERT ON ``$t`` FOR EACH ROW SET @x=1 */;;`n"
        $steps += Step @(Q $db $t) @(Q $db $trigger)
    }
    @{ Text = $text + $TAIL; Steps = $steps }
}
# reads: what the final definition selects from; calls: functions it calls.
function ViewFile($db, $v, $reads, $calls, $flavor) {
    $id = $v.Replace('`', '``')
    $stub = if ($flavor -eq 'MySql') { 'Temporary view structure for view' } else { 'Temporary table structure for view' }
    $from = (@($reads) | ForEach-Object { '`' + $_.Replace('`', '``') + '`' }) -join ' join '
    $cols = (@(@($calls) | Where-Object { $_ } | ForEach-Object { "``$db``.``$_``() AS ``$($_)_v``" }) + @('1 AS `one`')) -join ','
    $text = "$HEAD--`n-- $stub ``$id```n--`n`nDROP TABLE IF EXISTS ``$id``;`n/*!50001 DROP VIEW IF EXISTS ``$id``*/;`n/*!50001 CREATE VIEW ``$id`` AS SELECT `n 1 AS ``one``*/;`n`n--`n-- Final view structure for view ``$id```n--`n`n/*!50001 DROP VIEW IF EXISTS ``$id``*/;`n/*!50001 CREATE ALGORITHM=UNDEFINED */`n/*!50013 DEFINER=``root``@``localhost`` SQL SECURITY DEFINER */`n/*!50001 VIEW ``$id`` AS select $cols from $from */;`n$TAIL"
    $needs = @(@($reads) + @(@($calls) | Where-Object { $_ })) | ForEach-Object { Q $db $_ }
    @{ Text = $text; Steps = @((Step @() @(Q $db $v)), (Step $needs @(Q $db $v))) }
}
# events: @(name, @(tables it uses)); routines: @(kind, name).
function RoutinesFile($db, $events, $routines) {
    $text = $HEAD; $steps = @()
    if (@($events).Count) {
        $text += "--`n-- Dumping events for database '$db'`n--`n"
        foreach ($ev in $events) {
            $text += "/*!50106 CREATE*/ /*!50117 DEFINER=``root``@``localhost``*/ /*!50106 EVENT ``$($ev[0])`` ON SCHEDULE EVERY 1 HOUR STARTS '2026-11-07 10:00:00' ON COMPLETION NOT PRESERVE ENABLE DO DELETE FROM ``$($ev[1][0])`` WHERE id < 0 */ ;;`n"
            $steps += Step @($ev[1] | ForEach-Object { Q $db $_ }) @(Q $db $ev[0])
        }
    }
    if (@($routines).Count) {
        $text += "`n--`n-- Dumping routines for database '$db'`n--`n"
        foreach ($r in $routines) {
            $text += "/*!50003 DROP $($r[0]) IF EXISTS ``$($r[1])`` */;`nDELIMITER ;;`nCREATE DEFINER=``root``@``localhost`` $($r[0]) ``$($r[1])``() SELECT 1 ;;`nDELIMITER ;`n"
            $steps += Step @() @(Q $db $r[1])
        }
    }
    @{ Text = $text + $TAIL; Steps = $steps }
}
function Sim($name, $f) {
    $p = Join-Path $dir $name
    [IO.File]::WriteAllText($p, $f.Text, (New-Object Text.UTF8Encoding($false)))
    [pscustomobject]@{ Name = $name; Path = $p; Text = $f.Text; Steps = @($f.Steps); Info = (Get-DumpFileInfo $p) }
}
# A per-table export of one database: three tables, two with a trigger; an event that uses two of
# the tables, a function and a procedure; a chain of views, one read across it the other way round
# by name, one that calls the function, and one with a backquote in its name.
function PerTableExport($db, $flavor) {
    $f = { param($n) "$db.$n.sql" }
    @(
        (Sim (& $f 'customers') (TableFile $db 'customers' $null)),
        (Sim (& $f 'orders') (TableFile $db 'orders' 'tr_orders')),
        (Sim (& $f 'zeta') (TableFile $db 'zeta' 'tr_zeta')),
        (Sim (& $f 'routines_events') (RoutinesFile $db @(,@('ev_one', @('zeta', 'orders'))) @(@('FUNCTION', 'fn_one'), @('PROCEDURE', 'pr_one')))),
        (Sim (& $f 'a_view') (ViewFile $db 'a_view' @('m_view') @() $flavor)),
        (Sim (& $f 'm_view') (ViewFile $db 'm_view' @('z_view', 'customers') @('fn_one') $flavor)),
        (Sim (& $f 'z_view') (ViewFile $db 'z_view' @('orders') @() $flavor)),
        (Sim (& $f 'q`v') (ViewFile $db 'q`v' @('a_view') @() $flavor))
    )
}
# Runs the model in this order: the names of the files that failed, each with what it lacked.
# Called as @(Simulate ...).
function Simulate($files) {
    $there = New-Object 'System.Collections.Generic.HashSet[string]'
    $failed = @()
    foreach ($f in $files) {
        foreach ($st in $f.Steps) {
            $missing = $st.Needs | Where-Object { -not $there.Contains($_) } | Select-Object -First 1
            if ($missing) { $failed += "$($f.Name) (needs $missing)"; break }
            foreach ($m in $st.Makes) { [void]$there.Add($m) }
        }
    }
    $failed   # one line per failed file; nothing when all went in
}
# The order Import chose, for files handed over in this order.
function Ordered($in) { $o = Get-DumpImportOrder @($in | ForEach-Object { $_.Info }); , @($o | ForEach-Object { $in[$_] }) }
# What must hold for any input order, with or without files Import cannot tell (Other): every file
# runs once; the routines files after every table file and the views after everything else; tables
# keep their order, and so do the files that are neither tables nor views; and a table that ran
# before a script still does. The empty string when it all holds, else what did not.
function Invariants($in, $out) {
    $inNames = @($in | ForEach-Object Name); $outNames = @($out | ForEach-Object Name)
    if ((($inNames | Sort-Object) -join '|') -ne (($outNames | Sort-Object) -join '|')) { return "not every file once: $($outNames -join ',')" }
    $kind = @{}; foreach ($f in $in) { $kind[$f.Name] = $f.Info.Kind }
    $pos = @{}; for ($i = 0; $i -lt $outNames.Count; $i++) { $pos[$outNames[$i]] = $i }
    $lastTable = -1; for ($i = 0; $i -lt $outNames.Count; $i++) { if ($kind[$outNames[$i]] -eq 'Tables') { $lastTable = $i } }
    $seenView = $false
    for ($i = 0; $i -lt $outNames.Count; $i++) {
        $k = $kind[$outNames[$i]]
        if ($k -eq 'Routines' -and $lastTable -gt $i) { return "$($outNames[$i]) before a table: $($outNames -join ',')" }
        if ($k -eq 'View') { $seenView = $true } elseif ($seenView) { return "a view before $($outNames[$i]): $($outNames -join ',')" }
    }
    $keep = { param($pick) ((@($inNames | Where-Object { & $pick $kind[$_] }) -join '|') -eq (@($outNames | Where-Object { & $pick $kind[$_] }) -join '|')) }
    if (-not (& $keep { param($k) $k -eq 'Tables' })) { return "tables reordered: $($outNames -join ',')" }
    if (-not (& $keep { param($k) $k -eq 'Routines' -or $k -eq 'Other' })) { return "routines or scripts reordered: $($outNames -join ',')" }
    for ($i = 0; $i -lt $inNames.Count; $i++) {
        if ($kind[$inNames[$i]] -ne 'Tables') { continue }
        for ($j = $i + 1; $j -lt $inNames.Count; $j++) {
            if ($kind[$inNames[$j]] -eq 'Other' -and $pos[$inNames[$i]] -gt $pos[$inNames[$j]]) { return "table $($inNames[$i]) moved after $($inNames[$j]): $($outNames -join ',')" }
        }
    }
    ''
}
# A seeded shuffle (xorshift, as the Rust tests), so a failure can be run again.
function Shuffled($files, [ref]$seed) {
    $a = [object[]]@($files)
    for ($i = $a.Count - 1; $i -ge 1; $i--) {
        $s = [uint64]$seed.Value
        $s = $s -bxor ($s -shl 13); $s = $s -bxor ($s -shr 7); $s = $s -bxor ($s -shl 17)
        $seed.Value = $s
        $j = [int]($s % [uint64]($i + 1)); $x = $a[$i]; $a[$i] = $a[$j]; $a[$j] = $x
    }
    , $a
}
# Every order of these files (Heap's algorithm), each handed to $f; how many there were.
function EachOrder($files, [scriptblock]$f) {
    $a = [object[]]@($files); $c = New-Object int[] $a.Count; $n = 1
    & $f $a
    $i = 0
    while ($i -lt $a.Count) {
        if ($c[$i] -lt $i) {
            if ($i % 2 -eq 0) { $x = $a[0]; $a[0] = $a[$i]; $a[$i] = $x } else { $x = $a[$c[$i]]; $a[$c[$i]] = $a[$i]; $a[$i] = $x }
            & $f $a; $n++; $c[$i]++; $i = 0
        } else { $c[$i] = 0; $i++ }
    }
    $n
}
function ByName($files) { , [object[]]@($files | Sort-Object { $_.Name } -Culture '' -CaseSensitive) }
function Names($files) { (@($files | ForEach-Object Name)) -join ',' }

try {
    # --- The files are told by what is in them, not by their names ---------------------------------
    $files = PerTableExport 'd' 'MySql'
    Check ((@($files | ForEach-Object { $_.Info.Kind }) -join ',') -eq 'Tables,Tables,Tables,Routines,View,View,View,View') 'tables, routines and views are told apart' (@($files | ForEach-Object { "$($_.Name)=$($_.Info.Kind)" }) -join ' ')
    Check ($files[7].Info.View -ceq 'q`v') 'a backquote in a view''s name' $files[7].Info.View
    $renamedOk = $true
    foreach ($f in $files) {
        $p = Join-Path $dir "renamed_$($f.Name.Length).sql"
        [IO.File]::WriteAllText($p, $f.Text)
        if ((Get-DumpFileInfo $p).Kind -ne $f.Info.Kind) { $renamedOk = $false }
    }
    Check $renamedOk 'the same text under a name that says otherwise is told the same'
    Check ((Get-DumpKind "--`n-- Dumping routines for database 'd'`n--`n") -eq 'Routines') 'routines without events'
    Check ((Get-DumpKind "--`n-- Dumping events for database 'd'`n--`n") -eq 'Routines') 'events without routines'
    Check ((Get-DumpKind '') -eq 'Other') 'an empty file'
    Check ((Get-DumpKind "UPDATE t SET a = 1;`n-- Table structure for a later look`n") -eq 'Other') 'a script of the user''s own'
    Check ((Get-DumpKind "INSERT INTO t VALUES ('\n-- Table structure for table ``x``');`n") -eq 'Other') 'a heading inside a value is not one'
    Check ((Get-DumpKind "--`n-- Structure for view ``v```n--`nCREATE VIEW v AS SELECT 1;`n") -eq 'Other') 'another tool''s view heading'
    Check ((Get-DumpKind "--`r`n-- Table structure for table ``t```r`n--`r`n") -eq 'Tables') 'CRLF line ends'
    # A whole-database dump whose first object in the alphabet is a view: the view's stand-in comes
    # first, the tables after it, and its own routines and views at the end.
    $whole = "$HEAD--`n-- Temporary view structure for view ``a_view```n--`n`n--`n-- Table structure for table ``customers```n--`n`n--`n-- Dumping events for database 'd'`n--`n`n--`n-- Final view structure for view ``a_view```n--`n$TAIL"
    Check ((Get-DumpKind $whole) -eq 'Tables') 'a whole dump that opens with a view''s stand-in is run as the one file it is'
    Check ((Get-DumpKind "--`n-- Dumping data for table ``t```n--`n") -eq 'Tables') 'a data-only dump'
    $late = Join-Path $dir 'late.sql'
    [IO.File]::WriteAllText($late, ("-- padding`n" * 7000) + "`n-- Table structure for table ``t```n")
    Check ((Get-DumpFileInfo $late).Kind -eq 'Other') 'a heading further in than the first 64 KB is not looked for'
    Check ((Get-DumpFileInfo (Join-Path $dir 'gone.sql')).Kind -eq 'Other') 'a file that is not there is Other, and the import reports it missing'

    # --- A per-table export imports completely, whatever order its files come in -------------------
    # Every order for MySQL's files; for MariaDB's, which differ only in the view stand-in's
    # heading, a seeded sample - every order of both took three minutes.
    foreach ($flavor in 'MySql', 'MariaDb') {
        $files = PerTableExport 'd' $flavor
        Check (@(Simulate (ByName $files)).Count -gt 0) "$flavor : in name order, without reordering, the restore is incomplete"
        $script:bad = $null
        $one = {
            param($in)
            if ($script:bad) { return }
            $out = Ordered $in
            $why = Invariants $in $out
            if (-not $why) { $f = @(Simulate $out); if ($f.Count) { $why = "$($f -join '; ') for $(Names $in)" } }
            if ($why) { $script:bad = $why }
        }
        if ($flavor -eq 'MySql') {
            $n = EachOrder $files $one
            Check ($n -eq 40320 -and -not $script:bad) "$flavor : every order of the eight files ($n) restores completely" $script:bad
        } else {
            $seed = [uint64]'0x3c6ef372fe94f82b'
            for ($k = 0; $k -lt 3000 -and -not $script:bad; $k++) { & $one (Shuffled $files ([ref]$seed)) }
            Check (-not $script:bad) "$flavor : 3,000 seeded orders of the eight files restore completely" $script:bad
        }
    }

    # --- Scripts and files it cannot tell keep their place -----------------------------------------
    $files = @(PerTableExport 'd' 'MySql')
    # A script that sets things up first, one that fixes data after the routines, and one that runs
    # at the very end and needs the procedure and the last table.
    $files += Sim '00_setup.sql' @{ Text = "CREATE TABLE helper (id INT);`n"; Steps = @(Step @() @('d.helper')) }
    $files += Sim 'd.s_fix.sql' @{ Text = "CALL pr_one();`n"; Steps = @(Step @('d.pr_one') @()) }
    $files += Sim 'zz_after.sql' @{ Text = "CALL pr_one();`nINSERT INTO zeta VALUES (9);`n"; Steps = @(Step @('d.pr_one', 'd.zeta', 'd.helper') @()) }
    $byName = ByName $files
    $out = Ordered $byName
    Check ((Names $out) -ceq '00_setup.sql,d.customers.sql,d.orders.sql,d.zeta.sql,d.routines_events.sql,d.s_fix.sql,zz_after.sql,d.z_view.sql,d.m_view.sql,d.a_view.sql,d.q`v.sql') 'scripts keep their place among the routines, tables move ahead of the routines, views go last in the order they read each other' (Names $out)
    Check (@(Simulate $out).Count -eq 0) 'and the restore is complete' (@(Simulate $out) -join '; ')
    $seed = [uint64]'0x9e3779b97f4a7c15'; $bad = ''
    for ($k = 0; $k -lt 2000 -and -not $bad; $k++) { $in = Shuffled $files ([ref]$seed); $bad = Invariants $in (Ordered $in) }
    Check (-not $bad) 'in 2,000 seeded shuffles with scripts, the order keeps its rules' $bad

    # --- Several databases and other tools' files together ------------------------------------------
    $files = @(PerTableExport 'd1' 'MySql') + @(PerTableExport 'd2' 'MariaDb')
    # A view in d2 that reads one in d1: the name match carries no database, so it waits for both
    # a_views, which only costs it a place.
    $cross = ViewFile 'd2' 'cross' @('a_view') @() 'MySql'; $cross.Steps[1].Needs = [string[]]@('d1.a_view')
    $files += Sim 'd2.cross.sql' $cross
    # Files another tool wrote: phpMyAdmin's view heading is not one Import knows, its table
    # headings are mysqldump's.
    $files += Sim 'pma_view.sql' @{ Text = "--`n-- Structure for view ``pv```n--`nCREATE VIEW pv AS SELECT 1;`n"; Steps = @(Step @() @('x.pv')) }
    $files += Sim 'pma_table.sql' @{ Text = "--`n-- Table structure for table ``pt```n--`nCREATE TABLE pt (id INT);`n--`n-- Dumping data for table ``pt```n--`n"; Steps = @(Step @() @('x.pt')) }
    Check ($files[-2].Info.Kind -eq 'Other' -and $files[-1].Info.Kind -eq 'Tables') 'another tool''s view is Other, its table a table'
    $out = Ordered (ByName $files)
    Check (@(Simulate $out).Count -eq 0) 'two databases and other tools'' files restore completely in name order' (Names $out)
    $seed = [uint64]'0x2545f4914f6cdd1d'; $bad = ''
    for ($k = 0; $k -lt 2000 -and -not $bad; $k++) {
        $in = Shuffled $files ([ref]$seed); $out = Ordered $in
        $bad = Invariants $in $out
        if (-not $bad) { $f = @(Simulate $out); if ($f.Count) { $bad = "$($f -join '; ') for $(Names $in)" } }
    }
    Check (-not $bad) 'and in 2,000 seeded shuffles of the twenty files' $bad

    # --- What cannot be ordered is kept, and nothing is lost ---------------------------------------
    $x = Sim 'x.sql' (ViewFile 'd' 'x' @('y') @() 'MySql'); $y = Sim 'y.sql' (ViewFile 'd' 'y' @('x') @() 'MySql')
    Check ((Names (Ordered @($x, $y))) -eq 'x.sql,y.sql' -and (Names (Ordered @($y, $x))) -eq 'y.sql,x.sql') 'two views that seem to read each other stay in the order given'
    $files = PerTableExport 'd' 'MySql'
    $out = Ordered @($files | Where-Object { $_.Info.Kind -ne 'Routines' })
    Check ((Names $out[0..2]) -eq 'd.customers.sql,d.orders.sql,d.zeta.sql') 'without a routines file only the views move'
    Check ((Names (Ordered $files)[0..3]) -eq 'd.customers.sql,d.orders.sql,d.zeta.sql,d.routines_events.sql') 'routines already after every table: nothing moves'
    # A view whose column has another view's name waits for it needlessly, and still restores.
    $col = Sim 'c.sql' @{ Text = "--`n-- Final view structure for view ``c```n--`nVIEW ``c`` AS select ``customers``.``id`` AS ``z_view`` from ``customers```n"; Steps = @(Step @('d.customers') @('d.c')) }
    $out = Ordered (@($col) + @($files))
    $on = @($out | ForEach-Object Name)
    Check ($on.IndexOf('c.sql') -gt $on.IndexOf('d.z_view.sql') -and @(Simulate $out).Count -eq 0) 'a column named like a view only costs a place' ($on -join ',')
    Check ((Get-DumpFilesInImportOrder ([string[]]@($files[4].Path, $files[0].Path))) -join ',' -eq "$($files[0].Path),$($files[4].Path)") 'Get-DumpFilesInImportOrder hands back the paths in that order'
    Check (@(Get-DumpFilesInImportOrder ([string[]]@($files[0].Path))).Count -eq 1) 'and one file is one file'
} finally {
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail) { "`n  $fail FAILED"; exit 1 } else { "`n  all passed"; exit 0 }
