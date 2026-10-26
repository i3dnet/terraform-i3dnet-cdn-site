locals {
  origin_list = [for o in var.origins : {
    fqdn       = o.fqdn
    port       = o.port
    ssl        = o.ssl
    verify_ssl = o.verify_ssl
    location   = o.location
    dns_record = o.dns_record
    healthcheck = {
      path                 = o.healthcheck.path
      host                 = coalesce(o.healthcheck.host, "${o.ssl ? "https" : "http"}://${o.fqdn}")
      expected_status_code = o.healthcheck.expected_status_code
      interval_ms          = o.healthcheck.interval_ms
      timeout_ms           = o.healthcheck.timeout_ms
      min_valid_checks     = o.healthcheck.min_valid_checks
    }
  }]
}

resource "restful_resource" "cdn" {
  path      = "/service/resource"
  read_path = "$(path)/$(body.uid)"
  body = {
    name           = var.name
    groupCode      = var.group_code
    initiativeCode = var.initiative_code
  }

  # PUT /service/resource/{uid} takes a different body than POST (no group or
  # initiative, plus fields such as enabled and dns), so an update could reset
  # them. The resource is created once; renames are a dashboard step.
  lifecycle {
    ignore_changes = [body]
  }
}

# Each setting is its own sub-resource: PUT creates or replaces it, GET returns
# the same shape (enums as names), so a plan shows edits made in the dashboard.

resource "restful_resource" "backend" {
  path          = "${restful_resource.cdn.id}/backend"
  create_method = "PUT"
  update_method = "PUT"
  delete_method = "DELETE"
  body = {
    strategy    = var.strategy
    origin_list = local.origin_list
  }
}

resource "restful_resource" "hostnames" {
  path          = "${restful_resource.cdn.id}/hostnames"
  create_method = "PUT"
  update_method = "PUT"
  delete_method = "DELETE"
  body          = [for h in var.hostnames : { fqdn = h.fqdn, ssl_cn = h.ssl_cn }]

  # Fail closed: publish the hostnames only once the allowlist is in place, and
  # on destroy remove them before the allowlist.
  depends_on = [restful_resource.allowlist]
}

resource "restful_resource" "flags" {
  path          = "${restful_resource.cdn.id}/flags"
  create_method = "PUT"
  update_method = "PUT"
  delete_method = "DELETE"
  body          = var.flags

  # Fail closed, as for hostnames: enable the site only behind its allowlist.
  depends_on = [restful_resource.allowlist]
}

resource "restful_resource" "allowlist" {
  count = var.predefined_allowlist == null ? 0 : 1

  path          = "${restful_resource.cdn.id}/predefined-allowlist"
  create_method = "PUT"
  update_method = "PUT"
  delete_method = "DELETE"
  body          = { key = var.predefined_allowlist }
}
