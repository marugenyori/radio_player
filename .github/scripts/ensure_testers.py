"""TestFlight の内部テストのグループがなければ作り、App Store Connect のユーザーをテスターに入れる。"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

from cleanup_dev_certs import API, call, token

GROUP_NAME = "自分"


def post(url: str, auth: str, body: dict):
    req = urllib.request.Request(
        url,
        method="POST",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {auth}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as res:
        data = res.read()
        return json.loads(data) if data else None


def main() -> int:
    auth = token()
    q = urllib.parse.quote(os.environ["BUNDLE_ID"])
    app = call("GET", f"{API}/apps?filter[bundleId]={q}", auth)["data"][0]

    groups = call("GET", f"{API}/apps/{app['id']}/betaGroups", auth)["data"]
    internal = [g for g in groups if g["attributes"].get("isInternalGroup")]
    if internal:
        group = internal[0]
        print(f"内部テストのグループ「{group['attributes']['name']}」があります")
    else:
        group = post(f"{API}/betaGroups", auth, {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}},
            }
        })["data"]
        print(f"内部テストのグループ「{GROUP_NAME}」を作りました（新しいビルドは自動で配られます）")

    existing = {
        (t["attributes"].get("email") or "").lower()
        for t in call("GET", f"{API}/betaGroups/{group['id']}/betaTesters?limit=200", auth)["data"]
    }
    for user in call("GET", f"{API}/users?limit=200", auth)["data"]:
        a = user["attributes"]
        email = a.get("username") or a.get("email") or ""
        if not email or email.lower() in existing:
            continue
        try:
            post(f"{API}/betaTesters", auth, {
                "data": {
                    "type": "betaTesters",
                    "attributes": {"email": email, "firstName": a.get("firstName"), "lastName": a.get("lastName")},
                    "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}},
                }
            })
            print(f"テスターに追加しました：{a.get('lastName', '')}{a.get('firstName', '')}")
        except urllib.error.HTTPError as e:
            print(f"テスターに追加できませんでした（{e.code}）：{e.read().decode(errors='replace')[:300]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
