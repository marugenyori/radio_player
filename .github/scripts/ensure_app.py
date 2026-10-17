"""App ID（Bundle ID）がなければ作り、App Store Connect にアプリがあるか確かめる。

- App ID は API で作れるので、ここで自動で登録する
- App Store Connect の「アプリ」は API では作れないので、なければ作り方を表示して止める
"""
import json
import os
import sys
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
    if any(b["attributes"]["identifier"] == bundle_id for b in ids):
        print(f"App ID {bundle_id} は登録済みです")
    else:
        post(f"{API}/bundleIds", auth, {
            "data": {
                "type": "bundleIds",
                "attributes": {"identifier": bundle_id, "name": "RadioPlayer", "platform": "IOS"},
            }
        })
        print(f"App ID {bundle_id} を登録しました")

    apps = call("GET", f"{API}/apps?filter[bundleId]={q}", auth)["data"]
    if apps:
        print(f"App Store Connect のアプリ「{apps[0]['attributes']['name']}」が見つかりました")
        return 0

    print(f"::error::App Store Connect にアプリがありません。「アプリ」→「＋」→「新規App」で、"
          f"名前「{APP_NAME}」、バンドル ID「{bundle_id}」のアプリを作ってから、もう一度実行してください。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
