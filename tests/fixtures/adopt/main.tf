# The legacy fixture's site, moved onto the module. Before planning, remove the
# four restful_operation settings from state (terraform state rm): Terraform 1.5
# has no `removed` block, and leaving them in state would DELETE the live
# settings. Then this plan moves two resources, imports four, and changes nothing.
# The import blocks are in imports.tf, which run.sh writes from imports.tf.tpl
# with the legacy resource's path: Terraform 1.5 takes only a literal string as
# an import id.

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
  hostnames       = [{ fqdn = "app.example.test", ssl_cn = "wildcard.example.test" }]
  origins = [{
    fqdn        = "app-production.cluster.example.test"
    healthcheck = { path = "/healthz" }
  }]
  flags                = { auth_pass_through = true }
  predefined_allowlist = "i3d_office"
}

module "dns" {
  source = "../../../modules/powerdns-cname"

  zone      = "example.test."
  hostnames = ["app.example.test"]
  target    = module.site.cname_target
}

moved {
  from = restful_resource.cdn
  to   = module.site.restful_resource.cdn
}

moved {
  from = powerdns_record.app
  to   = module.dns.powerdns_record.cname["app.example.test"]
}
