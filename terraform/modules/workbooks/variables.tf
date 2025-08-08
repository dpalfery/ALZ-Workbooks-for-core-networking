variable "workbook_definitions" {
  description = "Map of workbook definitions to deploy"
  type = map(object({
    name                    = string
    display_name            = string
    category                = string
    source_id               = string
    data_json_template_path = string
    parameters              = map(string)
  }))
}

variable "workspace_ids" {
  description = "List of Log Analytics workspace IDs for parameter injection"
  type        = list(string)
}

variable "management_group_path" {
  description = "Management group path (optional) for parameter injection"
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure location for workbook resources"
  type        = string
}

variable "tags" {
  description = "Tags applied to workbook resources"
  type        = map(string)
  default     = {}
}

variable "slo_defaults" {
  description = "Default SLO targets map by service"
  type = map(object({
    availabilityPct = number
    latencyMs       = number
    errorRatePct    = number
  }))
  default = {}
}

variable "resource_group_name" {
  description = "Target resource group name where workbooks will be created"
  type        = string
}