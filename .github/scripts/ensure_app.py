"""App ID（Bundle ID）がなければ作り、App Store Connect にアプリがなければ作る。

- App ID は API で作れるので、ここで自動で登録する
- App Store Connect の「アプリ」は API で作れない場合がある。そのときは作り方を表示して止める
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

from cleanup_dev_certs import API, call, token

APP_NAME = "金曜・最高ラジオ"


def post(url: str, auth: str, body: dict):
    req = urllib.request.Request(
        url,
        method="POST",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {auth}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.loads(res.read())


def main() -> int:
    bundle_id = os.environ["BUNDLE_ID"]
    auth = token()
    q = urllib.parse.quote(bundle_id)

    ids = call("GET", f"{API}/bundleIds?filter[identifier]={q}&limit=200", auth)["data"]
    found = [b for b in ids if b["attributes"]["identifier"] == bundle_id]
    if found:
        resource_id = found[0]["id"]
        print(f"App ID {bundle_id} は登録済みです")
    else:
        resource_id = post(f"{API}/bundleIds", auth, {
            "data": {
                "type": "bundleIds",
                "attributes": {"identifier": bundle_id, "name": "RadioPlayer", "platform": "IOS"},
            }
        })["data"]["id"]
        print(f"App ID {bundle_id} を登録しました")

    apps = call("GET", f"{API}/apps?filter[bundleId]={q}", auth)["data"]
    if apps:
        print(f"App Store Connect のアプリ「{apps[0]['attributes']['name']}」が見つかりました")
        return 0

    try:
        post(f"{API}/apps", auth, {
            "data": {
                "type": "apps",
                "attributes": {"name": APP_NAME, "primaryLocale": "ja", "sku": "radioplayer", "bundleId": bundle_id},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": resource_id}}},
            }
        })
        print(f"App Store Connect にアプリ「{APP_NAME}」を作りました")
        return 0
    except urllib.error.HTTPError as e:
        print(f"API でのアプリ作成はできませんでした（{e.code}）：{e.read().decode(errors='replace')[:500]}")

    print(f"::error::App Store Connect にアプリがありません。「アプリ」→「＋」→「新規App」で、"
          f"名前「{APP_NAME}」、バンドル ID「{bundle_id}」のアプリを作ってから、もう一度実行してください。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
