import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request


GRAFANA_URL = os.environ.get("GRAFANA_URL", "http://grafana:3000")
ADMIN_USER = os.environ.get("GRAFANA_ADMIN_USER", "admin")
ADMIN_PASSWORD = os.environ.get("GRAFANA_ADMIN_PASSWORD", "admin")
TEMPO_URL = os.environ.get("GRAFANA_TEMPO_URL", "http://tempo:3200")
TEMPO_TENANT = os.environ.get("TEMPO_TENANT_ID", "shared-trace")

ORG_DEFINITIONS = [
    {
        "name": "Frontend Org",
        "user": {
            "login": "frontend-user",
            "name": "Frontend User",
            "email": "frontend@example.local",
            "password": "frontend-pass",
        },
        "datasource_uid": "tempo-frontend-org",
    },
    {
        "name": "Backend Org",
        "user": {
            "login": "backend-user",
            "name": "Backend User",
            "email": "backend@example.local",
            "password": "backend-pass",
        },
        "datasource_uid": "tempo-backend-org",
    },
]


def admin_headers(extra=None):
    token = base64.b64encode(f"{ADMIN_USER}:{ADMIN_PASSWORD}".encode()).decode()
    headers = {
        "Authorization": f"Basic {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if extra:
        headers.update(extra)
    return headers


def request(method, path, payload=None, headers=None):
    url = f"{GRAFANA_URL}{path}"
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, method=method, headers=headers or admin_headers())
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            content = response.read().decode()
            return response.status, json.loads(content) if content else {}
    except urllib.error.HTTPError as error:
        content = error.read().decode()
        data = {}
        if content:
            try:
                data = json.loads(content)
            except json.JSONDecodeError:
                data = {"message": content}
        return error.code, data


def wait_for_grafana():
    for _ in range(60):
        try:
            status, _ = request("GET", "/api/health")
            if status == 200:
                return
        except urllib.error.URLError:
            pass
        time.sleep(2)
    raise RuntimeError("Grafana did not become ready in time")


def get_or_create_org(name):
    encoded = urllib.parse.quote(name, safe="")
    status, body = request("GET", f"/api/orgs/name/{encoded}")
    if status == 200:
        return body["id"]
    status, body = request("POST", "/api/orgs", {"name": name})
    if status == 200:
        return int(body["orgId"])
    raise RuntimeError(f"Failed to create org {name}: {body}")


def get_or_create_user(user):
    query = urllib.parse.quote(user["login"], safe="")
    status, body = request("GET", f"/api/users/lookup?loginOrEmail={query}")
    if status == 200:
        return body["id"]
    payload = {
        "name": user["name"],
        "email": user["email"],
        "login": user["login"],
        "password": user["password"],
    }
    status, body = request("POST", "/api/admin/users", payload)
    if status == 200:
        return body["id"]
    raise RuntimeError(f"Failed to create user {user['login']}: {body}")


def ensure_user_in_org(org_id, user):
    status, body = request("GET", f"/api/orgs/{org_id}/users")
    if status != 200:
        raise RuntimeError(f"Failed to list org users for org {org_id}: {body}")
    for member in body:
        if member["login"] == user["login"]:
            if member["role"] != "Editor":
                status, update_body = request(
                    "PATCH",
                    f"/api/orgs/{org_id}/users/{member['userId']}",
                    {"role": "Editor"},
                )
                if status != 200:
                    raise RuntimeError(
                        f"Failed to update {user['login']} role in org {org_id}: {update_body}"
                    )
            return
    status, body = request(
        "POST",
        f"/api/orgs/{org_id}/users",
        {"loginOrEmail": user["login"], "role": "Editor"},
    )
    if status != 200:
        raise RuntimeError(f"Failed to add {user['login']} to org {org_id}: {body}")


def switch_user_org(user_id, org_id):
    status, body = request("POST", f"/api/users/{user_id}/using/{org_id}")
    if status not in (200, 409):
        raise RuntimeError(f"Failed to switch user {user_id} to org {org_id}: {body}")


def remove_user_from_main_org_if_needed(user_id, org_id):
    if org_id == 1:
        return
    status, body = request("GET", "/api/orgs/1/users")
    if status != 200:
        raise RuntimeError(f"Failed to list Main Org users: {body}")
    member = next((item for item in body if item["userId"] == user_id), None)
    if not member:
        return
    status, body = request("DELETE", f"/api/orgs/1/users/{user_id}")
    if status != 200:
        raise RuntimeError(f"Failed to remove user {user_id} from Main Org: {body}")


def create_or_update_datasource(org_id, uid, name):
    headers = admin_headers({"X-Grafana-Org-Id": str(org_id)})
    status, body = request("GET", f"/api/datasources/uid/{uid}", headers=headers)
    payload = {
        "uid": uid,
        "name": name,
        "type": "tempo",
        "access": "proxy",
        "url": TEMPO_URL,
        "isDefault": True,
        "jsonData": {
            "httpHeaderName1": "X-Scope-OrgID",
        },
        "secureJsonData": {
            "httpHeaderValue1": TEMPO_TENANT,
        },
    }
    if status == 200:
        payload["id"] = body["id"]
        payload["orgId"] = org_id
        status, body = request("PUT", f"/api/datasources/uid/{uid}", payload, headers=headers)
        if status == 200:
            return
        raise RuntimeError(f"Failed to update datasource {uid}: {body}")
    status, body = request("POST", "/api/datasources", payload, headers=headers)
    if status == 200:
        return
    raise RuntimeError(f"Failed to create datasource {uid}: {body}")


def main():
    wait_for_grafana()
    for definition in ORG_DEFINITIONS:
        org_id = get_or_create_org(definition["name"])
        user_id = get_or_create_user(definition["user"])
        ensure_user_in_org(org_id, definition["user"])
        switch_user_org(user_id, org_id)
        remove_user_from_main_org_if_needed(user_id, org_id)
        create_or_update_datasource(org_id, definition["datasource_uid"], "Tempo Shared")
        print(f"Configured org '{definition['name']}' with user '{definition['user']['login']}'")


if __name__ == "__main__":
    main()
