variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "management_group_path" {
  type    = string
  default = ""
}

# Data sources to resolve two LA workspaces by name/RG for portability
variable "workspace1_name" { type = string }
variable "workspace1_rg" { type = string }
variable "workspace2_name" { type = string }
variable "workspace2_rg" { type = string }

# Optional tags for module resources
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to workbook resources"
}