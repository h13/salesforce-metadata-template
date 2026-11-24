# JWT Bearer Flow 認証セットアップ手順

> **English version**: [jwt-auth-setup.md](jwt-auth-setup.md)

CI/CD から Salesforce org にデプロイするための JWT Bearer Flow の設定手順。

## 概要

```
GitHub Actions → JWT で認証（CI 専用ユーザーとして） → Salesforce org にデプロイ
```

必要なもの:

- Salesforce org の管理者アクセス
- OpenSSL（鍵生成用）
- GitHub リポジトリの Settings アクセス

## 1. 秘密鍵と証明書の生成

ローカルで実行:

```bash
mkdir -p ~/.config/salesforce-ci && cd ~/.config/salesforce-ci

# 秘密鍵を生成
openssl genrsa -out server.key 2048 && chmod 600 server.key

# 証明書を生成（有効期限 365 日）
openssl req -new -x509 -key server.key -out server.crt -days 365 \
  -subj "/CN=salesforce-ci/O=YourCompany"
```

`server.key` が CI で使う秘密鍵、`server.crt` が Salesforce に登録する証明書。リポジトリ配下には置かないこと。

## 2. CI 専用ユーザーの作成

デプロイは個人アカウントではなく専用のインテグレーションユーザーで実行します（担当者の異動・退職やパスワードポリシーの影響を受けないため）。Salesforce には「ユーザーに紐づかないサービスプリンシパル」が存在しないため、これが Salesforce 流のサービスアカウントです。

管理者で認証済みの sf CLI から作成できます:

```bash
# システム管理者プロファイルの ID を取得
pnpm exec sf data query --target-org sandbox \
  --query "SELECT Id FROM Profile WHERE Name = 'システム管理者'"

# CI ユーザーを作成（ProfileId は上の結果に置き換える）
pnpm exec sf data create record --target-org sandbox --sobject User --values \
  "Username='github-ci@company.com.sandboxname' LastName='GitHub CI' Alias='ghci' Email='<管理者のメール>' TimeZoneSidKey='Asia/Tokyo' LocaleSidKey='ja_JP' EmailEncodingKey='UTF-8' LanguageLocaleKey='ja' ProfileId='<ProfileId>'"
```

パスワードは設定しません。パスワードログイン不可のまま、認証は JWT 証明書のみで行います。

> **ライセンスの補足**: 無償の「Salesforce Integration」ライセンス（API 専用）は、メタデータデプロイに必要な権限の組み合わせが難しい（型ごとの個別権限に加え、一部の型は Modify All Data が必須）ため、フルライセンス + システム管理者プロファイルを推奨します。

## 3. Salesforce で外部クライアントアプリケーションを作成

> **注意**: 2025 年以降の org では、新規「接続アプリケーション」の作成がデフォルトで無効化されています
> （Metadata API 経由でも「接続アプリケーションを作成できません」エラーになる）。
> 後継の**外部クライアントアプリケーション (External Client App)** を使います。JWT Bearer Flow を公式サポートしており、`sf org login jwt` もそのまま使えます。
> アプリケーションの設定はこのリポジトリに含まれず org 上で手動管理するため、変更時はこのドキュメントを更新して Git 上で履歴を残してください。

### Sandbox org で設定

1. **設定** → クイック検索で「アプリ」と入力 → **アプリケーションマネージャ**
2. **新規アプリケーション ▼** → **新規外部クライアントアプリケーション**
3. 基本情報:
   - 外部クライアントアプリケーション名: `CI Deploy` / API 参照名: `CI_Deploy`
   - 取引先責任者メール: 管理者のメール / 配布状態: **ローカル**
4. **OAuth 設定の有効化** にチェック:
   - コールバック URL: `https://login.salesforce.com/services/oauth2/callback`（JWT フローでは未使用だが入力必須）
   - OAuth 範囲: `api` / `web` / `refresh_token, offline_access`
   - **JWT ベアラーフローを有効化** にチェック → `server.crt` をアップロード
     （macOS のファイルダイアログで `~/.config` が見えないときは Cmd+Shift+. で隠しファイルを表示）
5. **保存**

### アクセスポリシーの設定

1. 作成したアプリの **ポリシー** タブ → **編集**
2. アプリケーションポリシーの **プロファイルを選択** で「システム管理者」を選択済みに移動
3. OAuth ポリシーの **許可されているユーザー** を **管理者が承認したユーザーは事前承認済み** に変更
4. **保存**

### コンシューマーキーを取得

1. **設定** タブ → **OAuth 設定** → コンシューマーキーと秘密を表示（本人確認を求められる場合あり）
2. **コンシューマーキー** をコピー（これが `SF_CLIENT_ID`。コンシューマーの秘密は JWT フローでは使いません）

