#!/usr/bin/env bash
# End-to-end tests of the module against tests/mock_api.py, an in-memory stand-in
# for the CDN v2 and PowerDNS APIs. Needs terraform (>= 1.5), python3, curl and
# jq; the providers come from the Terraform registry.
#   TERRAFORM=/path/to/terraform MOCK_PORT=18080 tests/run.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fixtures=$here/fixtures
tf=${TERRAFORM:-terraform}
port=${MOCK_PORT:-18080}
work=$(mktemp -d)
mock=

clean_fixtures() {
  for d in site cdn-only legacy adopt; do
    rm -rf "$fixtures/$d/.terraform" "$fixtures/$d/.terraform.lock.hcl" "$fixtures/$d"/terraform.tfstate*
  done
  rm -f "$fixtures/adopt/imports.tf"
}
cleanup() {
  if [ -n "$mock" ]; then kill "$mock" 2>/dev/null || true; fi
  clean_fixtures
  rm -rf "$work"
}
trap cleanup EXIT
clean_fixtures

export TF_IN_AUTOMATION=1 TF_INPUT=0 TF_VAR_port=$port
export TF_PLUGIN_CACHE_DIR=${TF_PLUGIN_CACHE_DIR:-$work/plugins}
mkdir -p "$TF_PLUGIN_CACHE_DIR"

python3 -I "$here/mock_api.py" "$port" 2>"$work/mock.log" &
mock=$!
for _ in $(seq 50); do
  curl -sf "http://127.0.0.1:$port/api/v1/servers" >/dev/null && break
  sleep 0.1
done

n=0
ok() {
  n=$((n + 1))
  echo "ok $n - $1"
}
fail() {
  echo "not ok - $1" >&2
  tail -40 "$work/out.txt" >&2 2>/dev/null || true
  exit 1
}
# run DIR COMMAND ARGS...: terraform in a fixture, output in $work/out.txt.
run() {
  local dir=$1 command=$2
  shift 2
  "$tf" -chdir="$fixtures/$dir" "$command" -no-color "$@" >"$work/out.txt" 2>&1
}
# plan_rc DIR ARGS...: prints plan -detailed-exitcode's status (0 clean, 2 changes).
plan_rc() {
  local dir=$1 rc=0
  shift
  run "$dir" plan -detailed-exitcode "$@" || rc=$?
  echo "$rc"
}
# put PATH BODY: a dashboard edit, made directly on the API.
put() {
  curl -sf -X PUT -H 'Authorization: Bearer test' -H 'Content-Type: application/json' \
    "http://127.0.0.1:$port/api$1" -d "$2" >/dev/null
}
get_status() {
  curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer test' "http://127.0.0.1:$port/api$1"
}
expect_invalid() { # VAR=VALUE MESSAGE
  if run site plan -var "$1"; then fail "plan with $1 should fail"; fi
  grep -q "$2" "$work/out.txt" || fail "plan with $1 should say: $2"
  ok "rejects $1"
}

# A site --------------------------------------------------------------------

run site init || fail "init the site fixture"
run site apply -auto-approve || fail "apply a site"
grep -q 'Resources: 6 added' "$work/out.txt" || fail "apply a site: resource, four settings, one CNAME"
ok "a site applies: the resource, four settings and a CNAME"

[ "$(plan_rc site)" = 0 ] || fail "a second plan has no changes"
ok "a second plan has no changes (every setting reads back as written)"

path=$("$tf" -chdir="$fixtures/site" output -raw resource_path)
put "$path/flags" '{"enabled":false,"force_https":true,"auth_pass_through":true,"override_backend_host":true,"override_health_host":true,"use_i3d_static_dns":false,"kill_switch":false}'
put "$path/hostnames" '[{"fqdn":"app.example.test","ssl_cn":"app.example.test"}]'
put "$path/backend" '{"strategy":"RANDOM","origin_list":[{"fqdn":"app-production.cluster.example.test","port":443,"ssl":true,"verify_ssl":true,"location":"EU","dns_record":"A","healthcheck":{"path":"/healthz","host":"https://app-production.cluster.example.test","expected_status_code":200,"interval_ms":15000,"timeout_ms":2000,"min_valid_checks":2}}]}'
put "$path/predefined-allowlist" '{"key":"somewhere_else"}'
[ "$(plan_rc site)" = 2 ] || fail "dashboard edits show in the plan"
for setting in 'flags' 'hostnames' 'backend' 'allowlist\[0\]'; do
  grep -q "module.site.restful_resource.$setting will be updated in-place" "$work/out.txt" ||
    fail "a dashboard edit to $setting shows in the plan"
  ok "a dashboard edit to ${setting%%\\*} shows in the plan"
