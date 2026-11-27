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

鍵ペアは信頼の階層ごとに1本ずつ作る — 本番用と、全 sandbox 共用の2本。sandbox 用の鍵では本番が受け入れるトークンに署名できないため、保護ルールのない sandbox environment が本番に効く鍵を持つことがなくなる。

```bash
mkdir -p ~/.config/salesforce-ci && cd ~/.config/salesforce-ci

# 本番用の鍵ペア
openssl genrsa -out production.key 2048 && chmod 600 production.key
openssl req -new -x509 -key production.key -out production.crt -days 365 \
  -subj "/CN=salesforce-ci/O=YourCompany"

# sandbox 用の鍵ペア
openssl genrsa -out sandbox.key 2048 && chmod 600 sandbox.key
openssl req -new -x509 -key sandbox.key -out sandbox.crt -days 365 \
  -subj "/CN=salesforce-ci-sandbox/O=YourCompany"
```

`.key` が CI で使う秘密鍵、`.crt` が Salesforce に登録する証明書。いずれもリポジトリ配下には置かないこと。

## 2. CI 専用ユーザーの作成

デプロイは個人アカウントではなく専用のインテグレーションユーザーで実行します（担当者の異動・退職やパスワードポリシーの影響を受けないため）。Salesforce には「ユーザーに紐づかないサービスプリンシパル」が存在しないため、これが Salesforce 流のサービスアカウントです。

管理者で認証済みの sf CLI から作成できます:

```bash
# システム管理者プロファイルの ID を取得
pnpm exec sf data query --target-org production \
  --query "SELECT Id FROM Profile WHERE Name = 'システム管理者'"

# CI ユーザーを作成（ProfileId は上の結果に置き換える）
pnpm exec sf data create record --target-org production --sobject User --values \
  "Username='github-ci@company.com' LastName='GitHub CI' Alias='ghci' Email='<管理者のメール>' TimeZoneSidKey='Asia/Tokyo' LocaleSidKey='ja_JP' EmailEncodingKey='UTF-8' LanguageLocaleKey='ja' ProfileId='<ProfileId>'"
```

パスワードは設定しません。パスワードログイン不可のまま、認証は JWT 証明書のみで行います。

> **ライセンスの補足**: 無償の「Salesforce Integration」ライセンス（API 専用）は、メタデータデプロイに必要な権限の組み合わせが難しい（型ごとの個別権限に加え、一部の型は Modify All Data が必須）ため、フルライセンス + システム管理者プロファイルを推奨します。

## 3. Salesforce で外部クライアントアプリケーションを作成

> **注意**: 2025 年以降の org では、新規「接続アプリケーション」の作成がデフォルトで無効化されています
> （Metadata API 経由でも「接続アプリケーションを作成できません」エラーになる）。
> 後継の**外部クライアントアプリケーション (External Client App)** を使います。JWT Bearer Flow を公式サポートしており、`sf org login jwt` もそのまま使えます。
> アプリケーションの設定はこのリポジトリに含まれず org 上で手動管理するため、変更時はこのドキュメントを更新して Git 上で履歴を残してください。

### Production org で設定

1. **設定** → クイック検索で「アプリ」と入力 → **アプリケーションマネージャ**
2. **新規アプリケーション ▼** → **新規外部クライアントアプリケーション**
3. 基本情報:
   - 外部クライアントアプリケーション名: `CI Deploy` / API 参照名: `CI_Deploy`
   - 取引先責任者メール: 管理者のメール / 配布状態: **ローカル**
4. **OAuth 設定の有効化** にチェック:
   - コールバック URL: `https://login.salesforce.com/services/oauth2/callback`（JWT フローでは未使用だが入力必須）
   - OAuth 範囲: `api` / `web` / `refresh_token, offline_access`
   - **JWT ベアラーフローを有効化** にチェック → `production.crt` をアップロード
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

## 4. Sandbox へはリフレッシュで複製される

作成は Production で一度だけ行い、各 sandbox へはリフレッシュで複製される。外部クライアントアプリケーションは**同じコンシューマーキー**のまま複製され、CI ユーザーは username に `.{sandbox名}` が付いて複製される。リフレッシュでメールアドレスに `.invalid` が付くが、メールを受信しない CI ユーザーには実害がない。

