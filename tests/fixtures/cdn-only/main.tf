# The module with only the restful provider configured: a site whose DNS is
# managed elsewhere (external-dns, another provider, by hand).

terraform {
  required_providers {
    restful = {
      source = "magodo/restful"
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

module "site" {
  source = "../../.."

  name            = "plain"
  group_code      = "other"
  initiative_code = "test"
  hostnames       = [{ fqdn = "plain.example.test", ssl_cn = "wildcard.example.test" }]
  origins         = [{ fqdn = "plain-origin.example.test", healthcheck = { path = "/healthz" } }]
}

output "resource_path" {
  value = module.site.resource_path
}
