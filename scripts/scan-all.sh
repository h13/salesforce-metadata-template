#!/usr/bin/env bash
set -euo pipefail

# 抑止（ベースライン）を無効化した詳細スキャン。既存違反の内容を見るために使う。
# 追加引数はそのまま sf code-analyzer run に渡る（例: --target <file>）。

# Java は PMD エンジンの要件。.mise.toml で宣言している
if ! java -version >/dev/null 2>&1; then
  echo "Java が見つかりません。mise install を実行してください" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'suppressions:\n  disable_suppressions: true\n' >"$TMP/no-suppressions.yml"

pnpm exec sf code-analyzer run --workspace . \
  --config-file "$TMP/no-suppressions.yml" \
  --view detail "$@"
