# Salesforce Metadata Template

[![CI](https://github.com/h13/salesforce-metadata-template/actions/workflows/ci.yml/badge.svg)](https://github.com/h13/salesforce-metadata-template/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/h13/salesforce-metadata-template/blob/main/LICENSE)
[![Node.js](https://img.shields.io/badge/Node.js-26-green.svg)](https://nodejs.org/)
[![Java](https://img.shields.io/badge/Java-Temurin%2025-ED8B00.svg)](https://adoptium.net/)
[![Salesforce](https://img.shields.io/badge/Salesforce-CLI-00A1E0.svg)](https://developer.salesforce.com/tools/salesforcecli)

[English](README.md)

**Salesforce メタデータを Git + CI/CD で管理するためのテンプレートリポジトリ。**

GUI 操作（org から retrieve）と AI Agent による直接編集の両方に対応。`sandbox` ブランチへの push で Sandbox にデプロイ、`main` への push で Production にデプロイ。

**[→ クイックスタート](#クイックスタート)** · [デプロイ戦略](#デプロイ戦略) · [ドキュメント](#ドキュメント)

## 課題

Salesforce org には宣言的カスタマイズ（フロー、オブジェクト、権限セット、レイアウト）が蓄積されます。すべて GUI で構築され、バージョン履歴はありません。何かが壊れても、差分の確認、ロールバック、レビューができません。AI Agent もバリデーションゲートなしでは安全に貢献できません。

## 解決策

すべてのメタデータを Git に取り込む。CI で人間と AI の両方の変更を org に反映する前に検証する。

```text
GUI 変更      → sf retrieve → Git → PR → CI validate → merge → deploy
AI Agent 編集 → Git に直接   → PR → CI validate → merge → deploy
```

どちらのパスも同じ `force-app/` ディレクトリと同じ CI パイプラインに合流します。

## クイックスタート

### 前提条件

- [mise](https://mise.jdx.dev/)（Node.js と Java のバージョン管理。Java は code analyzer の PMD エンジンに必要）
- [pnpm](https://pnpm.io/)

[Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) は devDependency として同梱されているため、グローバルインストールは不要。`pnpm install` 後に `pnpm exec sf ...` で実行する。

### セットアップ

```bash
mise trust
mise install
pnpm install
```

`scripts/org.sh` に組織の値（My Domain 名・共有 sandbox 名）を設定してから認証します:

```bash
pnpm run login <sandbox名>
```

instance URL は sandbox の命名規則から導出され、エイリアス = sandbox名 で登録されます。認証は sandbox ごとに初回とリフレッシュ後だけで済みます。

### GUI 変更の取り込み

```bash
pnpm run retrieve [sandbox名]  # 省略時は共有 sandbox
```

### retrieve 範囲のカスタマイズ

デフォルトでは `retrieve.sh` は `sfdx-project.json` のパッケージディレクトリに基づいてメタデータを取得します。管理パッケージが多い org や `package.xml` でワイルドカード取得する場合は以下に注意してください:

- **`.forceignore`** — 管理パッケージのメタデータ（例: `**/pi__*`）を retrieve/deploy 対象外にします。インストール済みパッケージに合わせてコメントを外すかパターンを追加してください。
- **`package.xml`** — ワイルドカード取得用のマニフェストを作成する場合、漏れやすいタイプ（`ApexTrigger`、`LightningComponentBundle`、`AuraDefinitionBundle`）を含めてください。

### Apex の整形

```bash
pnpm run format:apex
```

Apex クラス・トリガーは Prettier（`prettier-plugin-apex`）で整形します（それ以外は oxfmt が担当）。`pnpm run check` に対応する検査が含まれます。

### デプロイ前の検証

```bash
pnpm run validate [sandbox名]  # 省略時は共有 sandbox
```

### コード解析とベースライン

```bash
pnpm run scan
```

CI は severity を問わずすべての違反で fail します。既存違反は `code-analyzer.yml` にファイル×ルール単位の上限として固定し、上限を超えた分＝新規違反だけが fail します。

- 初回は `pnpm run baseline` を実行して、org の既存違反から `code-analyzer.yml` を生成してください
- 既存違反の詳細（ファイル・行・メッセージ）は `pnpm run scan:all` で確認できます（抑止無効の詳細スキャン。`--target <file>` で絞り込み可）。件数だけなら `code-analyzer.yml` を直接見るのが速いです
- 既存違反を修正したら、同じ PR で `pnpm run baseline` を実行して上限を下げます（ラチェット）
- 件数が増える再生成はエラーで止まります。承知の上で取り込むときだけ `pnpm run baseline --allow-increase` を付けてください

### 個人 sandbox へのデプロイ

```bash
pnpm run deploy <sandbox名>
```

未認証なら先に web ログインを挟んでからデプロイします。手元の未コミット変更もそのまま反映されます。共有 sandbox へのデプロイは `sandbox` ブランチへの push 経由のみです（script 側でも拒否します）。

本番へのデプロイは `main` ブランチへのマージで CI/CD が自動実行します（ローカルからの手動デプロイは不可）。

## デプロイ戦略

| ブランチ  | デプロイ先     | トリガー      |
| --------- | -------------- | ------------- |
| `sandbox` | Sandbox org    | push 時に自動 |
| `main`    | Production org | push 時に自動 |

いずれのブランチへの PR も CI で dry-run 検証（`pnpm exec sf project deploy start --dry-run`）を実行。

### 差分デプロイと削除の反映

push 時のデプロイは、そのブランチの最後に成功したデプロイ以降の変更分だけを送る。基準コミットは Deploy ワークフロー自身の実行履歴から読む（追加の状態管理なし）。マニフェストと `destructiveChanges.xml` は [sfdx-git-delta](https://github.com/scolladon/sfdx-git-delta) で生成し、変更と削除を 1 回のアトミックなデプロイとして実行する。依存関係を壊す削除はデプロイ全体がロールバックされる。PR 検証では同じ差分を dry-run し、変更と削除の一覧を job summary に出す。

基準が使えない場合（初回デプロイ・履歴の書き換え・古い run の再実行）は、削除なしの全量デプロイに自動フォールバックする。workflow_dispatch で全量デプロイを強制することもできる。`pnpm run deploy` による個人 sandbox へのデプロイは従来どおり全量のみで、削除は反映されない。

## プロジェクト構成

```text
salesforce-metadata-template/
├── force-app/main/default/   # Salesforce メタデータ（ソース形式）
│   ├── flows/                # フロー定義
│   ├── objects/              # カスタムオブジェクト・項目
│   ├── permissionsets/       # 権限セット
│   ├── layouts/              # ページレイアウト
│   └── ...                   # その他のメタデータカテゴリ
├── scripts/
│   ├── org.sh                # 組織ごとの値（My Domain・共有 sandbox 名）
│   ├── retrieve.sh           # GUI 変更取得ヘルパー
│   ├── login.sh              # sandbox への web ログイン
│   ├── deploy.sh             # 個人 sandbox へのデプロイ
│   ├── validate.sh           # dry-run 検証
│   ├── baseline.sh           # code-analyzer ベースライン再生成
│   └── scan-all.sh           # 抑止無効のフルスキャン
├── .github/workflows/
│   ├── ci.yml                # PR バリデーション（dry-run deploy）
│   ├── deploy.yml            # push 時の自動デプロイ
│   └── sync-template.yml     # 週次テンプレート同期
├── docs/                     # セットアップドキュメント
├── sfdx-project.json         # Salesforce プロジェクト設定（API v67.0）
├── .mise.toml                # Node.js・Java バージョン管理
└── package.json              # sf CLI + CI ツール（oxlint, oxfmt, prettier）
```

## CI/CD 認証

JWT Bearer Flow を使用。セットアップ手順は [docs/jwt-auth-setup.ja.md](docs/jwt-auth-setup.ja.md) を参照。

Repository variables: `SF_MY_DOMAIN` / `SF_CI_USERNAME` / `SF_CLIENT_ID`。環境ごと（`sandbox` / `production`）には secret `SF_JWT_KEY`（sandbox 用と本番用で別の鍵ペア）と、sandbox 環境のみ variable `SANDBOX_ID` を登録する。username と instance URL はワークフロー側で導出される。

## テンプレート同期

このテンプレートから作成したリポジトリは、`sync-template.yml` ワークフローが週次で上流の更新を確認し、更新があれば `template-sync` ラベル付きの PR を自動作成する。

`.templatesyncignore` は許可リスト形式で、列挙したファイル（ツール設定とメタファイル）だけを同期する。メタデータ・スクリプト・ドキュメント・README が上書きされることはない。

CI/CD ワークフローは同期しない。GitHub は既定の Actions トークンからのワークフロー push を拒否するため。ワークフロー内のバージョン更新（action の SHA）は Renovate が行い、CI ロジック自体の変更はリポジトリごとに意図して取り込む。依存関係（`package.json`・`.mise.toml`）も Renovate の管轄。

## Renovate

依存関係は [Renovate](https://docs.renovatebot.com/) が更新する（設定は [`h13/renovate-config`](https://github.com/h13/renovate-config)）。このテンプレートから作成したリポジトリでは [Renovate アプリ](https://github.com/apps/renovate) のインストールが必要（[導入手順](https://docs.renovatebot.com/getting-started/installing-onboarding/)）。

## ドキュメント

- [Org とリポジトリの運用モデル](docs/org-model.ja.md) — 1リポ = 1本番 org、複数 Sandbox の扱い、衝突回避
- [認証ガイド](docs/authentication.ja.md) — ローカル開発 vs CI/CD の認証方式、必要な権限
- [JWT 認証セットアップ](docs/jwt-auth-setup.ja.md) — Connected App と GitHub Secrets の設定手順

## ライセンス

[MIT](LICENSE)
