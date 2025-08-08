# Azure Landing Zone SRE Workbooks

Modular Azure Monitor Workbooks, reusable KQL fragments, Terraform-only deployment, and CI validation for Azure Landing Zone (L2) SRE scenarios.

- Requirements: see [docs/specs/azure-landing-zone-sre-workbooks/requirements.md](docs/specs/azure-landing-zone-sre-workbooks/requirements.md)
- Design: see [docs/specs/azure-landing-zone-sre-workbooks/design.md](docs/specs/azure-landing-zone-sre-workbooks/design.md)
- Implementation tasks: see [docs/specs/azure-landing-zone-sre-workbooks/tasks.md](docs/specs/azure-landing-zone-sre-workbooks/tasks.md)

## Structure

- KQL library: [kql/lib](kql/lib)
  - Shared KQL fragments with documented input/output contracts
- Core workbook template: [workbooks/templates/core_workbook.json](workbooks/templates/core_workbook.json)
- Workbook datasets and JSON fragments: [workbooks/lib](workbooks/lib)
- Terraform module: [terraform/modules/workbooks](terraform/modules/workbooks)
- Example usage: [terraform/examples/single_rg](terraform/examples/single_rg)
- Scripts: [scripts](scripts)
  - KQL lint: [scripts/kql_lint.ps1](scripts/kql_lint.ps1)
  - KQL lint tests: [scripts/test_kql_lint.ps1](scripts/test_kql_lint.ps1)
  - Workbook JSON validation: [scripts/validate_workbook_json.ps1](scripts/validate_workbook_json.ps1)
  - Terraform validate: [scripts/tf_validate.ps1](scripts/tf_validate.ps1)
  - Terraform plan example: [scripts/tf_plan_example.ps1](scripts/tf_plan_example.ps1)
  - KQL smoke tests: [scripts/kql_smoke_tests.ps1](scripts/kql_smoke_tests.ps1)

## Getting Started

1) Validate workbook JSON
- Requires PowerShell 7+ (pwsh) or Windows PowerShell
- Command:
  - pwsh -File [scripts/validate_workbook_json.ps1](scripts/validate_workbook_json.ps1)

2) Lint KQL fragments
- Command:
  - pwsh -File [scripts/kql_lint.ps1](scripts/kql_lint.ps1) -Path kql/lib

3) Terraform validate (module and example)
- Requires Terraform CLI
- Command:
  - pwsh -File [scripts/tf_validate.ps1](scripts/tf_validate.ps1)

Optional: Plan the example
- Command:
  - pwsh -File [scripts/tf_plan_example.ps1](scripts/tf_plan_example.ps1)

KQL smoke tests (requires az CLI and a test workspace)
- Set env: WORKSPACE_ID=<your-law-id>
- Command:
  - pwsh -File [scripts/kql_smoke_tests.ps1](scripts/kql_smoke_tests.ps1)

## CI

GitHub Actions workflow: [ .github/workflows/ci.yml ](.github/workflows/ci.yml)
- JSON structure checks for workbook
- KQL lint
- Terraform fmt/validate
- Optional example plan (guarded by RUN_TF_PLAN)

## Notes

- RBAC: Reader on LAW(s) for queries; Contributor on target RG to create workbooks.
- Provider: azurerm >= 3.50.0
- State: manage per-environment backends and workspaces as appropriate.
- This repository ignores files under docs/archive per instruction.