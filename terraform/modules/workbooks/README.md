# Azure Monitor Workbooks Module

Deploy Azure Monitor Workbooks from JSON templates using the azurerm provider. This module renders a JSON workbook template with parameter injection and creates one or more `microsoft.insights/workbooks` resources.

Traceability: requirements 12.1–12.5, 10.3

## Inputs

- resource_group_name (string) Target resource group name for workbook resources.
- location (string) Azure region.
- workspace_ids (list(string)) List of Log Analytics Workspace resource IDs to inject into templates.
- management_group_path (string) Management Group path (optional) to inject into templates. Default: "".
- tags (map(string)) Tags applied to workbook resources. Default: {}.
- slo_defaults (map(object))
  - availabilityPct (number)
  - latencyMs (number)
  - errorRatePct (number)
- workbook_definitions (map(object))
  - name (string) Workbook resource name
  - display_name (string) Workbook displayName
  - category (string) Typically "workbook"
  - source_id (string) Source resource id (commonly a LAW id or RG id)
  - data_json_template_path (string) Path to the JSON template file
  - parameters (map(string)) Arbitrary template variables to merge, e.g., workspace1 = "<LAW id>", workspace2 = "<LAW id>"

## Outputs

- workbook_ids (map(string)) Map of created workbook resource IDs keyed by `workbook_definitions` keys

## Example

See a working example under `terraform/examples/single_rg`.

```hcl
module "workbooks" {
  source                = "../../modules/workbooks"
  resource_group_name   = data.azurerm_resource_group.rg.name
  location              = var.location
  workspace_ids         = [data.azurerm_log_analytics_workspace.w1.id, data.azurerm_log_analytics_workspace.w2.id]
  management_group_path = var.management_group_path
  workbook_definitions = {
    core = {
      name                    = "lz-sre-core"
      display_name            = "LZ SRE Core"
      category                = "workbook"
      source_id               = data.azurerm_log_analytics_workspace.w1.id
      data_json_template_path = "${path.module}/../../workbooks/templates/core_workbook.json"
      parameters              = {
        workspace1 = data.azurerm_log_analytics_workspace.w1.id
        workspace2 = data.azurerm_log_analytics_workspace.w2.id
      }
    }
  }
  tags = {
    env   = "test"
    owner = "sre"
  }
}
```

## Notes

- This module uses `templatefile()` to inject parameters into the JSON template. Ensure your template references variables using Terraform template syntax when needed (e.g., `"${workspace1}"`).
- RBAC: the deploying principal needs Contributor on the target RG and Reader on referenced workspaces for validation/usage.
- Provider: `azurerm >= 3.50.0`
- State: manage per-environment state backends as appropriate.

## CI

- `scripts/tf_validate.ps1` runs `terraform fmt -check` and `terraform validate` on both module and example.
- `scripts/tf_plan_example.ps1` optionally runs `terraform plan` for the example.
