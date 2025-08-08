param(
  [string]$ExamplePath = "terraform/examples/single_rg",
  [string]$TfVarsFile = ""
)
$ErrorActionPreference = "Stop"

function Ensure-Tool($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    Write-Warning "$name not found. Skipping plan."
    exit 0
  }
}

Ensure-Tool terraform

Push-Location $ExamplePath
try {
  Write-Host "Running terraform init in $ExamplePath..." -ForegroundColor Cyan
  terraform init -input=false

  if ([string]::IsNullOrWhiteSpace($TfVarsFile)) {
    Write-Host "Running terraform plan (no tfvars)..." -ForegroundColor Cyan
    terraform plan -input=false
  } else {
    if (-not (Test-Path $TfVarsFile)) {
      Write-Warning "TfVars file '$TfVarsFile' not found. Running plan without it."
      terraform plan -input=false
    } else {
      Write-Host "Running terraform plan with tfvars: $TfVarsFile" -ForegroundColor Cyan
      terraform plan -input=false -var-file=$TfVarsFile
    }
  }
} finally {
  Pop-Location
}