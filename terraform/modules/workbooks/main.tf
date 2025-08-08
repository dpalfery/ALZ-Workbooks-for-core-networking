data "azurerm_resource_group" "target" {
  name = var.resource_group_name
}

resource "azurerm_application_insights_workbook" "this" {
  for_each            = var.workbook_definitions
  name                = each.value.name
  display_name        = each.value.display_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.target.name
  category            = each.value.category
  source_id           = each.value.source_id

  // Render the JSON template with parameter injection
  data_json = templatefile(each.value.data_json_template_path, merge(each.value.parameters, {
    workspace_ids = var.workspace_ids
    mg_path       = var.management_group_path
    slo_defaults  = var.slo_defaults
  }))

  tags = var.tags
}