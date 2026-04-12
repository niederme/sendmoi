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

latest_uploaded_build=0
archives_root="$HOME/Library/Developer/Xcode/Archives"

if [[ -d "$archives_root" ]]; then
  while IFS= read -r -d '' archive_plist; do
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$archive_plist" 2>/dev/null || true)"
    [[ "$bundle_id" == "com.niederme.SendMoi" ]] || continue

    uploaded_build="$(/usr/libexec/PlistBuddy -c 'Print :Distributions:0:uploadedBuildNumber' "$archive_plist" 2>/dev/null || true)"
    if [[ "$uploaded_build" =~ ^[0-9]+$ ]] && (( uploaded_build > latest_uploaded_build )); then
      latest_uploaded_build="$uploaded_build"
    fi
  done < <(find "$archives_root" -type f -name 'Info.plist' -path '*.xcarchive/Info.plist' -print0 2>/dev/null)
fi

baseline_build="$current_build"
if (( latest_uploaded_build > baseline_build )); then
  baseline_build="$latest_uploaded_build"
fi

next_build="$(( baseline_build + 1 ))"

if [[ "$dry_run" == false ]]; then
  perl -0pi -e 's/CURRENT_PROJECT_VERSION = \d+;/CURRENT_PROJECT_VERSION = '"$next_build"';/g' "$PROJECT_FILE"
fi

echo "Project build: $current_build"
echo "Latest uploaded build: $latest_uploaded_build"
echo "Next build: $baseline_build -> $next_build"

if [[ "$dry_run" == true ]]; then
  echo "Dry run only. No files changed."
fi
