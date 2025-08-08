param(
  [Parameter(Mandatory = $false, Position = 0)]
  [string]$Path = "workbooks/templates/core_workbook.json"
)

$ErrorActionPreference = "Stop"

function Resolve-JsonFiles {
  param([string]$Target)
  if (Test-Path $Target -PathType Leaf) {
    if ($Target.ToLower().EndsWith(".json")) { return ,(Resolve-Path $Target).Path }
    else { throw "File '$Target' is not a .json file." }
  }
  elseif (Test-Path $Target -PathType Container) {
    return Get-ChildItem -Path $Target -Recurse -Include *.json | Select-Object -ExpandProperty FullName
  }
  else {
    throw "Path '$Target' does not exist."
  }
}

# Load baseline rules
$rulesPath = ".workbook-json-rules.json"
$rules = @{
  required_parameters       = @("timeRange","mgScope","subscriptionIds","resourceGroups","environmentTag","workspaces","serviceToggles")
  require_hidden_steps      = $true
  require_theming_metadata  = $true
}
if (Test-Path $rulesPath) {
  try {
    $r = Get-Content -Raw -Path $rulesPath | ConvertFrom-Json
    if ($null -ne $r.required_parameters) { $rules.required_parameters = @($r.required_parameters) }
    if ($null -ne $r.require_hidden_steps) { $rules.require_hidden_steps = [bool]$r.require_hidden_steps }
    if ($null -ne $r.require_theming_metadata) { $rules.require_theming_metadata = [bool]$r.require_theming_metadata }
  } catch {
    Write-Warning "Failed to parse $rulesPath. Using defaults."
  }
}

$files = Resolve-JsonFiles -Target $Path
$overallFailures = @()

