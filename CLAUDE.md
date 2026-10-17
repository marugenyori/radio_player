# このリポジトリについて（Claude 向けの作業メモ）

「金曜・最高ラジオ」：オモコロのポッドキャスト「セブ山・永田の金曜ラジオ」「最高ラジオ」を、
ユーザーが自分で保存した MP3 で聴くための個人用 iPhone アプリ（SwiftUI）。App Store には出さず TestFlight で使う。
最初の依頼内容と仕様は `HANDOFF.md` にある。

持ち主は Mac を持っておらず、Windows PC（ARM）と iPhone から作業する。ビルドの確認も配信も GitHub Actions（macOS ランナー）で行う。

## 返答のしかた

- **日本語**で、専門用語には短い説明を添える
- 持ち主が自分で操作する手順は、画面の項目名どおりに番号付きで書く。ターミナル操作は PowerShell 向けに
- パスワード・API キー・`.p8` の中身はチャットに貼ってもらわない

## 構成

| パス | 内容 |
|---|---|
| `project.yml` | XcodeGen の設定。`.xcodeproj` はリポジトリに入れず、CI で `xcodegen generate` して作る |
| `RadioPlayer/App` | アプリの入口と、一番外側の画面 |
| `RadioPlayer/Models` | 番組と回（`Episode`）、タイトル一覧（`EpisodeCatalog`）、ファイル探し（`AudioLibrary`）、聴取状況（`ListeningStore`）、再生（`AudioPlayer`） |
| `RadioPlayer/Views` | 一覧・再生画面・下の再生バー・設定 |
| `episodes.json` | 回番号とタイトルの一覧（リポジトリ直下。アプリに同梱される。ないときは CI が空の一覧を作ってビルドする） |
| `tools/make_icon.py` | アプリアイコン（1024px）を作るスクリプト |
| `.github/workflows/ios-build.yml` | ビルド確認と TestFlight 配信 |

- iOS 17 以上、iPhone 縦画面のみ、Swift 5 モード、外部ライブラリなし
- 保存は `UserDefaults`（聴取状況は `listeningStates` キーに JSON でまとめて保存）

## ビルドと配信

- `main` に push すると署名なしのシミュレータ向けビルドが走る（エラーは実行結果ページの「ビルド結果」にまとまる）
- TestFlight：Actions → iOS Build → Run workflow →「TestFlight にアップロードする」にチェック
- Secrets：`APPLE_TEAM_ID`、`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`（`marugenyori/claud_code` と同じ値）。`BUNDLE_ID` は任意（なければ `com.marugenyori.radioplayer`）
- Bundle ID はビルド設定 `APP_BUNDLE_ID` で渡す。`PRODUCT_BUNDLE_IDENTIFIER` をコマンドラインで上書きしない
- App ID は `.github/scripts/ensure_app.py` が API で自動登録する。App Store Connect のアプリは API で作れないので、持ち主に作ってもらう
- CI は毎回まっさらなマシンで自動署名するので、開発用証明書が増える。`.github/scripts/cleanup_dev_certs.py` でアーカイブ前に消している

## 音声ファイルの決まり

- 探す場所：アプリの「書類」フォルダ（PC の Apple Devices アプリから入れる）と、設定で選んだ iCloud Drive のフォルダ（security-scoped bookmark で覚える）。サブフォルダも探す
- パスに `saikou` か「最高」があれば最高ラジオ、それ以外は金曜ラジオ
- ファイル名の先頭の数字が回番号。数字で始まらないファイルは無視
- 「120 タイトル.mp3」のように区切りのあとに文字があれば、一覧のタイトルが空のときに使う
- iCloud の未ダウンロードのファイル（`.001.mp3.icloud`）も一覧に出し、再生時に `NSFileCoordinator` でダウンロードを待つ
- 音声ファイルと `.p8` はリポジトリに入れない（`.gitignore` 済み）
