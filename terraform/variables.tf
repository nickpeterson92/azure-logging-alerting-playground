variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "West US"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-monitoring-playground"
}

variable "admin_username" {
  description = "Admin username for the Windows VM"
  type        = string
  default     = "azureadmin"
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Admin password for the Windows VM"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
}

variable "vm_size" {
  description = "Size of the Windows VM"
  type        = string
  default     = "Standard_B2s"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Playground"
    Purpose     = "Monitoring-Alerting-POC"
    ManagedBy   = "Terraform"
  }
}