foreach ($file in $files) {
  $fail = $false
  $reasons = New-Object System.Collections.Generic.List[string]

  # Load JSON
  try {
    $jsonText = Get-Content -Raw -Path $file
    $json = $jsonText | ConvertFrom-Json -ErrorAction Stop
  } catch {
    $overallFailures += @{ file = $file; reasons = @("invalid JSON or unreadable file: $($_.Exception.Message)") }
    continue
  }

  # Base schema checks
  if (-not $json.version) { $fail = $true; $reasons.Add("missing: version") }
  if (-not $json.metadata) { $fail = $true; $reasons.Add("missing: metadata") }
  if (-not $json.parameters) { $fail = $true; $reasons.Add("missing: parameters") }
  if (-not $json.items) { $fail = $true; $reasons.Add("missing: items[]") }

  # Theming metadata (Req 8)
  if ($rules.require_theming_metadata) {
    if (-not $json.metadata.theming) {
      $fail = $true; $reasons.Add("missing: metadata.theming (darkTheme/highContrast)")
    } else {
      if ($null -eq $json.metadata.theming.darkTheme) { $fail = $true; $reasons.Add("missing: theming.darkTheme") }
      if ($null -eq $json.metadata.theming.highContrast) { $fail = $true; $reasons.Add("missing: theming.highContrast") }
    }
  }

  # Performance guardrails advisory
  if (-not $json.performanceGuardrails) {
    Write-Warning "[$file] performanceGuardrails not present; consider adding thresholds."
  }

  # Required parameters (Req 7)
  if ($json.parameters) {
    $paramNames = @($json.parameters.PSObject.Properties | Select-Object -ExpandProperty Name)
    foreach ($p in $rules.required_parameters) {
      if ($paramNames -notcontains $p) {
        $fail = $true; $reasons.Add("missing parameter: $p")
      }
    }
  }

  # Parameters panel and persistence (Req 7.5)
  $paramItem = $null
  if ($json.items) {
    $paramItem = $json.items | Where-Object { $_.name -eq "Parameters" -or $_.type -eq "parameters" } | Select-Object -First 1
  }
  if (-not $paramItem) { $fail = $true; $reasons.Add("missing parameters panel in items[]") }
  else {
    if ($null -eq $paramItem.persistInSharedLink -or $paramItem.persistInSharedLink -ne $true) {
      $fail = $true; $reasons.Add("Parameters panel should set persistInSharedLink=true")
    }
    if (-not $paramItem.controls) { $fail = $true; $reasons.Add("Parameters panel missing controls[]") }
    else {
      $controlParams = @($paramItem.controls | ForEach-Object { $_.parameter })
      foreach ($p in $rules.required_parameters) {
        if ($controlParams -notcontains $p) { $fail = $true; $reasons.Add("Parameters panel missing control for: $p") }
      }
      $wsCtrl = $paramItem.controls | Where-Object { $_.parameter -eq "workspaces" } | Select-Object -First 1
      if ($wsCtrl -and $wsCtrl.minSelected -lt 1) { $fail = $true; $reasons.Add("Workspaces control must enforce minSelected >= 1") }
    }
  }

  # Hidden steps exist (Req 11 modularity)
  if ($rules.require_hidden_steps) {
    if (-not $json.hiddenSteps -or $json.hiddenSteps.Count -eq 0) {
      $fail = $true; $reasons.Add("missing: hiddenSteps[]")
    } else {
      foreach ($hs in $json.hiddenSteps) {
        if (-not $hs.name) { $fail = $true; $reasons.Add("hiddenStep missing name") }
        if (-not $hs.kqlRef) { $fail = $true; $reasons.Add("hiddenStep '$($hs.name)' missing kqlRef") }
      }
    }
  }

  # Accessibility and keyboard navigation checks (Req 8)
  $items = @($json.items)
  if ($items.Count -gt 0) {
    $withLoading = ($items | Where-Object { $_.loadingIndicator -eq $true }).Count
    # Require at least 3 panels with loadingIndicator true
    if ($withLoading -lt [Math]::Min(3, $items.Count)) {
      $fail = $true; $reasons.Add("accessibility: loadingIndicator should be true on major panels (found $withLoading)")
    }
    $orders = @()
    foreach ($it in $items) {
      if ($null -eq $it.keyboardNavigationOrder) { $fail = $true; $reasons.Add("keyboardNavigationOrder missing on item '$($it.name)'.") }
      else { $orders += [int]$it.keyboardNavigationOrder }
    }
    if ($orders.Count -gt 1) {
      $sorted = @($orders | Sort-Object -Unique)
      if ($sorted.Count -ne $orders.Count) { $fail = $true; $reasons.Add("keyboardNavigationOrder must be unique across items.") }
    }
  }

  # RBAC-aware behaviors (Req 10 mapped to Task 9)
  if (-not $json.rbac) {
    $fail = $true; $reasons.Add("rbac section missing (readOnlyBehavior/exportFidelity)")
  } else {
    if ([string]::IsNullOrWhiteSpace($json.rbac.readOnlyBehavior)) { $fail = $true; $reasons.Add("rbac.readOnlyBehavior missing") }
    if ([string]::IsNullOrWhiteSpace($json.rbac.exportFidelity)) { $fail = $true; $reasons.Add("rbac.exportFidelity missing") }
  }

  # Panels acceptance spot-checks:
  # 2.1 Inventory: explicit workspace() union + dedup
  $inv = $items | Where-Object { $_.name -like "Inventory & Scope Overview*" } | Select-Object -First 1
  if (-not $inv) { $fail = $true; $reasons.Add("Inventory panel missing") }
  else {
    $k = "$($inv.kqlInline)"
    if ($k -notmatch 'workspace\(' -or $k -notmatch 'union\s+isfuzzy=true') { $fail = $true; $reasons.Add("Inventory panel should use workspace() union with isfuzzy=true") }
    if ($null -eq $inv.noDataState) { $fail = $true; $reasons.Add("Inventory panel missing empty-state rendering") }
  }

  # 2.2 Freshness: per-workspace coverage and missingWorkspaces
  $fresh = $items | Where-Object { $_.name -eq "Log Ingestion Health & Freshness" } | Select-Object -First 1
  if (-not $fresh) { $fail = $true; $reasons.Add("Freshness panel missing") }
  else {
    $k = "$($fresh.kqlInline)"
    if ($k -notmatch 'missingWorkspaces' -or $k -notmatch 'coverage') { $fail = $true; $reasons.Add("Freshness panel must compute missingWorkspaces/coverage") }
  }

  # 2.3 AMBA Coverage + mapping
  $amba = $items | Where-Object { $_.name -like "AMBA Baseline Alert Coverage*" } | Select-Object -First 1
  if (-not $amba) { $fail = $true; $reasons.Add("AMBA Coverage panel missing") }
  else {
    $deps = @($amba.dataDependencies)
    if ($deps.Count -eq 0) { $fail = $true; $reasons.Add("AMBA panel missing mapping dataDependencies") }
  }
  # optional noisy alerts
  $noisy = $items | Where-Object { $_.name -eq "Noisy Alerts Heuristic (optional)" } | Select-Object -First 1
  if (-not $noisy) { Write-Warning "Noisy Alerts heuristic panel not found (optional if Alert table unavailable)." }

  # 2.4 SLIs tiles + drilldown
  $sli = $items | Where-Object { $_.name -like "Service Health SLIs*" } | Select-Object -First 1
  if (-not $sli) { $fail = $true; $reasons.Add("Service Health SLIs tiles panel missing") }
  $vmdd = $items | Where-Object { $_.name -eq "VM Health Drilldown" } | Select-Object -First 1
  if (-not $vmdd) { $fail = $true; $reasons.Add("VM Health drilldown panel missing") }

  # 2.5 SLO: default targets + multi-window burn rate
  $sloWindows = $items | Where-Object { $_.name -eq "SLO Burn Rate (7/30/90 days)" } | Select-Object -First 1
  if (-not $sloWindows) { $fail = $true; $reasons.Add("SLO multi-window burn rate panel missing") }

  # 2.6 Policy & Diagnostics coverage: summary + gaps + missing Activity Logs
  $pol = $items | Where-Object { $_.name -eq "Policy & Diagnostics Compliance Summary" } | Select-Object -First 1
  $diagGaps = $items | Where-Object { $_.name -eq "Diagnostics Coverage Gaps" } | Select-Object -First 1
  $actLogs = $items | Where-Object { $_.name -eq "Missing Subscription Activity Logs" } | Select-Object -First 1
  if (-not $pol)    { $fail = $true; $reasons.Add("Policy compliance summary panel missing") }
  if (-not $diagGaps) { $fail = $true; $reasons.Add("Diagnostics coverage gaps panel missing") }
  if (-not $actLogs)  { $fail = $true; $reasons.Add("Missing Activity Logs panel missing") }

  # Finalize
  if ($fail) {
    $overallFailures += @{ file = $file; reasons = $reasons }
  } else {
    Write-Host "[OK] $file passed enhanced workbook validation." -ForegroundColor Green
  }
}

if ($overallFailures.Count -gt 0) {
  Write-Host ""
  Write-Host "Workbook JSON validation failures:" -ForegroundColor Red
  foreach ($f in $overallFailures) {
    $file = $f.file
    $reasons = ($f.reasons -join "; ")
    Write-Host (" - " + $file + ": " + $reasons) -ForegroundColor Red
  }
  exit 2
}

exit 0