terraform {
  required_providers {
    restful = {
      source = "magodo/restful"
    }
    powerdns = {
      source = "pan-net/powerdns"
    }
  }
}

variable "port" {
  type = number
}

variable "strategy" {
  type    = string
  default = "HASH"
}

variable "location" {
  type    = string
  default = "EU"
}

variable "interval_ms" {
  type    = number
  default = 15000
}

variable "allowlist" {
  type    = string
  default = "i3d_office"
}

variable "hostname" {
  type    = string
  default = "app.example.test"
}

provider "restful" {
  base_url = "http://127.0.0.1:${var.port}/api"
  security = {
    http = {
      token = {
        token = "test"
      }
    }
  }
}

provider "powerdns" {
  server_url = "http://127.0.0.1:${var.port}"
  api_key    = "test"
}

module "site" {
  source = "../../.."

  name            = "app"
  group_code      = "other"
  initiative_code = "test"
  hostnames       = [{ fqdn = var.hostname, ssl_cn = "wildcard.example.test" }]
  origins = [{
    fqdn        = "app-production.cluster.example.test"
    location    = var.location
    healthcheck = { path = "/healthz", interval_ms = var.interval_ms }
  }]
  strategy             = var.strategy
  flags                = { auth_pass_through = true }
  predefined_allowlist = var.allowlist
}

module "dns" {
  source = "../../../modules/powerdns-cname"

  zone      = "example.test."
  hostnames = [var.hostname]
  target    = module.site.cname_target
}

output "resource_path" {
  value = module.site.resource_path
}

output "resource_uid" {
  value = module.site.resource_uid
}
