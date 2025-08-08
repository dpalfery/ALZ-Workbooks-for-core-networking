# Requirements Document

## Introduction

This document defines the initial functional and non-functional requirements for a set of Azure Monitor Workbook dashboards that support Site Reliability Engineering (SRE) for Azure Landing Zone Level 2 (L2) and below. Data sources are two Log Analytics Workspaces (multi-workspace), with the objective of providing standardized, actionable visualizations for inventory, health, alert coverage, compliance, and SLOs across management groups, subscriptions, and resource groups.

Scope includes parameterized, reusable workbooks; excludes third-party data sources. Deployment is Terraform-only (no ARM or Bicep).

## Requirements

### Requirement 1: L2 overview and inventory across scopes

**User Story:** As an SRE, I want a landing-zone-level overview of resources and key health indicators across management groups and subscriptions, so that I can quickly assess the posture of my environment.

#### Acceptance Criteria

1. WHEN the workbook loads THEN the system SHALL display a summary inventory of resources grouped by management group, subscription, and resource type for the selected time range.
2. IF the user changes the scope filter (management group, subscription, resource group) THEN the system SHALL update all sections to reflect the new scope within 5 seconds on cached data or 30 seconds on fresh queries.
3. WHEN querying data THEN the system SHALL union results from the two configured Log Analytics Workspaces and de-duplicate by ResourceId.
4. IF no resources are found for the selected scope THEN the system SHALL show an empty state with guidance to adjust filters or verify data collection.
5. WHEN the number of returned rows exceeds 200,000 THEN the system SHALL prompt the user to narrow filters to prevent timeouts.

### Requirement 2: Log ingestion health and data freshness

**User Story:** As an SRE, I want to see ingestion health and data freshness for key tables, so that I can detect data pipeline issues that would hide real incidents.

#### Acceptance Criteria

1. WHEN the workbook loads THEN the system SHALL display per-table lastIngestedTime, row counts, and data latency for critical tables (e.g., Heartbeat, InsightsMetrics, AzureActivity, AzureDiagnostics).
2. IF data freshness exceeds a configurable threshold (default 15 minutes for Heartbeat, 60 minutes for AzureActivity) THEN the system SHALL flag the table with a warning status.
3. WHEN one workspace is missing a critical table THEN the system SHALL indicate partial coverage and identify which workspace is missing data.
4. IF ingestion errors are detected in LogManagement logs THEN the system SHALL render a panel listing recent errors with links to affected resources.
5. WHEN the user hovers a warning icon THEN the system SHALL show a tooltip with the computed latency and threshold.

### Requirement 3: Baseline alert coverage (AMBA-aligned)

**User Story:** As an SRE, I want to visualize baseline alert coverage aligned to Microsoft AMBA guidance, so that I can identify coverage gaps across landing-zone workloads.

#### Acceptance Criteria

1. WHEN the workbook loads THEN the system SHALL display counts of active alert rules by service category and severity mapped to AMBA taxonomy.
2. IF a required AMBA baseline alert for a scoped service is not present THEN the system SHALL flag a coverage gap with the missing rule name and target scope.
3. WHEN an alert rule is disabled THEN the system SHALL count it as a gap and indicate Disabled status.
4. IF the user drills into a service category THEN the system SHALL display the underlying KQL checks and affected resources.
5. WHEN a rule fires frequently above a configurable threshold THEN the system SHALL recommend tuning by highlighting noisy alerts.

### Requirement 4: Platform and workload health

**User Story:** As an SRE, I want health views for platform and workload services (VMs, AKS, App Service, Storage, SQL, Network), so that I can detect and triage incidents quickly.

#### Acceptance Criteria

1. WHEN the workbook loads THEN the system SHALL present per-service health tiles with status computed from key SLIs (availability, error rate, latency, saturation).
2. IF any SLI breaches its threshold THEN the system SHALL mark the service tile as Degraded or Critical and expose drill-down tabs with KQL detail.
3. WHEN the user selects a service tile THEN the system SHALL show time series charts and top offenders (e.g., top erroring resources).
4. IF no telemetry exists for a service in scope THEN the system SHALL gray out the tile and show “No data”.
5. WHEN AKS is in scope THEN the system SHALL support node/cluster health from ContainerInsights tables if available.

### Requirement 5: SLO/SLA visualization

**User Story:** As an SRE, I want to visualize SLO targets and error budgets, so that I can understand reliability performance over selectable windows.

#### Acceptance Criteria

1. WHEN the workbook loads THEN the system SHALL allow the user to set SLO targets per service (percentage availability or latency thresholds) via parameters.
2. IF an SLO is defined THEN the system SHALL compute burn rate and remaining error budget over 7/30/90-day windows.
3. WHEN burn rate exceeds an actionable threshold (e.g., 2x over 1h/6h) THEN the system SHALL highlight the service as at risk.
4. IF no SLO is defined for a service THEN the system SHALL show a callout with guidance to configure SLOs.
5. WHEN the user exports the SLO panel THEN the system SHALL include current thresholds and time window in the export.

### Requirement 6: Policy/compliance and diagnostic coverage

**User Story:** As a Cloud Ops engineer, I want to see Azure Policy compliance and diagnostic setting coverage, so that guardrails and logging are enforced at L2 and below.

#### Acceptance Criteria

