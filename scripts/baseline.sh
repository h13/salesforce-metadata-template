#!/usr/bin/env bash
set -euo pipefail

# ベースライン (code-analyzer.yml) の再生成。
# 抑止を無効化した一時設定でフルスキャンし、素の違反数から生成する。
# 通常設定のスキャンや CI 成果物は「抑止後」の結果しか含まないため、
# そこから再生成すると常に 0 件になる（循環）。
# --allow-increase はそのまま generate に渡る。

# Java は PMD エンジンの要件。.mise.toml で宣言している
if ! java -version >/dev/null 2>&1; then
  echo "Java が見つかりません。mise install を実行してください" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'suppressions:\n  disable_suppressions: true\n' >"$TMP/no-suppressions.yml"
echo "抑止無効でスキャンします（数分かかります）" >&2
pnpm exec sf code-analyzer run --workspace . \
  --config-file "$TMP/no-suppressions.yml" \
  --output-file "$TMP/sfca_results.json"

node scripts/generate-baseline.mjs "$TMP/sfca_results.json" "$@"
