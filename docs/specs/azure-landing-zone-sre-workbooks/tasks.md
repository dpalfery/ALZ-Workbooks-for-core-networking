# Implementation Plan

This plan converts the approved design into discrete, incremental coding tasks suitable for a code-generation LLM. Tasks are test-driven, avoid big jumps, and reference specific requirements and acceptance criteria from the requirements document. Only code-writing, modification, and testing activities are included.

- [x] 1. Initialize repo structure for workbooks, KQL, Terraform, and CI
  - Create directories:
    - [kql/lib](kql/lib)
    - [workbooks/templates](workbooks/templates)
    - [workbooks/lib](workbooks/lib)
    - [terraform/modules/workbooks](terraform/modules/workbooks)
    - [terraform/examples/single_rg](terraform/examples/single_rg)
    - [scripts](scripts)
    - [.github/workflows](.github/workflows)
  - Add placeholder README files describing contents in each directory.
  - Add .editorconfig and basic linting config for JSON and KQL (text rules).
  - _Requirements: 11.1–11.5, 9.1–9.5_

- [x] 1.1 Create KQL shared library function files (stubs) with headers and input/output contracts
  - Files:
    - [kql/lib/inventory_by_scope.kql](kql/lib/inventory_by_scope.kql)
    - [kql/lib/table_freshness.kql](kql/lib/table_freshness.kql)
    - [kql/lib/amba_coverage_by_service.kql](kql/lib/amba_coverage_by_service.kql)
    - [kql/lib/service_health_sli.kql](kql/lib/service_health_sli.kql)
    - [kql/lib/slo_burn_rate.kql](kql/lib/slo_burn_rate.kql)
    - [kql/lib/policy_compliance_summary.kql](kql/lib/policy_compliance_summary.kql)
  - Include parameter documentation blocks and sample invocation comments.
  - _Requirements: 11.1, 11.4, 5.1–5.5, 2.1–2.5, 3.1–3.5, 4.1–4.5, 6.1–6.5_

- [x] 1.2 Add lightweight KQL linter script and tests
  - Implement [scripts/kql_lint.ps1](scripts/kql_lint.ps1) to check presence of summarize/bin usage and column projection limits; fail when rules aren’t met.
  - Add [scripts/test_kql_lint.ps1](scripts/test_kql_lint.ps1) with sample inputs asserting pass/fail behavior.
  - _Requirements: 9.1–9.5_

- [x] 2. Implement core workbook skeleton JSON with parameters panel
  - Create [workbooks/templates/core_workbook.json](workbooks/templates/core_workbook.json) with:
    - Parameter controls: timeRange, mgScope, subscriptionIds, resourceGroups, environmentTag, workspaces[], serviceToggles
    - Hidden steps for loading KQL fragments
    - Theming compatibility metadata
  - Add JSON schema validation script [scripts/validate_workbook_json.ps1](scripts/validate_workbook_json.ps1) (jq-based structure checks).
  - _Requirements: 7.1–7.5, 8.1–8.5, 11.1–11.5_

- [x] 2.1 Wire Inventory & Scope Overview panel
  - Add workbook steps to render inventory grouped by MG → Subscription → ResourceType using [kql/lib/inventory_by_scope.kql](kql/lib/inventory_by_scope.kql).
  - Ensure multi-workspace union with deduplication by ResourceId.
  - Add empty-state rendering for no-results case.
  - _Requirements: 1.1–1.5, 7.2, 7.3_

- [x] 2.2 Wire Log Ingestion Health & Freshness panel
  - Implement freshness table using [kql/lib/table_freshness.kql](kql/lib/table_freshness.kql) for Heartbeat, InsightsMetrics, AzureActivity, AzureDiagnostics with thresholds and status.
  - Add tooltips for latency/threshold details; partial coverage highlighting per workspace.
  - _Requirements: 2.1–2.5, 7.2, 9.2, 9.4_

- [x] 2.3 Wire AMBA Baseline Alert Coverage panel
  - Add mapping dataset [workbooks/lib/amba_mapping.json](workbooks/lib/amba_mapping.json) aligning service categories to required baseline alerts.
  - Implement coverage summary and gaps list using ARG and [kql/lib/amba_coverage_by_service.kql](kql/lib/amba_coverage_by_service.kql); count disabled rules as gaps.
  - Add noisy alert heuristic (if Alert tables available).
  - _Requirements: 3.1–3.5_

- [x] 2.4 Wire Service Health SLIs tiles and drilldowns
  - Implement per-service toggles for VMs, AKS, App Service, Storage, SQL, Network using [kql/lib/service_health_sli.kql](kql/lib/service_health_sli.kql).
  - Tiles compute availability, error rate, latency, saturation; drilldowns show time series and top offenders.
  - Handle No data grayout for absent telemetry.
  - _Requirements: 4.1–4.5, 8.1, 8.4, 9.5_

- [x] 2.5 Wire SLO & Error Budget visualization
  - Add parameter inputs for per-service SLO targets and default values.
  - Compute burn rate and remaining budget over 7/30/90 days via [kql/lib/slo_burn_rate.kql](kql/lib/slo_burn_rate.kql); highlight at-risk services.
  - Implement export action including thresholds and time window.
  - _Requirements: 5.1–5.5_