複製されるのは**本番の証明書**なので、リフレッシュ後に sandbox 側アプリの証明書を `sandbox.crt` に差し替える。差し替えるまで、その sandbox への CI 認証は明示的なエラーで失敗する（別の org に向かうことはない）。リフレッシュを待てない sandbox には、同じアプリ（証明書は `sandbox.crt`）とユーザーを手動で作成する。

## 5. GitHub の設定

秘密にすべきは秘密鍵だけ。全 org 共通の値は repository **variables** に置き、各 environment が持つのは自分の階層の鍵と（sandbox なら）`SANDBOX_ID` だけ。username（`SF_CI_USERNAME` + `.SANDBOX_ID`）と instance URL（`SF_MY_DOMAIN` / `SANDBOX_ID` から）はワークフロー側で導出するため、環境追加時の登録はこの2つで済む。

```bash
# Repository variables（全環境共通）
gh variable set SF_MY_DOMAIN --body 'mycompany'
gh variable set SF_CI_USERNAME --body 'github-ci@company.com'
gh variable set SF_CLIENT_ID --body '<コンシューマーキー>'

# 環境ごと
gh api -X PUT repos/OWNER/REPO/environments/sandbox > /dev/null
gh secret set SF_JWT_KEY --env sandbox < ~/.config/salesforce-ci/sandbox.key
gh variable set SANDBOX_ID --env sandbox --body '<sandbox名>'

gh api -X PUT repos/OWNER/REPO/environments/production > /dev/null
gh secret set SF_JWT_KEY --env production < ~/.config/salesforce-ci/production.key
```

### Repository variables

| 名前             | 値                                                         |
| ---------------- | ---------------------------------------------------------- |
| `SF_MY_DOMAIN`   | My Domain 名（`https://<SF_MY_DOMAIN>.my.salesforce.com`） |
| `SF_CI_USERNAME` | `github-ci@company.com`                                    |
| `SF_CLIENT_ID`   | 外部クライアントアプリのコンシューマーキー                 |

### 各 environment

| 種別     | 名前         | 値                                                                           |
| -------- | ------------ | ---------------------------------------------------------------------------- |
| Secret   | `SF_JWT_KEY` | 階層ごとの鍵: sandbox 環境は `sandbox.key`、`production` は `production.key` |
| Variable | `SANDBOX_ID` | sandbox 名（`production` には**登録しない**）                                |

各 environment は**自分の階層の鍵だけ**を持つ。sandbox 鍵では本番が受け入れるトークンに署名できない（本番が信頼するのは `production.crt` だけ）ため、保護ルールのない sandbox environment の中身では `production` environment の required reviewers を素通りできない。鍵は repository secret にせず environment secret に置くこと — repository secret はどのブランチのワークフローからも読めてしまう。

PR の validate ジョブも `sandbox` environment を参照する（ci.yml の `environment: sandbox`）ため、鍵のリポジトリレベルへの複製は不要。

## 6. ローカルでの認証テスト

```bash
pnpm exec sf org login jwt \
  --client-id <コンシューマーキー> \
  --jwt-key-file ~/.config/salesforce-ci/sandbox.key \
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
openssl req -new -x509 -key ~/.config/salesforce-ci/production.key \
  -out ~/.config/salesforce-ci/production.crt -days 365 \
  -subj "/CN=salesforce-ci/O=YourCompany"

# 外部クライアントアプリの JWT ベアラーフロー設定で証明書を差し替え
```

秘密鍵はそのまま使えるので、GitHub Secrets の更新は不要（証明書の再発行は鍵ペアごとに行う）。

## セキュリティ注意事項

- 秘密鍵はリポジトリにコミットしない（リポジトリ外の `~/.config/salesforce-ci/` 等に置く）
- GitHub Secrets に登録したらローカルの秘密鍵は安全に削除してよい（証明書を再発行する予定があるなら保管場所に注意して保持）
- 証明書の有効期限をカレンダーに登録しておく
- Production 環境には **Required reviewers** と **Deployment branch policy（main のみ）** を設定し、手動承認を挟むことを推奨
