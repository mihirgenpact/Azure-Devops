variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "myapp"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "aks_node_count" {
  description = "Number of nodes in the default AKS node pool"
  type        = number
  default     = 2
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS (leave null to use latest supported)"
  type        = string
  default     = null
}
