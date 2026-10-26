# A site behind the i3D.net CDN, reachable only from the office and VPN, with
# its CNAME in PowerDNS.

terraform {
  required_version = ">= 1.5"

  required_providers {
    restful = {
      source  = "magodo/restful"
      version = "~> 0.25"
    }
    powerdns = {
      source  = "pan-net/powerdns"
      version = "~> 1.5"
    }
  }
}

variable "cdn_api_key" {
  type      = string
  sensitive = true
}

variable "pdns_server_url" {
  type = string
}

variable "pdns_api_key" {
  type      = string
  sensitive = true
}

provider "restful" {
  base_url = "https://api.cdn-v2.i3d.net/api"
  security = {
    http = {
      token = {
        token = var.cdn_api_key
      }
    }
  }
}

provider "powerdns" {
  server_url = var.pdns_server_url
  api_key    = var.pdns_api_key
}

locals {
  hostname = "myapp.i3d.network"
}

module "cdn" {
  # Outside this repository: "github.com/i3dnet/terraform-i3dnet-cdn-site?ref=v0.1.0"
  source = "../.."

  name            = "myapp"
  group_code      = "other"
  initiative_code = "myteam"
  hostnames       = [{ fqdn = local.hostname, ssl_cn = "wildcard.i3d.network" }]
  origins = [{
    fqdn        = "myapp-origin.example.com"
    healthcheck = { path = "/healthz" }
  }]
  flags                = { auth_pass_through = true }
  predefined_allowlist = "i3d_office"
}

module "dns" {
  # Outside this repository: "github.com/i3dnet/terraform-i3dnet-cdn-site//modules/powerdns-cname?ref=v0.1.0"
  source = "../../modules/powerdns-cname"

  zone      = "i3d.network."
  hostnames = [local.hostname]
  target    = module.cdn.cname_target
}

output "cdn_resource_uid" {
  value = module.cdn.resource_uid
}
