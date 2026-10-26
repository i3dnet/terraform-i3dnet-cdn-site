# terraform-i3dnet-cdn-site

A Terraform module for one site behind the i3D.net CDN (CDN v2). It manages the CDN resource and its settings (origins, hostnames, flags and an optional predefined allowlist) through the CDN API, using the generic [`magodo/restful`](https://registry.terraform.io/providers/magodo/restful/latest) provider.

Every setting is read back from the API, so `terraform plan` shows changes made in the CDN dashboard, and `apply` puts them back. A submodule, [`modules/powerdns-cname`](modules/powerdns-cname), points the hostnames at the CDN in PowerDNS. If your DNS lives elsewhere, point a CNAME at the `cname_target` output instead.

## Usage

```hcl
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

module "cdn" {
  source = "github.com/i3dnet/terraform-i3dnet-cdn-site?ref=v0.1.0"

  name            = "myapp"
  group_code      = "other"
  initiative_code = "myteam"
  hostnames       = [{ fqdn = "myapp.i3d.network", ssl_cn = "wildcard.i3d.network" }]
  origins = [{
    fqdn        = "myapp-origin.example.com"
    healthcheck = { path = "/healthz" }
  }]
  flags                = { auth_pass_through = true }
  predefined_allowlist = "i3d_office"
}

provider "powerdns" {
  server_url = var.pdns_server_url
  api_key    = var.pdns_api_key
}

module "dns" {
  source = "github.com/i3dnet/terraform-i3dnet-cdn-site//modules/powerdns-cname?ref=v0.1.0"

  zone      = "i3d.network."
  hostnames = ["myapp.i3d.network"]
  target    = module.cdn.cname_target
}
```

[`examples/basic`](examples/basic) is the same configuration as a complete root module.

The CDN module needs only the `restful` provider. The submodule needs `pan-net/powerdns`. Both need Terraform 1.5 or later.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | | Name of the CDN resource (1 to 50 characters). Set on creation only; rename the resource in the dashboard. |
| `group_code` | string | | CDN group code, for example `other`. |
| `initiative_code` | string | | CDN initiative code. |
| `hostnames` | list of `{ fqdn, ssl_cn }` | | Public hostnames. `ssl_cn` names the edge certificate, for example `wildcard.i3d.network`. |
| `origins` | list of objects | | Origins. Each has `fqdn` and `healthcheck.path`. Optional: `port` (443), `ssl` (true), `verify_ssl` (true), `location` (`EU`), `dns_record` (`A`). Optional under `healthcheck`: `host` (the origin's URL), `expected_status_code` (200), `interval_ms` (15000), `timeout_ms` (2000), `min_valid_checks` (2). |
| `strategy` | string | `HASH` | How the edges pick an origin: `HASH`, `FALLBACK` or `RANDOM`. |
| `flags` | object | all defaults | `enabled` (true), `force_https` (true), `auth_pass_through` (false), `override_backend_host` (true), `override_health_host` (true), `use_i3d_static_dns` (false), `kill_switch` (false). |
| `predefined_allowlist` | string | `null` | A predefined allowlist key, for example `i3d_office` (the office and VPN). Null leaves the site open. |

The `powerdns-cname` submodule takes `zone` (with its trailing dot), `hostnames`, `ttl` (300) and `target` (`static.cdn-v2.i3d.net.`).

## Outputs

| Name | Description |
|---|---|
| `resource_uid` | UID of the CDN resource. |
| `resource_path` | API path of the resource, `/service/resource/<uid>`. |
| `cname_target` | Where each hostname's CNAME must point. |

## What the CDN API expects

These rules were learned against the live API. The module enforces or works around each of them.

- **Enums are names.** `strategy` (`HASH`, `FALLBACK`, `RANDOM`), `location` (`EU`, `NAW`, `NAE`, `APAC`) and `dns_record` (`A`, `SRV`) are JSON strings, although the API's swagger lists them as integers. A zero or missing value makes the backend update fail with a bare HTTP 500, so the module always sends all three and validates them.
- **Health checks run at least every 15 seconds.** `interval_ms` below 15000 is rejected; the module checks this at plan time.
- **`ssl_cn` names a certificate on the edges, not the hostname.** The API accepts any value, so a wrong name only shows up as broken HTTPS. For `*.i3d.network` it is `wildcard.i3d.network`.
- **Flags.** `override_backend_host` sends the origin's own FQDN as the `Host` header, which matches its TLS name. `auth_pass_through` forwards the `Authorization` header, which an API that takes bearer tokens needs. The module always sends every flag.
- **The resource is created once.** Updating the resource itself takes a different body than creating it, and could reset other fields, so the module ignores changes to `name`, `group_code` and `initiative_code` after creation.
- **Create DNS records before anyone looks the name up.** A lookup made before the record exists is cached as "no such name" for the zone's SOA minimum, which is an hour for `i3d.network`.

## Drift detection

Each setting is a `restful_resource` created with `PUT` and read with `GET` on the same path. The API returns exactly the shape it accepts, so a plan compares them directly:

```
  # module.cdn.restful_resource.flags will be updated in-place
      ~ body = {
          ~ enabled = false -> true
```

With `predefined_allowlist` set, the hostnames and flags are applied only after the allowlist. If the allowlist is rejected, a site meant to be private is never published.

## Adopting a site configured with `restful_operation`

Sites configured with `restful_operation` (write-only, no drift detection) can move onto the module without touching the live site.

1. **Replace the configuration.** Swap the resources for the module call (and the `powerdns-cname` submodule).
2. **Add `moved` blocks** for the CDN resource and the DNS record:

   ```hcl
   moved {
     from = restful_resource.cdn
     to   = module.cdn.restful_resource.cdn
   }

   moved {
     from = powerdns_record.myapp
     to   = module.dns.powerdns_record.cname["myapp.i3d.network"]
   }
   ```

3. **Add `import` blocks** for the settings. In Terraform 1.5 the id must be a literal string; replace `UID` with the resource's uid:

   ```hcl
   import {
     to = module.cdn.restful_resource.backend
     id = "{\"id\":\"/service/resource/UID/backend\",\"path\":\"/service/resource/UID/backend\",\"body\":{\"strategy\":null,\"origin_list\":null}}"
   }

   import {
     to = module.cdn.restful_resource.hostnames
     id = "{\"id\":\"/service/resource/UID/hostnames\",\"path\":\"/service/resource/UID/hostnames\"}"
   }

   import {
     to = module.cdn.restful_resource.flags
     id = "{\"id\":\"/service/resource/UID/flags\",\"path\":\"/service/resource/UID/flags\",\"body\":{\"enabled\":null,\"force_https\":null,\"auth_pass_through\":null,\"override_backend_host\":null,\"override_health_host\":null,\"use_i3d_static_dns\":null,\"kill_switch\":null}}"
   }

   import {
     to = module.cdn.restful_resource.allowlist[0]
     id = "{\"id\":\"/service/resource/UID/predefined-allowlist\",\"path\":\"/service/resource/UID/predefined-allowlist\",\"body\":{\"key\":null}}"
   }
   ```

4. **Remove the old `restful_operation` resources from state before planning**, for example `terraform state rm restful_operation.backend`. If they stay in state, the plan destroys them, and destroying a `restful_operation` sends `DELETE` to the live settings. On Terraform 1.7 or later, use `removed` blocks with `lifecycle { destroy = false }` instead.

5. **Check the plan.** It should show 2 moved, 4 imported, 0 added and 0 destroyed.
   - The imported settings also show as in-place updates. An import can't know `create_method`, `update_method` and `delete_method`, so Terraform fills them in.
   - Their bodies don't change, and the provider only calls the API when the body changes.

`tests/run.sh` rehearses exactly this sequence. It checks that the adoption sends no write request to the APIs and that the next plan is clean.

## Tests

```sh
tests/run.sh                                   # uses terraform from PATH
TERRAFORM=/path/to/terraform tests/run.sh      # another version
```

The tests run against `tests/mock_api.py`, an in-memory stand-in for the CDN and PowerDNS APIs that reproduces the API behaviour above. They need Python 3, `curl`, `jq` and network access to the Terraform registry for the providers. CI runs them on Terraform 1.5.7 and the latest release.

## Not covered yet

The module manages origins, hostnames, flags and the predefined allowlist. Other CDN features (custom headers, deny lists, redirects, rate limits, purges) are not managed here. Renaming a resource is a dashboard step.
