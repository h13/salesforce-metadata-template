#!/usr/bin/env bash
set -euo pipefail

# Regenerate the baseline (code-analyzer.yml).
# Runs a full scan with suppressions disabled via a temporary config and
# generates the baseline from the raw violation counts.
# A normal scan (or a CI artifact) only contains post-suppression results,
# so regenerating from those would always yield 0 violations (circular).
# --allow-increase is passed through to the generate step as-is.

# Java is required by the PMD engine; declared in .mise.toml
if ! java -version >/dev/null 2>&1; then
  echo "Java not found. Run: mise install" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'suppressions:\n  disable_suppressions: true\n' >"$TMP/no-suppressions.yml"
echo "Scanning with suppressions disabled (this takes a few minutes)" >&2
pnpm exec sf code-analyzer run --workspace force-app \
  --config-file "$TMP/no-suppressions.yml" \
  --output-file "$TMP/sfca_results.json"

node scripts/generate-baseline.mjs "$TMP/sfca_results.json" "$@"
