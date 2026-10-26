output "resource_uid" {
  description = "UID of the CDN resource."
  value       = restful_resource.cdn.output.uid
}

output "resource_path" {
  description = "API path of the CDN resource, /service/resource/<uid>."
  value       = restful_resource.cdn.id
}

output "cname_target" {
  description = "Where each hostname's DNS record must point (a CNAME), whatever manages the zone."
  value       = "static.cdn-v2.i3d.net."
}
