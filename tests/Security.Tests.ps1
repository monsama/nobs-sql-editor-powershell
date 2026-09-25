# Tests for the checks the local server makes before it acts on a request: the token, the paths it
# will run or read, and the release page it opens.
#
#   pwsh -NoProfile -File tests/Security.Tests.ps1 ./NOBSSQL.ps1

param([Parameter(Mandatory)][string]$ScriptPath)

$ErrorActionPreference = 'Stop'

$e=$null;$t=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $ScriptPath).Path,[ref]$t,[ref]$e)
if($e -and $e.Count){ $e | ForEach-Object { "  PARSE ERROR  line $($_.Extent.StartLineNumber): $($_.Message)" }; exit 1 }
$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $n.Name -in @('Test-ApiToken','Test-ToolPathName','Test-DataPathBad','Test-ReleasePageOk')},$true) | ForEach-Object { Invoke-Expression $_.Extent.Text }

$fail = 0
function Check($cond, $label, $detail) { if ($cond) { "  ok    $label" } else { "  FAIL  $label$(if($detail){" -> $detail"})"; $script:fail++ } }

"-- the token --"
$Token = [Guid]::NewGuid().ToString('N')
Check (Test-ApiToken ([pscustomobject]@{ token = $Token })) 'the right token is accepted'
# -ne against an array filters the array instead of comparing: {"token":[]} used to pass.
Check (-not (Test-ApiToken ('{"token":[]}' | ConvertFrom-Json))) 'an empty array is not a token'
Check (-not (Test-ApiToken ('{"token":["x"]}' | ConvertFrom-Json))) 'nor an array with something in it'
Check (-not (Test-ApiToken ([pscustomobject]@{ token = $Token.ToUpper() + 'x' }))) 'a longer one is refused'
Check (-not (Test-ApiToken ([pscustomobject]@{ token = ('0' * 32) }))) 'a wrong one of the right length is refused'
Check (-not (Test-ApiToken ([pscustomobject]@{}))) 'no token is refused'
Check (-not (Test-ApiToken $null)) 'no body is refused'

"-- tools --"
Check ($null -eq (Test-ToolPathName 'C:\x\mysql.exe' 'mysql')) 'mysql.exe as mysql'
Check ($null -eq (Test-ToolPathName 'C:\x\mariadb-dump.exe' 'mysqldump')) 'mariadb-dump.exe as mysqldump'
Check ($null -ne (Test-ToolPathName 'C:\Windows\System32\cmd.exe' 'x')) 'another kind of tool is refused'
Check ($null -ne (Test-ToolPathName 'C:\Windows\System32\cmd.exe' 'mysql')) 'cmd.exe is not mysql'
Check ($null -ne (Test-ToolPathName '\\nas\share\mysql.exe' 'mysql')) 'not from a network share'
Check ($null -ne (Test-ToolPathName '//nas/share/mysql.exe' 'mysql')) 'nor spelled with slashes'
Check ($null -ne (Test-ToolPathName 'C:\x\mysql.bat' 'mysql')) 'a tool is an .exe'

"-- data paths --"
foreach ($p in '\\.\PhysicalDrive0', '\\?\C:\x.sql', '//./pipe/x', 'C:\a\nul.txt', 'C:\con') { Check (Test-DataPathBad $p) "refused: $p" }
foreach ($p in 'C:\a\b.sql', '\\nas\share\backup.sql', 'D:\exports') { Check (-not (Test-DataPathBad $p)) "allowed: $p" }

"-- the release page --"
$script:ReleasesRepo = 'owner/repo'
Check (Test-ReleasePageOk 'https://github.com/owner/repo/releases/tag/v1.5.0') 'this project''s release'
Check (-not (Test-ReleasePageOk 'https://evil.example/owner/repo/releases/tag/v1.5.0')) 'not another host'
Check (-not (Test-ReleasePageOk 'https://github.com/other/repo/releases/tag/v1.5.0')) 'not another project'
Check (-not (Test-ReleasePageOk 'javascript:alert(1)')) 'not a script'

if ($fail) { "`n  $fail FAILED"; exit 1 } else { "`n  all passed"; exit 0 }
