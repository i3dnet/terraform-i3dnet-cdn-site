terraform {
  required_version = ">= 1.5"

  required_providers {
    powerdns = {
      source  = "pan-net/powerdns"
      version = "~> 1.5"
    }
  }
}

variable "zone" {
  description = "PowerDNS zone, with its trailing dot, for example \"i3d.network.\"."
  type        = string

  validation {
    condition     = endswith(var.zone, ".")
    error_message = "zone must end with a dot."
  }
}

variable "hostnames" {
  description = "Hostnames to point at the CDN, without trailing dots. Pass the CDN module's hostnames."
  type        = list(string)
}

variable "ttl" {
  description = "TTL of the records, in seconds."
  type        = number
  default     = 300
}

variable "target" {
  description = "Where the records point: the CDN module's cname_target output."
  type        = string
  default     = "static.cdn-v2.i3d.net."
}

resource "powerdns_record" "cname" {
  for_each = toset(var.hostnames)

  zone    = var.zone
  name    = "${each.key}."
  type    = "CNAME"
  ttl     = var.ttl
  records = [var.target]

  lifecycle {
    precondition {
      condition     = endswith("${each.key}.", ".${var.zone}")
      error_message = "Hostname ${each.key} is not in the zone ${var.zone}."
    }
  }
}

output "records" {
  description = "The CNAME records, by hostname."
  value       = { for h, r in powerdns_record.cname : h => r.id }
}