- [x] 2.6 Wire Policy & Diagnostics coverage panel
  - Use ARG to summarize Policy compliance; thresholds for initiatives > 10% non-compliance.
  - List monitored resource types missing diagnostic settings; detect missing subscription Activity Logs.
  - Employ [kql/lib/policy_compliance_summary.kql](kql/lib/policy_compliance_summary.kql) where LA augmentation is needed.
  - _Requirements: 6.1–6.5_

- [x] 3. Add accessibility and theme support refinements
  - Ensure dark theme-compatible colors and high-contrast readability across visuals.
  - Add loading indicators for slow panels; keyboard navigation ordering for controls.
  - _Requirements: 8.1–8.5_

- [x] 4. Implement Terraform module for workbook deployment (Terraform-only)
  - Create:
    - [terraform/modules/workbooks/main.tf](terraform/modules/workbooks/main.tf)
    - [terraform/modules/workbooks/variables.tf](terraform/modules/workbooks/variables.tf)
    - [terraform/modules/workbooks/outputs.tf](terraform/modules/workbooks/outputs.tf)
    - [terraform/modules/workbooks/versions.tf](terraform/modules/workbooks/versions.tf)
  - Variables include: workbook_definitions (map), location, tags, workspace_ids, management_group_path, slo_defaults.
  - Render [workbooks/templates/core_workbook.json](workbooks/templates/core_workbook.json) using templatefile with parameter injection.
  - _Requirements: 12.1–12.5, 10.3_

- [x] 4.1 Provide Terraform example usage and data sources
  - Create [terraform/examples/single_rg/main.tf](terraform/examples/single_rg/main.tf) showing module usage, azurerm provider config, data sources for LAW and RG.
  - Create [terraform/examples/single_rg/variables.tf](terraform/examples/single_rg/variables.tf) and [terraform/examples/single_rg/outputs.tf](terraform/examples/single_rg/outputs.tf).
  - _Requirements: 12.1–12.3_

- [x] 4.2 Add Terraform validation and plan scripts
  - Create [scripts/tf_validate.ps1](scripts/tf_validate.ps1) to run terraform fmt -check and terraform validate in module and example.
  - Create [scripts/tf_plan_example.ps1](scripts/tf_plan_example.ps1) to run terraform init/plan in the example with placeholders for tfvars.
  - _Requirements: 12.5_

- [x] 5. Add CI workflow for formatting, validation, KQL lint, and optional plan
  - Create [.github/workflows/ci.yml](.github/workflows/ci.yml) with jobs:
    - JSON lint and workbook JSON structure checks
    - KQL lint via [scripts/kql_lint.ps1](scripts/kql_lint.ps1)
    - Terraform fmt/validate using [scripts/tf_validate.ps1](scripts/tf_validate.ps1)
    - Optional plan on example using [scripts/tf_plan_example.ps1](scripts/tf_plan_example.ps1) behind a flag or with dummy backend
  - _Requirements: 12.5, 9.1–9.3_

- [x] 6. Add KQL smoke test scripts for critical queries against test LAW
  - Implement [scripts/kql_smoke_tests.ps1](scripts/kql_smoke_tests.ps1) using az monitor log-analytics query to execute fragments from [kql/lib](kql/lib) with a limited time range.
  - Add assertions for non-empty results and expected columns where applicable.
  - _Requirements: 2.1–2.5, 4.1–4.5, 5.2, 9.2_

- [x] 7. Implement performance guardrails in workbook JSON
  - Ensure all visuals use server-side summarization/binning; limit series counts and projected columns.
  - Add warnings/advisories when row counts exceed thresholds; truncate or aggregate where needed.
  - _Requirements: 9.1–9.5, 1.5_

- [x] 8. Implement parameter persistence and safe defaults
  - Persist parameter selections via shared links; handle invalid or missing parameter values by reverting to defaults.
  - Validate at least one workspace is always selected; default time range to last 24h.
  - _Requirements: 7.1–7.5, 8.1, 10.2_

- [x] 9. RBAC-aware behaviors and export fidelity checks
  - Ensure read-only users can’t edit but can change parameters; verify sharing scopes respect Azure RBAC.
  - Verify exported JSON includes all parameters and data bindings for redeploy.
  - _Requirements: 10.1–10.5_

- [x] 10. Finalize module documentation and examples
  - Add module README at [terraform/modules/workbooks/README.md](terraform/modules/workbooks/README.md) describing variables, outputs, and usage.
  - Add a top-level README section linking to the example and outlining prerequisites and roles.
  - _Requirements: 12.1–12.4, 10.1–10.5_

Notes for implementers:
- Keep each step incremental; commit after passing tests/validation.
- Prefer adding service panels incrementally (enable toggles and add tiles progressively).
- Maintain alignment with AMBA mappings in [workbooks/lib/amba_mapping.json](workbooks/lib/amba_mapping.json) and update as guidance evolves.