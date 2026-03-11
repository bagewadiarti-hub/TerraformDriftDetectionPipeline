variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "drift-detection-rg"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westus2"
}

variable "environment" {
  description = "Environment tag value"
  type        = string
  default     = "dev"
}
