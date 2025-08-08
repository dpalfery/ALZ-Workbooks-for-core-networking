param(
  [string]$ModulePath = "terraform/modules/workbooks",
  [string]$ExamplePath = "terraform/examples/single_rg"
)
$ErrorActionPreference = "Stop"

function Test-Tool($name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  return $null -ne $cmd
}

if (-not (Test-Tool "terraform")) {
  Write-Warning "terraform not found on PATH. Skipping fmt/validate (intended to run in CI where Terraform is installed)."
  exit 0
}

Write-Host "Running terraform fmt -check..." -ForegroundColor Cyan
terraform fmt -check -recursive

Write-Host "Validating module at $ModulePath..." -ForegroundColor Cyan
Push-Location $ModulePath
try {
  terraform init -backend=false -input=false
  terraform validate
} finally {
  Pop-Location
}

Write-Host "Validating example at $ExamplePath..." -ForegroundColor Cyan
Push-Location $ExamplePath
try {
  terraform init -backend=false -input=false
  terraform validate
} finally {
  Pop-Location
}

Write-Host "Terraform fmt/validate completed." -ForegroundColor Green