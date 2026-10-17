# 金曜・最高ラジオ

自分で保存した「セブ山・永田の金曜ラジオ」「最高ラジオ」の MP3 を聴くための、個人用 iPhone アプリです。

## 最初にやること（持ち主の作業）

### 1. Secrets を登録する
GitHub のこのリポジトリで「Settings」→「Secrets and variables」→「Actions」→「New repository secret」を押し、次の4つを登録します（値は claud_code に登録したものと同じです）。

- `APPLE_TEAM_ID`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_P8`（`.p8` ファイルの中身を、`-----BEGIN PRIVATE KEY-----` の行から最後の行まで全部）

Bundle ID を `com.marugenyori.radioplayer` 以外にしたいときだけ、`BUNDLE_ID` も登録します。

### 2. Apple Developer で App ID を登録する
1. https://developer.apple.com/account →「Certificates, IDs & Profiles」→「Identifiers」→「＋」
2. 「App IDs」→「Continue」→「App」→「Continue」
3. 「Description」に `RadioPlayer`、「Bundle ID」は「Explicit」で `com.marugenyori.radioplayer`
4. 「Capabilities」は何もチェックしないで「Continue」→「Register」

### 3. App Store Connect にアプリを登録する
1. https://appstoreconnect.apple.com →「アプリ」→「＋」→「新規App」
2. プラットフォーム「iOS」、名前「金曜・最高ラジオ」、言語「日本語」、バンドル ID は手順2のもの、SKU は `radioplayer`、ユーザアクセス「アクセス制限なし」→「作成」

### 4. TestFlight に出す
「Actions」→「iOS Build」→「Run workflow」→「TestFlight にアップロードする」にチェック →「Run workflow」。
終わってから 10〜30分ほどで、iPhone の TestFlight アプリに出てきます。

## 音声ファイルの入れ方

- **PC から直接**：Windows の「Apple Devices」アプリで iPhone を開き、「ファイル」→「金曜・最高ラジオ」に `kinyo_radio_mp3` と `saikou_radio_mp3` をドラッグ
- **iCloud Drive から**：2つのフォルダを iCloud Drive に入れ、アプリの設定（左上の歯車）→「フォルダを選ぶ」で、2つが入っている親フォルダを選ぶ
