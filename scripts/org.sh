# shellcheck shell=bash
# shellcheck disable=SC2034  # 変数は source 元の script が使う
# 組織ごとの値。テンプレートからリポジトリを作成したら書き換える
# （scripts/ はテンプレート同期の対象外なので、書き換えても上書きされない）
MY_DOMAIN="your-company"     # https://<MY_DOMAIN>.my.salesforce.com の My Domain 名
SHARED_SANDBOX="integration" # CI の検証と自動デプロイが使う共有 sandbox 名
