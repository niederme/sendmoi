#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/SendMoi.xcodeproj/project.pbxproj"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/bump_build_number.sh [--dry-run]

Increments CURRENT_PROJECT_VERSION across the Xcode project.
EOF
}

dry_run=false

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Could not find project file: $PROJECT_FILE" >&2
  exit 1
fi

current_build="$(perl -ne 'if (/CURRENT_PROJECT_VERSION = ([0-9]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"

if [[ -z "$current_build" ]]; then
  echo "Could not read CURRENT_PROJECT_VERSION from $PROJECT_FILE" >&2
  exit 1
fi

next_build="$(( current_build + 1 ))"

if [[ "$dry_run" == false ]]; then
  perl -0pi -e 's/CURRENT_PROJECT_VERSION = \d+;/CURRENT_PROJECT_VERSION = '"$next_build"';/g' "$PROJECT_FILE"
fi

echo "Build number: $current_build -> $next_build"

if [[ "$dry_run" == true ]]; then
  echo "Dry run only. No files changed."
fi
