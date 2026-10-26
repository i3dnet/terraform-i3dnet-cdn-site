import {
  to = module.site.restful_resource.backend
  id = "{\"id\":\"__RESOURCE_PATH__/backend\",\"path\":\"__RESOURCE_PATH__/backend\",\"body\":{\"strategy\":null,\"origin_list\":null}}"
}

import {
  to = module.site.restful_resource.hostnames
  id = "{\"id\":\"__RESOURCE_PATH__/hostnames\",\"path\":\"__RESOURCE_PATH__/hostnames\"}"
}

import {
  to = module.site.restful_resource.flags
  id = "{\"id\":\"__RESOURCE_PATH__/flags\",\"path\":\"__RESOURCE_PATH__/flags\",\"body\":{\"enabled\":null,\"force_https\":null,\"auth_pass_through\":null,\"override_backend_host\":null,\"override_health_host\":null,\"use_i3d_static_dns\":null,\"kill_switch\":null}}"
}

import {
  to = module.site.restful_resource.allowlist[0]
  id = "{\"id\":\"__RESOURCE_PATH__/predefined-allowlist\",\"path\":\"__RESOURCE_PATH__/predefined-allowlist\",\"body\":{\"key\":null}}"
}
