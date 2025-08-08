# Design Document

## Overview
This document describes the architecture and design for Azure Monitor Workbooks to support SRE monitoring at Azure Landing Zone Level 2 (L2) and below, sourcing from two Log Analytics Workspaces (LAW) and Azure Resource Graph (ARG). The solution emphasizes modular workbooks, reusable KQL, Terraform-only deployment, and performance-aware patterns.

Key goals:
- Multi-scope (management group, subscription, resource group) with consistent parameters
- Multi-workspace union with deduplication
- AMBA-aligned alert coverage visualization
- Service health SLIs and SLO/error budget views
- Policy/compliance and diagnostic coverage
- Terraform module for deployability and CI validation

References informing this design:
- Microsoft Workbook templates repository [microsoft/Application-Insights-Workbooks](https://github.com/microsoft/Application-Insights-Workbooks)
- Azure Monitor Baseline Alerts (AMBA) guidance and queries [Azure/azure-monitor-baseline-alerts](https://github.com/Azure/azure-monitor-baseline-alerts)
- Enterprise-scale Landing Zone guidance [Azure/Enterprise-Scale](https://github.com/Azure/Enterprise-Scale)
- Azure Monitor Workbooks docs [docs.microsoft.com/azure/azure-monitor/visualize/workbooks-overview](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-overview)
- Log Analytics table reference [docs.microsoft.com/azure/azure-monitor/reference/tables/tables-reference](https://learn.microsoft.com/azure/azure-monitor/reference/tables/tables-reference)
- Terraform azurerm provider (workbooks) [registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights_workbook](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights_workbook)

## Architecture
The solution consists of a core workbook and modular service tabs. Queries use LA for telemetry and ARG for configuration/compliance state. Terraform modules deliver versioned JSON definitions.

```mermaid
graph TD
  User[User (SRE/Cloud Ops)] -->|Parameters| WB[Core Workbook]
  WB --> Params[Parameter Panel]
  WB --> Inv[Inventory & Scope Overview]
  WB --> Ingest[Ingestion & Freshness]
  WB --> Alerts[AMBA Coverage]
  WB --> Health[Service Health SLIs]
  WB --> SLO[SLO/Error Budget]
  WB --> Policy[Policy & Diagnostics]
  Inv --> LA[(Log Analytics)]
  Ingest --> LA
  Health --> LA
  SLO --> LA
  Alerts --> ARG[(Azure Resource Graph)]
  Policy --> ARG
  Terraform[Terraform Module] -->|[arm.resource("microsoft.insights/workbooks")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1)| RG[Resource Group]
```

Design principles:
- Parameterize everything: time range, scope, environment tags, workspace selection, service toggles
- Prefer server-side summarization (summarize, bin) and minimal columns (project) to reduce data scanned
- Use [kql.function("compute_sli_status")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1) and [kql.function("slo_error_budget")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1) fragments for reuse
- Blend data sources: LA for telemetry; ARG for alert rule metadata, policy state, and diagnostic settings
- Terraform-only deployment using [terraform.resource("azurerm_application_insights_workbook")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1)

## Components and Interfaces

1) Core Parameters Panel
- Inputs: none (user interaction)
- Outputs: timeRange, mgScope, subscriptionIds[], resourceGroups[], environmentTag, workspaces[], serviceToggles{vm,aks,app,storage,sql,network}
- Behavior: Validate selections; default to last 24h; ensure at least one workspace selected; persist in shared links

2) Inventory & Scope Overview
- Inputs: parameters above
- Data: ARG for resource inventory; LA union for recent heartbeat/activity counts
- Output: Tables and tiles grouped by MG -> Subscription -> ResourceType
- KQL fragments: [kql.function("inventory_by_scope")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1)

3) Ingestion & Freshness
- Inputs: workspaces[], timeRange
- Data: LA tables Heartbeat, InsightsMetrics, AzureActivity, AzureDiagnostics
- Output: Per-table lastIngestedTime, row counts, computed latency; warnings when thresholds breached
- KQL fragments: [kql.function("table_freshness")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1)

4) AMBA Alert Coverage
- Inputs: scope params
- Data: ARG query of alert rules (ScheduledQueryRulesV2, MetricAlerts), states (enabled/disabled), mapping to AMBA baseline
- Output: Coverage summary by service category; gaps list; noisy alerts detection by recent firing frequency (LA Alerts table if available)
- KQL/ARG fragments: [kql.function("amba_coverage_by_service")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1)

