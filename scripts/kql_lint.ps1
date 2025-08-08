param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Path,
  [int]$MaxProjectColumns = 0
)

$ErrorActionPreference = "Stop"

# Load rules from repo root if present
$repoRulesPath = Join-Path -Path (Get-Location) -ChildPath ".kql-lint-rules.json"
$rules = @{
  require_summarize_or_bin = $true
  max_project_columns = 12
  max_take_rows = 5000
}
if (Test-Path $repoRulesPath) {
  try {
    $json = Get-Content -Raw -Path $repoRulesPath | ConvertFrom-Json
    if ($null -ne $json.require_summarize_or_bin) { $rules.require_summarize_or_bin = [bool]$json.require_summarize_or_bin }
    if ($null -ne $json.max_project_columns) { $rules.max_project_columns = [int]$json.max_project_columns }
    if ($null -ne $json.max_take_rows) { $rules.max_take_rows = [int]$json.max_take_rows }
  } catch {
    Write-Warning "Failed to parse .kql-lint-rules.json. Using defaults."
  }
}
if ($MaxProjectColumns -gt 0) { $rules.max_project_columns = $MaxProjectColumns }

function Get-KqlFiles($p) {
  if (Test-Path $p -PathType Container) {
    return Get-ChildItem -Path $p -Recurse -Filter *.kql | Select-Object -ExpandProperty FullName
  } elseif (Test-Path $p -PathType Leaf) {
    return ,(Resolve-Path $p).Path
  } else {
    # Try glob from working dir
    return Get-ChildItem -Path . -Recurse -Filter *.kql | Select-Object -ExpandProperty FullName
  }
}

$files = Get-KqlFiles -p $Path
if (-not $files -or $files.Count -eq 0) {
  Write-Error "No .kql files found for path: $Path"
  exit 1
}

$failed = @()
foreach ($f in $files) {
  $content = Get-Content -Raw -Path $f
  $fileFailed = $false
  $reasons = @()

  if ($rules.require_summarize_or_bin) {
    if (($content -notmatch '\|\s*summarize\b') -and ($content -notmatch '\bbin\s*\(') -and ($content -notmatch '\bmake-series\b')) {
      $fileFailed = $true
      $reasons += "missing summarize/bin/make-series"
    }
  }

  # Enforce projection column limit on '| project' (not project-away)
  $projectMatches = [System.Text.RegularExpressions.Regex]::Matches($content, '\|\s*project(?!-away)\b([^\n;]+)')
  foreach ($m in $projectMatches) {
    $colsPart = $m.Groups[1].Value
    # Remove comments and trailing pipes
    $colsPart = $colsPart -replace '//.*$', ''
    # Count columns by comma; allow aliases 'col = expr'
    $cols = ($colsPart -split ',').Where({ $_.Trim() -ne '' }).Count
    if ($cols -gt $rules.max_project_columns) {
      $fileFailed = $true
      $reasons += "project columns $cols > limit $($rules.max_project_columns)"
    }
  }

  # Guard extremely large take
  $takeMatches = [System.Text.RegularExpressions.Regex]::Matches($content, '\|\s*take\s+(\d+)')
  foreach ($m in $takeMatches) {
    $n = [int]$m.Groups[1].Value
    if ($n -gt $rules.max_take_rows) {
      $fileFailed = $true
      $reasons += "take $n > max $($rules.max_take_rows)"
    }
  }

  if ($fileFailed) {
    $failed += @{ file = $f; reasons = $reasons }
  }
}

if ($failed.Count -gt 0) {
  Write-Host "KQL Lint Failures:" -ForegroundColor Red
  foreach ($i in $failed) {
    Write-Host (" - " + $i.file + ": " + ($i.reasons -join '; ')) -ForegroundColor Red
  }
  exit 2
} else {
  Write-Host "KQL lint passed for $($files.Count) file(s)." -ForegroundColor Green
  exit 0
}