$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path ".").Path
$tmp = Join-Path $repoRoot ".tmp\kql-lint-tests"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$passFile = Join-Path $tmp "pass.kql"
$failFile = Join-Path $tmp "fail.kql"

@'
Heartbeat
| where TimeGenerated > ago(24h)
| summarize lastSeen=max(TimeGenerated) by ResourceId
| project ResourceId, lastSeen
'@ | Set-Content -Path $passFile -Encoding UTF8

@'
Heartbeat
| where TimeGenerated > ago(24h)
| where Computer != "" // no summarize nor bin
| project a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q
| take 999999
'@ | Set-Content -Path $failFile -Encoding UTF8

$lintPath = Join-Path $repoRoot "scripts\kql_lint.ps1"
Write-Host "Running lint on passing file..."
powershell -NoProfile -File $lintPath -Path $passFile
$passExit = $LASTEXITCODE

Write-Host "Running lint on failing file..."
powershell -NoProfile -File $lintPath -Path $failFile
$failExit = $LASTEXITCODE

if ($passExit -ne 0) { Write-Host "Expected pass.kql to pass but exit code was $passExit" -ForegroundColor Red; exit 1 }
if ($failExit -eq 0) { Write-Host "Expected fail.kql to fail but exit code was $failExit" -ForegroundColor Red; exit 1 }

Write-Host "kql_lint tests passed." -ForegroundColor Green
exit 0