5) Service Health SLIs
- Inputs: serviceToggles, timeRange
- Data: 
  - VM: Heartbeat, InsightsMetrics (Perf), AzureDiagnostics (Guest/Platform)
  - AKS: ContainerInsights (KubePodInventory, KubeNodeInventory, InsightsMetrics)
  - App Service: AppRequests/AppTraces (via LA if connected), AzureDiagnostics
  - Storage: AzureMetrics/InsightsMetrics
  - SQL: AzureDiagnostics, AzureMetrics
  - Network: AzureDiagnostics (firewalls, gateways), AzureMetrics
- Output: Tiles with availability, error rate, latency, saturation, with drill-down charts and top offenders
- KQL fragments: [kql.function("service_health_sli")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1)

6) SLO & Error Budget
- Inputs: user-defined SLO targets per service via parameters
- Data: same SLIs as Health; compute burn rates and budgets over 7/30/90 days
- Output: SLO compliance charts; burn-rate alerting guidance panels
- KQL fragments: [kql.function("slo_burn_rate")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1)

7) Policy & Diagnostics Coverage
- Inputs: scope params
- Data: ARG for Policy compliance states; ARG for diagnosticSettings on resource types; LA for Activity Log collection health
- Output: Compliance summaries; list of resources missing diagnostic settings; critical warnings for missing subscription Activity Logs
- ARG fragments: [kql.function("policy_compliance_summary")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1)

8) Shared KQL Library
- Implementation: Inline Workbook "query" steps referencing "Parameters" and "Hidden" steps holding fragments
- Naming: prefix fragments with "lib_" and document inputs/outputs; avoid name collisions

## Data Models

Log Analytics tables used (not exhaustive):
- Heartbeat: Computer, ResourceId, TimeGenerated
- InsightsMetrics: Name, Namespace, Val, Tags, _ResourceId, TimeGenerated
- AzureActivity: Category, OperationName, ActivityStatus, ResourceId, SubscriptionId, TimeGenerated
- AzureDiagnostics: Category, OperationName, ResourceId, ResultType, Level, TimeGenerated
- ContainerInsights: KubePodInventory, KubeNodeInventory, KubeServices, Perf
- App telemetry via LA (if connected): AppRequests, AppTraces, AppDependencies
- Alerts (optional via LA): Alert, AlertHistory (region-dependent availability)

Azure Resource Graph entities:
- Resources: type, id, name, subscriptionId, resourceGroup, tags
- Alert rule resources: microsoft.insights/scheduledqueryrules, microsoft.insights/metricalerts
- Policy states: policyResources, policyAssignments, policyDefinitions (via policyStates in ARG)
- Diagnostic settings: microsoft.insights/diagnosticSettings (ARG supports querying these via resources)

Parameter model:
- timeRange: timespan
- scope: mgPath | subscriptionIds[] | resourceGroups[]
- workspaces: workspaceIds[]
- environmentTag: string filter (e.g., env in ["prod","nonprod"])
- serviceToggles: map[string]bool
- sloTargets: map[service]{availabilityPct, latencyMs, errorRatePct}

## KQL Patterns and Fragments

Multi-workspace union with deduplication:

```kusto
let W1 = workspace(id_1);
let W2 = workspace(id_2);
union isfuzzy=true W1:Heartbeat, W2:Heartbeat
| summarize lastSeen = max(TimeGenerated) by ResourceId
```

Table freshness (example):

```kusto
let critical = dynamic(["Heartbeat","InsightsMetrics","AzureActivity","AzureDiagnostics"]);
union withsource=TableName Heartbeat, InsightsMetrics, AzureActivity, AzureDiagnostics
| summarize lastIngested = max(TimeGenerated), rows = count() by TableName
| extend latencyMin = datetime_diff("minute", now(), lastIngested) * -1
| extend thresholdMin = case(TableName == "Heartbeat", 15, TableName == "AzureActivity", 60, 30)
| extend status = iff(latencyMin > thresholdMin, "Warning", "OK")
```

SLO burn rate (generic):

```kusto
let target = 0.995; // 99.5%
let window = 7d;
let errors = MyServiceTable | where TimeGenerated > ago(window) | where IsError == true | count;
let total = MyServiceTable | where TimeGenerated > ago(window) | count;
let err_rate = todouble(errors) / todouble(total);
let budget = 1.0 - target;
let burn_rate = err_rate / budget;
project burn_rate, remaining_budget = 1.0 - err_rate
```

Noisy alerts heuristic (if Alert table present):

```kusto
Alert
| where TimeGenerated > ago(14d)
| summarize fires = count() by AlertRuleName
| where fires > 50
```

## Terraform Deployment Design (Terraform-only)

