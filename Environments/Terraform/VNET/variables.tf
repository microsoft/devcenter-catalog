variable "resource_group_name" {
  default     = "rg-unknown"
  description = "Name of the RG to get Terraform to stop complaining."
}

variable "name" {
  default     = "unset-name"
  description = "The root name to use for resources."
}

variable "location" {
  default     = "eastus"
  description = "The location of the RG."
}