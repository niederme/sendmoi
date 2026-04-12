#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/SendMoi.xcodeproj/project.pbxproj"
APP_NAME="SendMoi.app"
SHARE_NAME="SendMoiShare.appex"

warn() {
  echo "warning: $*" >&2
}

current_build="$(perl -ne 'if (/CURRENT_PROJECT_VERSION = ([0-9]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"

if [[ -z "$current_build" ]]; then
  warn "Could not read CURRENT_PROJECT_VERSION from $PROJECT_FILE"
  exit 0
fi

find_latest_archive() {
  local archives_root="$HOME/Library/Developer/Xcode/Archives"
  local newest_path=""
  local newest_mtime=0

  [[ -d "$archives_root" ]] || return 0

  while IFS= read -r -d '' candidate; do
    [[ -d "$candidate/Products/Applications/$APP_NAME" ]] || continue

    local modified_at
    modified_at="$(stat -f '%m' "$candidate" 2>/dev/null || echo 0)"
    if (( modified_at > newest_mtime )); then
      newest_mtime="$modified_at"
      newest_path="$candidate"
    fi
  done < <(find "$archives_root" -type d -name '*.xcarchive' -mmin -180 -print0 2>/dev/null)

  echo "$newest_path"
}

archive_path="${1:-${ARCHIVE_PATH:-}}"
if [[ -z "$archive_path" || ! -d "$archive_path" ]]; then
  archive_path="$(find_latest_archive)"
fi

if [[ -z "$archive_path" || ! -d "$archive_path" ]]; then
  warn "Could not locate the freshly created archive to sync build number."
  exit 0
fi

archive_plist="$archive_path/Info.plist"
app_plist="$archive_path/Products/Applications/$APP_NAME/Contents/Info.plist"
share_plist="$archive_path/Products/Applications/$APP_NAME/Contents/PlugIns/$SHARE_NAME/Contents/Info.plist"

update_plist_value() {
  local plist_path="$1"
  local key_path="$2"
  local value="$3"

  if [[ ! -f "$plist_path" ]]; then
    return
  fi

  if /usr/libexec/PlistBuddy -c "Print $key_path" "$plist_path" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set $key_path $value" "$plist_path"
  fi
}

update_plist_value "$archive_plist" ":ApplicationProperties:CFBundleVersion" "$current_build"
update_plist_value "$app_plist" ":CFBundleVersion" "$current_build"
update_plist_value "$share_plist" ":CFBundleVersion" "$current_build"

echo "Synced archive build number to $current_build at $archive_path"
