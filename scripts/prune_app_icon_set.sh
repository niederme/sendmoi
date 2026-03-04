#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_ICON_DIR=${1:-"$REPO_ROOT/MailMoi/Assets.xcassets/AppIcon.appiconset"}
CONTENTS_JSON="$APP_ICON_DIR/Contents.json"

if [ ! -f "$CONTENTS_JSON" ]; then
  printf 'Missing AppIcon Contents.json at %s\n' "$CONTENTS_JSON" >&2
  exit 1
fi

if ! command -v /usr/bin/ruby >/dev/null 2>&1; then
  printf 'This script requires /usr/bin/ruby to parse %s\n' "$CONTENTS_JSON" >&2
  exit 1
fi

ALLOWED_FILES=$(mktemp "${TMPDIR:-/tmp}/mailmoi-appicon.XXXXXX")
trap 'rm -f "$ALLOWED_FILES"' EXIT HUP INT TERM

/usr/bin/ruby -rjson -e '
  json = JSON.parse(File.read(ARGV[0]))
  json.fetch("images", []).map { |image| image["filename"] }.compact.sort.each { |name| puts name }
' "$CONTENTS_JSON" > "$ALLOWED_FILES"

REMOVED_COUNT=0

for FILE_PATH in "$APP_ICON_DIR"/*; do
  if [ ! -f "$FILE_PATH" ]; then
    continue
  fi

  FILE_NAME=$(basename "$FILE_PATH")

  if [ "$FILE_NAME" = "Contents.json" ]; then
    continue
  fi

  if ! grep -Fqx "$FILE_NAME" "$ALLOWED_FILES"; then
    rm "$FILE_PATH"
    printf 'Removed stray icon file: %s\n' "$FILE_NAME"
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
  fi
done

if [ "$REMOVED_COUNT" -eq 0 ]; then
  printf 'No stray icon files found in %s\n' "$APP_ICON_DIR"
fi
