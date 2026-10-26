# A site configured inline with write-only restful_operation settings, the way
# configurations did before this module. The adopt fixture moves it over.

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

resource "restful_resource" "cdn" {
  path      = "/service/resource"
  read_path = "$(path)/$(body.uid)"
  body = {
    name           = "app"
    groupCode      = "other"
    initiativeCode = "test"
  }

  lifecycle {
    ignore_changes = [body]
  }
}

resource "restful_operation" "backend" {
  path          = "${restful_resource.cdn.id}/backend"
  method        = "PUT"
  delete_method = "DELETE"
  body = {
    strategy = "HASH"
    origin_list = [{
      dns_record = "A"
      fqdn       = "app-production.cluster.example.test"
      location   = "EU"
      port       = 443
      ssl        = true
      verify_ssl = true
      healthcheck = {
        path                 = "/healthz"
        host                 = "https://app-production.cluster.example.test"
        expected_status_code = 200
        interval_ms          = 15000
        timeout_ms           = 2000
        min_valid_checks     = 2
      }
    }]
  }
}

resource "restful_operation" "hostnames" {
  path          = "${restful_resource.cdn.id}/hostnames"
  method        = "PUT"
  delete_method = "DELETE"
  body          = [{ fqdn = "app.example.test", ssl_cn = "wildcard.example.test" }]
}

resource "restful_operation" "flags" {
  path          = "${restful_resource.cdn.id}/flags"
  method        = "PUT"
  delete_method = "DELETE"
  body = {
    enabled               = true
    force_https           = true
    auth_pass_through     = true
    override_backend_host = true
    override_health_host  = true
    use_i3d_static_dns    = false
    kill_switch           = false
  }
}

resource "restful_operation" "allowlist" {
  path          = "${restful_resource.cdn.id}/predefined-allowlist"
  method        = "PUT"
  delete_method = "DELETE"
  body          = { key = "i3d_office" }
}

resource "powerdns_record" "app" {
  zone    = "example.test."
  name    = "app.example.test."
  type    = "CNAME"
  ttl     = 300
  records = ["static.cdn-v2.i3d.net."]
}

output "resource_path" {
  value = restful_resource.cdn.id
}