## 4. Production org でも同じ手順を実行

Production org にも同じ CI ユーザー（`github-ci@company.com`）と外部クライアントアプリケーションを作成する。同じ `server.crt` を使えば、同じ秘密鍵で両方の org に認証できる。

## 5. GitHub Environment の設定

秘密にすべきは秘密鍵だけで、残りは非秘密の設定値なので environment **variables** に置き、UI から見える状態を保つ。
リポジトリの **Settings** → **Environments** で環境を作成して登録する。gh CLI なら:

```bash
gh api -X PUT repos/OWNER/REPO/environments/sandbox > /dev/null
gh secret set SF_JWT_KEY --env sandbox < ~/.config/salesforce-ci/server.key
gh variable set SF_CLIENT_ID --env sandbox --body '<コンシューマーキー>'
gh variable set SF_USERNAME --env sandbox --body 'github-ci@company.com.sandboxname'
gh variable set SF_INSTANCE_URL --env sandbox --body 'https://mycompany--dev.sandbox.my.salesforce.com'
```

### `sandbox` 環境

| 種別     | 名前              | 値                                                 |
| -------- | ----------------- | -------------------------------------------------- |
| Secret   | `SF_JWT_KEY`      | `server.key` の中身（PEM テキスト全体）            |
| Variable | `SF_CLIENT_ID`    | 外部クライアントアプリのコンシューマーキー         |
| Variable | `SF_USERNAME`     | `github-ci@company.com.sandboxname`                |
| Variable | `SF_INSTANCE_URL` | `https://mycompany--dev.sandbox.my.salesforce.com` |

### `production` 環境

| 種別     | 名前              | 値                                      |
| -------- | ----------------- | --------------------------------------- |
| Secret   | `SF_JWT_KEY`      | 同じ `server.key` の中身                |
| Variable | `SF_CLIENT_ID`    | Production 側アプリのコンシューマーキー |
| Variable | `SF_USERNAME`     | `github-ci@company.com`                 |
| Variable | `SF_INSTANCE_URL` | `https://mycompany.my.salesforce.com`   |

PR の validate ジョブも `sandbox` environment を参照する（ci.yml の `environment: sandbox`）ため、リポジトリレベルへの複製は不要。

## 6. ローカルでの認証テスト

```bash
pnpm exec sf org login jwt \
  --client-id <コンシューマーキー> \
  --jwt-key-file ~/.config/salesforce-ci/server.key \
  --username github-ci@company.com.sandboxname \
  --instance-url https://mycompany--dev.sandbox.my.salesforce.com \
  --alias ci-sandbox
```

成功すると以下が表示される:

```
Successfully authorized github-ci@company.com.sandboxname with org ID 00D...
```

## 7. 動作確認

```bash
# CI ユーザーで Sandbox にデプロイテスト
pnpm exec sf project deploy start --dry-run --target-org ci-sandbox --wait 30
```

## トラブルシューティング

### 「接続アプリケーションを作成できません。…カスタマーサポートにお問い合わせください」

新しい org では接続アプリケーションの新規作成が無効化されている。本ドキュメントの手順どおり、外部クライアントアプリケーションで作成する。

### `INVALID_LOGIN: Invalid login credentials`

- アプリのアクセスポリシーでユーザーのプロファイルが事前承認されているか確認
- コンシューマーキーが正しいか確認
- ユーザー名が正しいか確認（Sandbox は `.sandboxname` サフィックスが必要）

### `JWT_INVALID_GRANT: user hasn't approved this consumer`

- 「管理者が承認したユーザーは事前承認済み」に設定されているか確認
- プロファイルが選択済みに追加されているか確認

### `INVALID_CLIENT_ID`

- アプリ作成後、反映まで最大10分かかる場合がある
- コンシューマーキーをコピーし直す

### 証明書の有効期限切れ

```bash
# 新しい証明書を生成（秘密鍵はそのまま）
openssl req -new -x509 -key ~/.config/salesforce-ci/server.key \
  -out ~/.config/salesforce-ci/server.crt -days 365 \
  -subj "/CN=salesforce-ci/O=YourCompany"

# 外部クライアントアプリの JWT ベアラーフロー設定で証明書を差し替え
```

秘密鍵（`server.key`）はそのまま使えるので、GitHub Secrets の更新は不要。

## セキュリティ注意事項

- `server.key` はリポジトリにコミットしない（リポジトリ外の `~/.config/salesforce-ci/` 等に置く）
- GitHub Secrets に登録したらローカルの `server.key` は安全に削除してよい（証明書を再発行する予定があるなら保管場所に注意して保持）
- 証明書の有効期限をカレンダーに登録しておく
- Production 環境には **Required reviewers** と **Deployment branch policy（main のみ）** を設定し、手動承認を挟むことを推奨
