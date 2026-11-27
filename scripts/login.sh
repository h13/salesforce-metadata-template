#!/usr/bin/env bash
set -euo pipefail

# sandbox への web ログイン。エイリアス = sandbox名 で登録する

# shellcheck disable=SC1091
source "$(dirname "$0")/org.sh"

NAME="${1:?使い方: pnpm run login <sandbox名>}"

# URL のホスト名に入るため検証する
if ! [[ "$NAME" =~ ^[A-Za-z0-9]{1,10}$ ]]; then
  echo "sandbox名は英数字のみ（最大10文字）: $NAME" >&2
  exit 1
fi

if pnpm exec sf org display --target-org "$NAME" >/dev/null 2>&1; then
  echo "認証済み: $NAME" >&2
  exit 0
fi

pnpm exec sf org login web --alias "$NAME" \
  --instance-url "https://${MY_DOMAIN}--${NAME}.sandbox.my.salesforce.com"