done
run site apply -auto-approve || fail "apply restores the settings"
[ "$(plan_rc site)" = 0 ] || fail "after apply the plan is clean again"
ok "apply puts the settings back"

expect_invalid interval_ms=10000 'at least 15000'
expect_invalid strategy=NO_STRATEGY 'strategy must be HASH, FALLBACK or RANDOM'
expect_invalid location=XX 'location must be one of'
expect_invalid hostname=app.other.test 'is not in the zone'

run site destroy -auto-approve || fail "destroy the site"
[ "$(get_status "$path")" = 404 ] || fail "destroy deletes the CDN resource"
rrsets=$(curl -s "http://127.0.0.1:$port/api/v1/servers/localhost/zones/example.test." | jq '.rrsets | length')
[ "$rrsets" = 0 ] || fail "destroy deletes the CNAME"
ok "destroy deletes the resource and the CNAME"

# The CDN module alone, with no PowerDNS provider configured -------------------

run cdn-only init || fail "init the cdn-only fixture"
run cdn-only apply -auto-approve || fail "apply a site with only the restful provider"
[ "$(plan_rc cdn-only)" = 0 ] || fail "a cdn-only site plans clean"
run cdn-only destroy -auto-approve || fail "destroy the cdn-only site"
ok "the CDN module works without the PowerDNS provider"

# Adopting a site configured with restful_operation ---------------------------

run legacy init || fail "init the legacy fixture"
run legacy apply -auto-approve || fail "apply the legacy site"
path=$("$tf" -chdir="$fixtures/legacy" output -raw resource_path)
cp "$fixtures/legacy/terraform.tfstate" "$fixtures/adopt/terraform.tfstate"
sed "s#__RESOURCE_PATH__#$path#g" "$fixtures/adopt/imports.tf.tpl" >"$fixtures/adopt/imports.tf"
run adopt init || fail "init the adopt fixture"
for setting in backend hostnames flags allowlist; do
  "$tf" -chdir="$fixtures/adopt" state rm "restful_operation.$setting" >"$work/out.txt" 2>&1 ||
    fail "state rm restful_operation.$setting"
done
run adopt plan -out="$work/adopt.plan" || fail "plan the adoption"
"$tf" -chdir="$fixtures/adopt" show -json "$work/adopt.plan" >"$work/adopt.json"
jq -e '[.resource_changes[].change.actions[] | select(. == "create" or . == "delete")] | length == 0' "$work/adopt.json" >/dev/null ||
  fail "the adoption plan creates and destroys nothing"
# Imported settings show as in-place updates because an import can't know
# create_method and friends; their bodies are unchanged, and the provider only
# calls the API when the body changes (checked by the no-writes test below).
jq -e '[.resource_changes[] | select(.change.actions == ["update"]) | select(.change.before.body != .change.after.body)] | length == 0' "$work/adopt.json" >/dev/null ||
  fail "the adoption plan changes no setting's body"
jq -e '[.resource_changes[] | select(.change.importing != null)] | length == 4' "$work/adopt.json" >/dev/null ||
  fail "the adoption plan imports the four settings"
jq -e '[.resource_changes[] | select(.previous_address != null)] | length == 2' "$work/adopt.json" >/dev/null ||
  fail "the adoption plan moves the resource and the CNAME"
ok "adoption plan: 2 moved, 4 imported, no body changed, nothing created or destroyed"

before=$(wc -l <"$work/mock.log")
run adopt apply "$work/adopt.plan" || fail "apply the adoption"
writes=$(tail -n +"$((before + 1))" "$work/mock.log" | grep -cE 'mock: (POST|PUT|PATCH|DELETE) ' || true)
[ "$writes" = 0 ] || fail "adoption sends no writes to the APIs (saw $writes)"
ok "adoption sends no writes to the APIs"

[ "$(plan_rc adopt)" = 0 ] || fail "after adoption the plan is clean"
ok "after adoption the plan is clean"

run adopt destroy -auto-approve || fail "destroy the adopted site"
[ "$(get_status "$path")" = 404 ] || fail "destroy deletes the adopted resource"
ok "the adopted site destroys cleanly"

echo "1..$n"
