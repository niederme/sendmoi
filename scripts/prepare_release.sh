#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/MailMoi.xcodeproj/project.pbxproj"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/prepare_release.sh [--version X.Y[.Z]] [--build N] [--dry-run]

Defaults:
  - Keeps the current marketing version unless --version is provided.
  - Increments the current build number by 1 unless --build is provided.

Examples:
  ./scripts/prepare_release.sh
  ./scripts/prepare_release.sh --version 0.3
  ./scripts/prepare_release.sh --version 0.3 --build 7
  ./scripts/prepare_release.sh --dry-run
EOF
}

next_version=""
next_build=""
dry_run=false

while (( $# > 0 )); do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 1; }
      next_version="$2"
      shift 2
      ;;
    --build)
      [[ $# -ge 2 ]] || { echo "Missing value for --build" >&2; exit 1; }
      next_build="$2"
      shift 2
      ;;
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

current_version="$(perl -ne 'if (/MARKETING_VERSION = ([0-9.]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"
current_build="$(perl -ne 'if (/CURRENT_PROJECT_VERSION = ([0-9]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"
team_id="$(perl -ne 'if (/DEVELOPMENT_TEAM = ([A-Z0-9]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"
signing_style="$(perl -ne 'if (/CODE_SIGN_STYLE = ([^;]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"
app_bundle_id="$(perl -ne 'print "$1\n" if /PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/' "$PROJECT_FILE" | head -n 1)"
share_bundle_id="$(perl -ne 'print "$1\n" if /PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/' "$PROJECT_FILE" | tail -n 1)"

if [[ -n "$next_version" && ! "$next_version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "Version must look like 1, 1.2, or 1.2.3" >&2
  exit 1
fi

if [[ -n "$next_build" && ! "$next_build" =~ ^[0-9]+$ ]]; then
  echo "Build must be a positive integer" >&2
  exit 1
fi

if [[ -z "$next_version" ]]; then
  next_version="$current_version"
fi

if [[ -z "$next_build" ]]; then
  next_build="$(( current_build + 1 ))"
fi

if [[ "$dry_run" == false ]]; then
  perl -0pi -e 's/CURRENT_PROJECT_VERSION = \d+;/CURRENT_PROJECT_VERSION = '"$next_build"';/g' "$PROJECT_FILE"
  perl -0pi -e 's/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = '"$next_version"';/g' "$PROJECT_FILE"
fi

echo "Release prep summary"
echo "  Previous version: $current_version"
echo "  Previous build:   $current_build"
echo "  Next version:     $next_version"
echo "  Next build:       $next_build"
echo "  Signing:          $signing_style"
echo "  Team ID:          $team_id"
echo "  App bundle ID:    $app_bundle_id"
echo "  Share bundle ID:  $share_bundle_id"

if [[ "$dry_run" == true ]]; then
  echo
  echo "Dry run only. No files changed."
else
  echo
  echo "Updated $PROJECT_FILE"
fi

echo
echo "Next:"
echo "  1. Open the project in Xcode."
echo "  2. Product > Clean Build Folder."
echo "  3. Product > Archive."
