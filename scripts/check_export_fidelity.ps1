param(
  [Parameter(Mandatory = $true)]
  [string]$ExportPath
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ExportPath -PathType Leaf)) {
  Write-Error "Exported workbook JSON not found at: $ExportPath"
  exit 1
}

try {
  $jsonText = Get-Content -Raw -Path $ExportPath
  $json = $jsonText | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Error "Invalid JSON: $($_.Exception.Message)"
  exit 2
}

$fail = $false
$reasons = New-Object System.Collections.Generic.List[string]

# Required top-level blocks
foreach ($k in @("version","metadata","parameters","items")) {
  if (-not $json.PSObject.Properties.Name -contains $k) {
    $fail = $true; $reasons.Add("missing top-level key: $k")
  }
}

# Parameters fidelity
$requiredParams = @("timeRange","mgScope","subscriptionIds","resourceGroups","environmentTag","workspaces","serviceToggles")
foreach ($p in $requiredParams) {
  if (-not $json.parameters.PSObject.Properties.Name -contains $p) {
    $fail = $true; $reasons.Add("missing parameter: $p")
  }
}

# Hidden steps fidelity (either exported inline or referenced)
if (-not $json.hiddenSteps -or $json.hiddenSteps.Count -eq 0) {
  $fail = $true; $reasons.Add("hiddenSteps[] missing")
} else {
  foreach ($hs in $json.hiddenSteps) {
    if (-not $hs.name) { $fail = $true; $reasons.Add("hiddenStep missing name") }
    if (-not $hs.kqlRef) { $fail = $true; $reasons.Add("hiddenStep '$($hs.name)' missing kqlRef") }
  }
}

# Items basic checks
if (-not $json.items -or $json.items.Count -eq 0) {
  $fail = $true; $reasons.Add("no items[] found")
} else {
  $paramPanel = $json.items | Where-Object { $_.type -eq "parameters" -or $_.name -eq "Parameters" } | Select-Object -First 1
  if (-not $paramPanel) { $fail = $true; $reasons.Add("parameters panel missing in items[]") }
  elseif ($paramPanel.persistInSharedLink -ne $true) { $fail = $true; $reasons.Add("parameters panel should set persistInSharedLink=true") }
}

# RBAC/export hints if present
if ($json.rbac) {
  if ([string]::IsNullOrWhiteSpace($json.rbac.readOnlyBehavior)) { $fail = $true; $reasons.Add("rbac.readOnlyBehavior missing") }
  if ([string]::IsNullOrWhiteSpace($json.rbac.exportFidelity)) { $fail = $true; $reasons.Add("rbac.exportFidelity missing") }
}

if ($fail) {
  Write-Host "Export fidelity check FAILED:" -ForegroundColor Red
  $reasons | ForEach-Object { Write-Host (" - " + $_) -ForegroundColor Red }
  exit 3
} else {
  Write-Host "[OK] Export fidelity checks passed for $ExportPath" -ForegroundColor Green
  exit 0
}