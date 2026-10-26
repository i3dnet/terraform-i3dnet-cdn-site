"""In-memory stand-in for the CDN v2 API and the PowerDNS API, for the module's tests.

It reproduces the CDN API behaviour the module depends on, as observed on the
real API in October 2026:
- enums travel as names; a zero or missing enum makes PUT /backend answer a
  bare HTTP 500 with no body;
- a health-check interval under 15 s is a 400;
- GET on a setting returns exactly what PUT stored;
- GET /service/resource/{uid} returns a different, larger shape than POST takes.

Usage: python3 -I mock_api.py PORT
"""

import json
import re
import sys
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STRATEGIES = {"HASH", "FALLBACK", "RANDOM"}
LOCATIONS = {"EU", "NAW", "NAE", "APAC"}
DNS_RECORDS = {"A", "SRV"}
SETTINGS = {"backend", "hostnames", "flags", "predefined-allowlist"}

resources = {}  # uid -> {"name", "groupCode", "initiativeCode", "settings": {name: body}}
zones = {}  # zone name -> {(name, type): rrset}


def backend_error(body):
    """Return (status, message) for an invalid backend body, or None."""
    if body.get("strategy") not in STRATEGIES:
        return 500, None
    for origin in body.get("origin_list") or []:
        if origin.get("location") not in LOCATIONS or origin.get("dns_record") not in DNS_RECORDS:
            return 500, None
        if (origin.get("healthcheck") or {}).get("interval_ms", 0) < 15000:
            return 400, "health check interval must be at least 15 seconds"
    return None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("mock: %s %s\n" % (self.command, self.path))

    def reply(self, status, body=None):
        data = b"" if body is None else json.dumps(body).encode()
        self.send_response(status)
        if body is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"null")

    def dispatch(self):
        path = self.path.split("?", 1)[0]
        if path.startswith("/api/v1/"):
            return self.powerdns(path)
        if path.startswith("/api/service/resource"):
            if not self.headers.get("Authorization", "").startswith("Bearer "):
                return self.reply(401, {"error": "unauthorized"})
            return self.cdn(path[len("/api/service/resource"):])
        sys.stderr.write("mock: unhandled %s %s\n" % (self.command, self.path))
        return self.reply(404, {"error": "not found"})

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = dispatch

    # CDN v2 -----------------------------------------------------------------

    def cdn(self, rest):
        if rest == "" and self.command == "POST":
            body = self.read_json()
            uid = uuid.uuid4().hex[:22]
            resources[uid] = {k: body.get(k) for k in ("name", "groupCode", "initiativeCode")}
            resources[uid]["settings"] = {}
            return self.reply(201, {**{k: body.get(k) for k in ("name", "groupCode", "initiativeCode")}, "uid": uid})

        m = re.fullmatch(r"/([^/]+)(?:/([^/]+))?", rest)
        if not m or m.group(1) not in resources:
            return self.reply(404, {"error": "resource not found"})
        uid, setting = m.group(1), m.group(2)
        res = resources[uid]

        if setting is None:
            if self.command == "GET":
                return self.reply(200, {
                    "name": res["name"], "groupCode": res["groupCode"], "initiativeCode": res["initiativeCode"],
                    "uid": uid, "path": "", "hash": "", "dns": "", "ssl": "", "enabled": False,
                    "filewatcherEnabled": False, "BillingTemplateId": 0, "originId": 0, "dnsList": None,
                })
            if self.command == "DELETE":
                del resources[uid]
                return self.reply(204)
            return self.reply(405, {"error": "method not allowed"})

        if setting not in SETTINGS:
            return self.reply(404, {"error": "unknown setting"})
        if self.command == "GET":
            if setting not in res["settings"]:
                return self.reply(404, {"error": "not set"})
            return self.reply(200, res["settings"][setting])
        if self.command == "PUT":
            body = self.read_json()
            if setting == "backend":
                err = backend_error(body)
                if err:
                    status, message = err
                    return self.reply(status, None if message is None else {"error": message})
            res["settings"][setting] = body
            return self.reply(200 if setting == "predefined-allowlist" else 201, body)
        if self.command == "DELETE":
            res["settings"].pop(setting, None)
            return self.reply(204)
        return self.reply(405, {"error": "method not allowed"})

    # PowerDNS ---------------------------------------------------------------

    def powerdns(self, path):
        if path in ("/api/v1/servers", "/api/v1/servers/"):
            return self.reply(200, [{"id": "localhost", "url": "/api/v1/servers/localhost", "version": "4.8.0"}])
        if path == "/api/v1/servers/localhost":
            return self.reply(200, {"id": "localhost", "url": "/api/v1/servers/localhost", "version": "4.8.0"})
        m = re.fullmatch(r"/api/v1/servers/localhost/zones/([^/]+)", path)
        if not m:
            sys.stderr.write("mock: unhandled %s %s\n" % (self.command, self.path))
            return self.reply(404, {"error": "not found"})
        zone = m.group(1)
        rrsets = zones.setdefault(zone, {})
        if self.command == "GET":
            return self.reply(200, {"id": zone, "name": zone, "kind": "Native", "rrsets": list(rrsets.values())})
        if self.command == "PATCH":
            for rr in self.read_json().get("rrsets", []):
                key = (rr["name"], rr["type"])
                if rr.get("changetype") == "DELETE":
                    rrsets.pop(key, None)
                else:
                    rrsets[key] = {k: rr[k] for k in ("name", "type", "ttl", "records") if k in rr}
                    rrsets[key].setdefault("comments", [])
            return self.reply(204)
        return self.reply(405, {"error": "method not allowed"})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
