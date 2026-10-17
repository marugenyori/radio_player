"""App Store Connect の状況（ビルドの処理状況、TestFlight のテスター）を表示する。"""
import os
import sys
import urllib.parse

from cleanup_dev_certs import API, call, token

STATES = {
    "PROCESSING": "処理中",
    "VALID": "処理完了（使える）",
    "INVALID": "無効（エラー）",
    "FAILED": "失敗",
}


def main() -> int:
    auth = token()
    q = urllib.parse.quote(os.environ["BUNDLE_ID"])
    apps = call("GET", f"{API}/apps?filter[bundleId]={q}", auth)["data"]
    if not apps:
        print("App Store Connect にアプリが見つかりません")
        return 1
    app = apps[0]
    print(f"アプリ：{app['attributes']['name']}（{app['attributes']['bundleId']}）")

    builds = call("GET", f"{API}/builds?filter[app]={app['id']}&sort=-uploadedDate&limit=5", auth)["data"]
    print("\n■ ビルド（新しい順）")
    if not builds:
        print("  まだ届いていません（アップロード直後は数分かかります）")
    for b in builds:
        a = b["attributes"]
        state = STATES.get(a.get("processingState"), a.get("processingState"))
        print(f"  ビルド {a['version']}：{state}　アップロード {a.get('uploadedDate', '')[:16]}　期限 {str(a.get('expirationDate', ''))[:10]}")

    groups = call("GET", f"{API}/apps/{app['id']}/betaGroups", auth)["data"]
    print("\n■ TestFlight のグループ")
    if not groups:
        print("  まだありません（内部テストのグループを作る必要があります）")
    for g in groups:
        kind = "内部" if g["attributes"].get("isInternalGroup") else "外部"
        testers = call("GET", f"{API}/betaGroups/{g['id']}/betaTesters", auth)["data"]
        names = "、".join(
            f"{t['attributes'].get('lastName') or ''}{t['attributes'].get('firstName') or ''}".strip()
            or "（名前なし）" for t in testers
        ) or "テスターなし"
        print(f"  {g['attributes']['name']}（{kind}）：{names}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