Module goals:
- Create/update one or more [terraform.resource("azurerm_application_insights_workbook")](docs/specs/azure-landing-zone-sre-workbooks/design.md:1) resources from JSON templates
- Support for_each over an input map of target scopes/subscriptions/regions
- Parameterize workspace IDs, mg paths, default SLO targets, and feature toggles

Suggested module interface:
- Variables:
  - var.workbook_definitions: map(object({ name, display_name, category, source_id, data_json_template_path, parameters = map(string) }))
  - var.workspace_ids: list(string)
  - var.management_group_path: string
  - var.location: string
  - var.tags: map(string)
  - var.slo_defaults: map(object({ availabilityPct = number, latencyMs = number, errorRatePct = number }))
- Outputs:
  - workbook_ids: map(string)

Example usage snippet:

```hcl
module "workbooks" {
  source = "./modules/workbooks"
  location = "eastus"
  workspace_ids = ["${data.azurerm_log_analytics_workspace.w1.id}", "${data.azurerm_log_analytics_workspace.w2.id}"]
  management_group_path = "/providers/Microsoft.Management/managementGroups/contoso-mg"
  workbook_definitions = {
    core = {
      name                     = "lz-sre-core"
      display_name             = "LZ SRE Core"
      category                 = "workbook"
      source_id                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg.name}"
      data_json_template_path  = "${path.module}/templates/core_workbook.json"
      parameters               = { workspace1 = data.azurerm_log_analytics_workspace.w1.id, workspace2 = data.azurerm_log_analytics_workspace.w2.id }
    }
  }
  tags = { env = "prod", owner = "sre" }
}
```

Resource implementation (inside module):

```hcl
resource "azurerm_application_insights_workbook" "this" {
  for_each            = var.workbook_definitions
  name                = each.value.name
  display_name        = each.value.display_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.target.name
  category            = each.value.category
  data_json           = templatefile(each.value.data_json_template_path, merge(each.value.parameters, {
    workspace_ids = var.workspace_ids,
    mg_path       = var.management_group_path,
    slo_defaults  = var.slo_defaults
  }))
}
```

CI validation:
- terraform fmt -check
- terraform validate
- optional: az monitor data-collection rule/schema checks for workbook JSON shape via jq parse
- optional plan against a test subscription; fail on diff in immutable fields

RBAC and provider prerequisites:
- Roles: Reader on target LAW(s) for query; Contributor to resource group for workbook creation
- Provider: azurerm ≥ 3.x; features.resource_group.prevent_deletion_if_contains_resources = false
- State management: per-environment backends (e.g., azurerm backend), workspaces for isolation

## Error Handling
- Query timeouts: show loading + advisory to narrow filters when >30s
- No data: render “No data” state; do not fail other panels
- Partial coverage: when one LAW lacks tables, annotate “partial” with which workspace is missing
- Module failure: isolate panel failures; do not block entire workbook rendering

## Testing Strategy
- KQL smoke tests via API: run representative queries using az monitor log-analytics query in CI against a test LAW; assert non-empty result and schema
- Query cost guardrails: assert summarize/bin and projected column limits via simple textual lint rules
- Terraform: fmt/validate/plan in CI; deploy to ephemeral RG; run LA queries; destroy
- Manual workbook checks: verify parameters persist via shared links; verify dark/high-contrast rendering

## Security and Privacy
- Do not include secrets or connection strings in workbooks
- Respect RBAC: only show data user is authorized to view
- Tag PII-bearing tables and avoid projecting sensitive fields by default

## Open Questions / Research To Refine
- Confirm availability of Alert/AlertHistory tables in target regions; if absent, rely solely on ARG for noisy alert detection
- Validate ARG query shapes for policyStates and diagnosticSettings across subscriptions at MG scope
- Determine preferred environment tag key (e.g., "env" vs "environment") across estates to standardize parameter filter

## Traceability to Requirements
- Req 1: Inventory & Scope Overview, multi-scope parameters, ARG + LA overview
- Req 2: Ingestion & Freshness panel with thresholds and warnings
- Req 3: AMBA coverage via ARG, disabled rules flagged, drill-downs
- Req 4: Service Health SLIs tiles and drilldowns per service
- Req 5: SLO/Error Budget parameters and burn rate views
- Req 6: Policy & Diagnostics coverage and alerts on gaps
- Req 7: Parameters for time/scope/env/workspaces; union across LAW
- Req 8: Theming, accessibility, loading indicators
- Req 9: Performance guardrails in KQL patterns
- Req 10: RBAC-aware sharing and JSON export fidelity
- Req 11: Modular tabs; fragment library; toggles
- Req 12: Terraform-only module, CI checks, variables for IDs and MG paths