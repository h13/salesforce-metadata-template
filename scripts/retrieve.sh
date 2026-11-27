#!/usr/bin/env bash
set -euo pipefail

# retrieve.sh — Pull metadata changes made via GUI from the target org.
#
# Usage:
#   ./scripts/retrieve.sh [sandbox-name]
#
# Defaults to the shared sandbox configured in scripts/org.sh.

# shellcheck disable=SC1091
source "$(dirname "$0")/org.sh"

ORG="${1:-$SHARED_SANDBOX}"

bash "$(dirname "$0")/login.sh" "$ORG"

echo "Retrieving metadata from org: $ORG"
sf project retrieve start --target-org "$ORG" --wait 60

echo ""
echo "Done. Review changes with: git diff"
