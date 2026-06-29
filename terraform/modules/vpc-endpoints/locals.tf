locals {
  service_endpoints = {
    for service in var.vpc_endpoints : service.service_name => service
  }
}
