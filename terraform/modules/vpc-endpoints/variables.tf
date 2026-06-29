variable "vpc_id" {
  type        = string
  description = "VPC id"
}

variable "vpc_endpoints" {
  type = list(object({
    service_name      = string
    route_table_ids   = optional(list(string))
    subnet_ids        = optional(list(string))
    vpc_endpoint_type = string
  }))
  description = "List of VPC endpoints to create"

  validation {
    condition     = length(var.vpc_endpoints) > 0
    error_message = "vpc_endpoints must not be empty"
  }

  validation {
    condition = alltrue([
      for endpoint in var.vpc_endpoints :
      endpoint.vpc_endpoint_type != "Interface" ||
      length(coalesce(endpoint.subnet_ids, [])) > 0
    ])

    error_message = "For Interface endpoints, you need subnet_ids."
  }

  validation {
    condition = alltrue([
      for endpoint in var.vpc_endpoints :
      endpoint.vpc_endpoint_type != "Gateway" ||
      length(coalesce(endpoint.route_table_ids, [])) > 0
    ])

    error_message = "For Gateway endpoints, you need route_table_ids."
  }
}
