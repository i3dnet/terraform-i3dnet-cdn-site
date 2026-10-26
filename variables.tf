variable "name" {
  description = "Name of the CDN resource, as shown in the CDN dashboard. Terraform sets it on creation only; rename the resource in the dashboard."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 50
    error_message = "name must be 1 to 50 characters (the CDN API's limit)."
  }
}

variable "group_code" {
  description = "CDN group code the resource is billed to, for example \"other\"."
  type        = string
}

variable "initiative_code" {
  description = "CDN initiative code the resource is billed to."
  type        = string
}

variable "hostnames" {
  description = <<-EOT
    Public hostnames the CDN serves. `ssl_cn` names the edge certificate to present
    (for example "wildcard.i3d.network"), not the hostname. The API accepts any value
    without checking it, so a wrong name only shows up as broken HTTPS.
  EOT
  type = list(object({
    fqdn   = string
    ssl_cn = string
  }))

  validation {
    condition     = length(var.hostnames) > 0
    error_message = "hostnames needs at least one entry."
  }

  validation {
    condition     = alltrue([for h in var.hostnames : !endswith(h.fqdn, ".") && h.ssl_cn != ""])
    error_message = "Each hostname needs an fqdn without a trailing dot and a non-empty ssl_cn."
  }
}

variable "origins" {
  description = <<-EOT
    Origins behind the CDN. `location` and `dns_record` default to "EU" and "A"; the API
    rejects their zero values with a bare HTTP 500, so the module always sends them.
    `healthcheck.host` defaults to the origin's URL (scheme from `ssl`).
  EOT
  type = list(object({
    fqdn       = string
    port       = optional(number, 443)
    ssl        = optional(bool, true)
    verify_ssl = optional(bool, true)
    location   = optional(string, "EU")
    dns_record = optional(string, "A")
    healthcheck = object({
      path                 = string
      host                 = optional(string)
      expected_status_code = optional(number, 200)
      interval_ms          = optional(number, 15000)
      timeout_ms           = optional(number, 2000)
      min_valid_checks     = optional(number, 2)
    })
  }))

  validation {
    condition     = length(var.origins) > 0
    error_message = "origins needs at least one entry."
  }

  validation {
    condition     = alltrue([for o in var.origins : contains(["EU", "NAW", "NAE", "APAC"], o.location)])
    error_message = "origins[*].location must be one of EU, NAW, NAE, APAC."
  }

  validation {
    condition     = alltrue([for o in var.origins : contains(["A", "SRV"], o.dns_record)])
    error_message = "origins[*].dns_record must be A or SRV."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.healthcheck.interval_ms >= 15000])
    error_message = "origins[*].healthcheck.interval_ms must be at least 15000 (the CDN's minimum)."
  }
}

variable "strategy" {
  description = "How the edges pick an origin: HASH, FALLBACK or RANDOM."
  type        = string
  default     = "HASH"

  validation {
    condition     = contains(["HASH", "FALLBACK", "RANDOM"], var.strategy)
    error_message = "strategy must be HASH, FALLBACK or RANDOM."
  }
}

variable "flags" {
  description = <<-EOT
    Resource flags. Every flag is always sent. `override_backend_host` sends the origin's
    own FQDN as the Host header; `auth_pass_through` forwards the Authorization header,
    which an API taking bearer tokens needs.
  EOT
  type = object({
    enabled               = optional(bool, true)
    force_https           = optional(bool, true)
    auth_pass_through     = optional(bool, false)
    override_backend_host = optional(bool, true)
    override_health_host  = optional(bool, true)
    use_i3d_static_dns    = optional(bool, false)
    kill_switch           = optional(bool, false)
  })
  default = {}
}

variable "predefined_allowlist" {
  description = "Key of a predefined allowlist, for example \"i3d_office\" (the office and VPN). Null leaves the site open to everyone."
  type        = string
  default     = null
}
