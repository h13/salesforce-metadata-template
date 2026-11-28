#!/usr/bin/env bash
set -euo pipefail

# Detailed scan with suppressions (the baseline) disabled. Use it to inspect
# the content of existing violations.
# Extra arguments are passed through to sf code-analyzer run
# (e.g. --target <file>).

# Java is required by the PMD engine; declared in .mise.toml
if ! java -version >/dev/null 2>&1; then
  echo "Java not found. Run: mise install" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'suppressions:\n  disable_suppressions: true\n' >"$TMP/no-suppressions.yml"

pnpm exec sf code-analyzer run --workspace force-app \
  --config-file "$TMP/no-suppressions.yml" \
  --view detail "$@"
