param(
  [string]$WorkspaceId = $env:WORKSPACE_ID,
  [string]$Timespan = "PT1H"
)
$ErrorActionPreference = "Stop"

function Skip($msg) { Write-Warning $msg; exit 0 }

if (-not $WorkspaceId) { Skip "WORKSPACE_ID not provided. Skipping KQL smoke tests." }
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Skip "Azure CLI not found. Skipping KQL smoke tests." }

Write-Host "Running KQL smoke tests against workspace: $WorkspaceId" -ForegroundColor Cyan

$tests = @(
  @{ name = "table_freshness"; path = "kql/lib/table_freshness.kql"; expectCols = @("TableName","lastIngested","rows","latencyMin","thresholdMin","status") },
  @{ name = "inventory_by_scope"; path = "kql/lib/inventory_by_scope.kql"; expectCols = @("SubscriptionId","ResourceType","Count","LastSeen") }
)

$fail = $false
foreach ($t in $tests) {
  if (-not (Test-Path $t.path)) {
    Write-Host "Skip $($t.name): file not found $($t.path)" -ForegroundColor Yellow
    continue
  }
  $query = Get-Content -Raw -Path $t.path

  try {
    $respJson = az monitor log-analytics query --workspace $WorkspaceId --analytics-query "$query" --timespan $Timespan --out json
    $resp = $respJson | ConvertFrom-Json
  } catch {
    Write-Host "Smoke test failed for $($t.name): Azure CLI error - $($_.Exception.Message)" -ForegroundColor Red
    $fail = $true
    continue
  }

  if ($null -eq $resp.tables -or $resp.tables.Count -eq 0) {
    Write-Host "Smoke test failed for $($t.name): no tables returned." -ForegroundColor Red
    $fail = $true
    continue
  }

  $table = $resp.tables[0]
  $cols = @($table.columns | ForEach-Object { $_.name })
  $rows = $table.rows

  if ($rows.Count -eq 0) {
    Write-Host "Smoke test failed for $($t.name): empty result." -ForegroundColor Red
    $fail = $true
    continue
  }

  foreach ($c in $t.expectCols) {
    if ($cols -notcontains $c) {
      Write-Host "Smoke test failed for $($t.name): expected column '$c' not found. Got: $($cols -join ', ')" -ForegroundColor Red
      $fail = $true
      break
    }
  }

  if (-not $fail) {
    Write-Host "[OK] $($t.name) returned rows with expected columns." -ForegroundColor Green
  }
}

if ($fail) { exit 2 } else { exit 0 }