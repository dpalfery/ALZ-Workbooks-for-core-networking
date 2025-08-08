terraform {
  required_version = ">= 1.3.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.50.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

data "azurerm_log_analytics_workspace" "w1" {
  name                = var.workspace1_name
  resource_group_name = var.workspace1_rg
}

data "azurerm_log_analytics_workspace" "w2" {
  name                = var.workspace2_name
  resource_group_name = var.workspace2_rg
}

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
      parameters              = { workspace1 = data.azurerm_log_analytics_workspace.w1.id, workspace2 = data.azurerm_log_analytics_workspace.w2.id }
    }
  }

  tags = var.tags
}