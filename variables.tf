variable "location" {
  description = "Azure region allowed by the student subscription policy (westeurope and francecentral are blocked here)."
  type        = string
  default     = "spaincentral"
}

variable "owner" {
  description = "Tag value, used to identify who created the resources."
  type        = string
  default     = "mohamed-amine-neji"
}

variable "node_vm_size" {
  description = "VM size for the single AKS node. The subscription policy allows B-series v2 only in spaincentral."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "owner_email" {
  description = "Address that receives the demo alert."
  type        = string
  default     = "medaminenj@gmail.com"
}

variable "alert_cpu_threshold" {
  description = "Node CPU percentage that triggers the demo alert."
  type        = number
  default     = 50
}
