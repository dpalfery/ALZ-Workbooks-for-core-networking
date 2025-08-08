output "workbook_ids" {
  description = "Map of workbook IDs by key"
  value       = { for k, v in azurerm_application_insights_workbook.this : k => v.id }
}