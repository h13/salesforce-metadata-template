#!/usr/bin/env bash
set -euo pipefail

# 個人 sandbox へのデプロイ

# shellcheck disable=SC1091
source "$(dirname "$0")/org.sh"

NAME="${1:?使い方: pnpm run deploy <sandbox名>}"

# 共有へ直接撒くと sandbox ブランチと実体がずれるため拒否（ホスト名は大文字小文字非区別）
if [ "$(echo "$NAME" | tr '[:upper:]' '[:lower:]')" = "$SHARED_SANDBOX" ]; then
  echo "共有 Sandbox ($SHARED_SANDBOX) へは sandbox ブランチへの push でデプロイしてください" >&2
  exit 1
fi

bash "$(dirname "$0")/login.sh" "$NAME"
pnpm exec sf project deploy start --target-org "$NAME"