1. WHEN the workbook loads THEN the system SHALL summarize Policy compliance by initiative/policy with counts of compliant/non-compliant resources within the selected scope.
2. IF diagnostic settings are missing for monitored resource types THEN the system SHALL list the non-compliant resources with links to enable diagnostics.
3. WHEN an initiative has over 10% non-compliance THEN the system SHALL flag the initiative for remediation.
4. IF Activity Logs are not being collected for a subscription in scope THEN the system SHALL surface a critical warning.
5. WHEN the user drills in THEN the system SHALL show per-resource compliance state history if available.

### Requirement 7: Parameters, filters, and multi-workspace support

**User Story:** As an SRE, I want consistent parameters for time range, scope, environment, and workspace selection, so that I can reuse the workbooks across tenants and regions.

#### Acceptance Criteria

1. WHEN the workbook loads THEN the system SHALL expose parameters for time range, management group, subscription, resource group, environment tag, and workspace selection.
2. IF the user selects both workspaces THEN the system SHALL execute KQL queries using the union operator across workspaces.
3. WHEN the user changes the time range THEN all visualizations SHALL refresh consistently without stale data.
4. IF a parameter value is invalid or no longer available THEN the system SHALL revert to a safe default and inform the user.
5. WHEN parameters are saved as a shared link THEN the system SHALL preserve selected values.

### Requirement 8: Usability and accessibility

**User Story:** As an SRE, I want responsive, accessible, and readable dashboards, so that I can use them effectively during incidents.

#### Acceptance Criteria

1. WHEN the workbook is viewed on standard desktop resolutions THEN the system SHALL maintain legibility without horizontal scrolling in primary views.
2. IF high-contrast mode is enabled in the browser THEN the system SHALL render charts and tables with sufficient contrast.
3. WHEN dark theme is selected THEN the system SHALL use Azure Workbooks dark theme compatible colors.
4. IF a panel takes longer than 30 seconds to load THEN the system SHALL display a loading indicator and suggest filter reduction.
5. WHEN keyboard navigation is used THEN all interactive controls SHALL be reachable and operable.

### Requirement 9: Performance and cost efficiency

**User Story:** As a platform owner, I want queries and visuals to be efficient, so that user experience remains fast and Log Analytics costs are controlled.

#### Acceptance Criteria

1. WHEN executing KQL THEN the system SHALL use server-side summarization and binning to limit dataset size where appropriate.
2. IF query time exceeds 30 seconds or data scanned exceeds 2 GB per visual THEN the system SHALL advise narrowing filters.
3. WHEN repeated queries are executed within a session THEN the system SHALL reuse parameters and cached results where Workbooks supports it.
4. IF a query returns more than 200,000 rows THEN the system SHALL truncate or aggregate results with user notification.
5. WHEN charts are rendered THEN the system SHALL limit series counts to maintain readability and performance.

### Requirement 10: Sharing, RBAC, and lifecycle

**User Story:** As an SRE lead, I want controlled sharing and versioning, so that teams can collaborate safely across landing zones.

#### Acceptance Criteria

1. WHEN the workbook is published THEN the system SHALL support sharing at resource group, subscription, or workspace scope respecting Azure RBAC.
2. IF the user has only Reader access THEN the system SHALL prevent edits while allowing parameter changes.
3. WHEN a new version is deployed via Terraform THEN the system SHALL not overwrite user-specific parameter links.
4. IF a workbook reference is deprecated THEN the system SHALL display a banner with a link to the successor.
5. WHEN exporting to JSON THEN the system SHALL include all parameters and data source bindings needed for redeployment.

### Requirement 11: Extensibility and modularity

**User Story:** As a solution engineer, I want a modular workbook structure, so that I can add service-specific tabs without breaking the core.

#### Acceptance Criteria

1. WHEN adding a new service module THEN the system SHALL expose a standard contract for parameters and KQL fragment inputs/outputs.
2. IF a module fails to render THEN the system SHALL fail gracefully and isolate the error to the module panel.
3. WHEN a module is disabled via parameter THEN the system SHALL hide its visuals and avoid running its queries.
4. IF the core parameters change THEN dependent modules SHALL receive updated values without manual edits.
5. WHEN templates are reused across tenants THEN the system SHALL allow overriding workspace and scope bindings via parameters.

### Requirement 12: Deployment as code (Terraform-only)

**User Story:** As a platform engineer, I want the workbooks to be deployable via code, so that environments can be replicated consistently.

#### Acceptance Criteria

1. WHEN exporting workbook JSON THEN the system SHALL provide a Terraform module and example usage snippet (using the azurerm provider) to deploy/update the microsoft.insights/workbooks resource.
2. IF a Terraform deployment is executed THEN the system SHALL allow setting values via Terraform variables (e.g., workspace IDs, management group IDs/paths) with support for tfvars and TF_VAR_ environment variables.
3. WHEN deploying to multiple regions or tenants THEN the system SHALL avoid hard-coded resource IDs by using Terraform variables and data sources, and SHALL support per-environment workspaces/state backends.
4. IF deployment fails due to RBAC or missing resource providers THEN the system SHALL document required roles and azurerm provider features settings necessary for the module.
5. WHEN a workbook version is updated in source control THEN CI validation SHALL run terraform fmt -check, terraform validate, and JSON schema/reference checks before release.

## Notes and assumptions

- Two Log Analytics Workspaces are the authoritative data sources; Application Insights tables may be present via LA.
- Open-source templates such as Microsoft Application-Insights-Workbooks and AMBA queries will be referenced and adapted where applicable.
- Target users include SREs, Cloud Ops, and Platform Engineers; primary use during incident response and weekly reviews.
- Non-goals: custom data collectors, third-party SaaS integrations, and visualization outside Azure Workbooks.