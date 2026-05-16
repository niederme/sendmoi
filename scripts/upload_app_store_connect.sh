#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$ROOT_DIR/SendMoi.xcodeproj"
PROJECT_FILE="$PROJECT/project.pbxproj"
SCHEME="${SCHEME:-SendMoi}"
CONFIGURATION="${CONFIGURATION:-Release}"
PLATFORM="${PLATFORM:-ios}"
EXPORT_DIR="${EXPORT_DIR:-$ROOT_DIR/build/app-store-connect-export}"
ASC_CONFIG_FILE="${ASC_CONFIG_FILE:-$HOME/.appstoreconnect/sendmoi.env}"
AUTH_MODE="${AUTH_MODE:-}"
DESTINATION="${DESTINATION:-upload}"
IOS_SIGNING_STYLE="${IOS_SIGNING_STYLE:-automatic}"
IOS_SIGNING_CERTIFICATE="${IOS_SIGNING_CERTIFICATE:-Apple Distribution: John Niedermeyer (289GY9L343)}"
IOS_APP_PROFILE_NAME="${IOS_APP_PROFILE_NAME:-SendMoi iOS App Store 2026}"
IOS_SHARE_PROFILE_NAME="${IOS_SHARE_PROFILE_NAME:-SendMoi Share iOS App Store 2026}"
MACOS_SIGNING_STYLE="${MACOS_SIGNING_STYLE:-manual}"
MACOS_SIGNING_CERTIFICATE="${MACOS_SIGNING_CERTIFICATE:-3rd Party Mac Developer Application: John Niedermeyer (289GY9L343)}"
MACOS_INSTALLER_SIGNING_CERTIFICATE="${MACOS_INSTALLER_SIGNING_CERTIFICATE:-3rd Party Mac Developer Installer: John Niedermeyer (289GY9L343)}"
MACOS_APP_PROFILE_NAME="${MACOS_APP_PROFILE_NAME:-SendMoi Mac App Store 2026}"
MACOS_SHARE_PROFILE_NAME="${MACOS_SHARE_PROFILE_NAME:-SendMoi Share Mac App Store 2026}"
SKIP_ARCHIVE=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/upload_app_store_connect.sh [options]

Options:
  --archive-path PATH   Use or create this archive path.
  --export-dir PATH     Export/upload working directory.
  --platform PLATFORM   Archive ios or macos. Defaults to ios.
  --auth-mode MODE      Use account or api-key auth. Defaults to account for iOS and api-key for macOS.
  --export-only         Export an IPA without uploading.
  --skip-archive        Reuse --archive-path instead of building a new archive.
  --dry-run             Print the commands without running them.

Environment:
  PLATFORM              ios or macos. Defaults to ios.
  AUTH_MODE             account or api-key. Defaults to account for iOS and api-key for macOS.
  IOS_SIGNING_STYLE     automatic or manual. Defaults to automatic.
  IOS_APP_PROFILE_NAME  iOS app provisioning profile name for manual signing.
  IOS_SHARE_PROFILE_NAME
                        iOS share extension provisioning profile name for manual signing.
  MACOS_SIGNING_STYLE   automatic or manual. Defaults to manual.
  MACOS_APP_PROFILE_NAME
                        macOS app provisioning profile name for manual signing.
  MACOS_SHARE_PROFILE_NAME
                        macOS share extension provisioning profile name for manual signing.
  ASC_KEY_ID            App Store Connect API key ID.
  ASC_ISSUER_ID         App Store Connect issuer ID.
  ASC_KEY_PATH          Path to AuthKey_<key id>.p8.
  ASC_CONFIG_FILE       Optional env file to source. Defaults to ~/.appstoreconnect/sendmoi.env.

The default account auth mode uses the Apple account signed in to Xcode. API-key
auth is still available, but cloud distribution signing may require Xcode account
auth depending on the API key's role and cloud-signing permissions.

In api-key mode, if ASC_KEY_ID or ASC_ISSUER_ID is omitted, the script reads
ASC_CONFIG_FILE when it exists.
If ASC_KEY_PATH is omitted, the script uses:
  ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
EOF
}

ARCHIVE_PATH=""

while (( $# > 0 )); do
  case "$1" in
    --archive-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --archive-path" >&2; exit 1; }
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --export-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --export-dir" >&2; exit 1; }
      EXPORT_DIR="$2"
      shift 2
      ;;
    --platform)
      [[ $# -ge 2 ]] || { echo "Missing value for --platform" >&2; exit 1; }
      PLATFORM="$2"
      shift 2
      ;;
    --auth-mode)
      [[ $# -ge 2 ]] || { echo "Missing value for --auth-mode" >&2; exit 1; }
      AUTH_MODE="$2"
      shift 2
      ;;
    --export-only)
      DESTINATION="export"
      shift
      ;;
    --skip-archive)
      SKIP_ARCHIVE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
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

case "$PLATFORM" in
  ios)
    archive_destination="generic/platform=iOS"
    archive_platform_label="iOS"
    AUTH_MODE="${AUTH_MODE:-account}"
    ;;
  macos)
    archive_destination="generic/platform=macOS"
    archive_platform_label="macOS"
    AUTH_MODE="${AUTH_MODE:-api-key}"
    ;;
  *)
    echo "PLATFORM must be ios or macos." >&2
    exit 1
    ;;
esac

if [[ "$AUTH_MODE" != "account" && "$AUTH_MODE" != "api-key" ]]; then
  echo "AUTH_MODE must be account or api-key." >&2
  exit 1
fi

if [[ "$DESTINATION" != "upload" && "$DESTINATION" != "export" ]]; then
  echo "DESTINATION must be upload or export." >&2
  exit 1
fi

if [[ "$IOS_SIGNING_STYLE" != "automatic" && "$IOS_SIGNING_STYLE" != "manual" ]]; then
  echo "IOS_SIGNING_STYLE must be automatic or manual." >&2
  exit 1
fi

if [[ "$MACOS_SIGNING_STYLE" != "automatic" && "$MACOS_SIGNING_STYLE" != "manual" ]]; then
  echo "MACOS_SIGNING_STYLE must be automatic or manual." >&2
  exit 1
fi

auth_args=(-allowProvisioningUpdates)

if [[ "$AUTH_MODE" == "api-key" ]]; then
  if [[ -f "$ASC_CONFIG_FILE" ]]; then
    source "$ASC_CONFIG_FILE"
  fi

  [[ -n "${ASC_KEY_ID:-}" ]] || { echo "ASC_KEY_ID is required in api-key auth mode." >&2; exit 1; }
  [[ -n "${ASC_ISSUER_ID:-}" ]] || { echo "ASC_ISSUER_ID is required in api-key auth mode." >&2; exit 1; }

  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  [[ -f "$ASC_KEY_PATH" ]] || { echo "App Store Connect key not found: $ASC_KEY_PATH" >&2; exit 1; }

  auth_args+=(
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

version="$(perl -ne 'if (/MARKETING_VERSION = ([0-9.]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"
build="$(perl -ne 'if (/CURRENT_PROJECT_VERSION = ([0-9]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"
team_id="$(perl -ne 'if (/DEVELOPMENT_TEAM = ([A-Z0-9]+);/) { print "$1\n"; exit }' "$PROJECT_FILE")"

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$ROOT_DIR/build/archives/SendMoi-${version}-${build}-${archive_platform_label}.xcarchive"
fi

EXPORT_OPTIONS="$(mktemp "${TMPDIR:-/tmp}/sendmoi-export-options.XXXXXX")"
trap 'rm -f "$EXPORT_OPTIONS"' EXIT

{
  print '<?xml version="1.0" encoding="UTF-8"?>'
  print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  print '<plist version="1.0">'
  print '<dict>'
  print '  <key>method</key>'
  print '  <string>app-store-connect</string>'
  print '  <key>destination</key>'
  print "  <string>$DESTINATION</string>"
  print '  <key>teamID</key>'
  print "  <string>$team_id</string>"
  print '  <key>signingStyle</key>'
  if [[ "$PLATFORM" == "ios" && "$IOS_SIGNING_STYLE" == "manual" ]]; then
    print '  <string>manual</string>'
    print '  <key>signingCertificate</key>'
    print "  <string>$IOS_SIGNING_CERTIFICATE</string>"
    print '  <key>provisioningProfiles</key>'
    print '  <dict>'
    print '    <key>com.niederme.SendMoi</key>'
    print "    <string>$IOS_APP_PROFILE_NAME</string>"
    print '    <key>com.niederme.SendMoi.ShareExtension</key>'
    print "    <string>$IOS_SHARE_PROFILE_NAME</string>"
    print '  </dict>'
  elif [[ "$PLATFORM" == "macos" && "$MACOS_SIGNING_STYLE" == "manual" ]]; then
    print '  <string>manual</string>'
    print '  <key>signingCertificate</key>'
    print "  <string>$MACOS_SIGNING_CERTIFICATE</string>"
    print '  <key>installerSigningCertificate</key>'
    print "  <string>$MACOS_INSTALLER_SIGNING_CERTIFICATE</string>"
    print '  <key>provisioningProfiles</key>'
    print '  <dict>'
    print '    <key>com.niederme.SendMoi</key>'
    print "    <string>$MACOS_APP_PROFILE_NAME</string>"
    print '    <key>com.niederme.SendMoi.ShareExtension</key>'
    print "    <string>$MACOS_SHARE_PROFILE_NAME</string>"
    print '  </dict>'
  else
    print '  <string>automatic</string>'
  fi
  print '  <key>manageAppVersionAndBuildNumber</key>'
  print '  <false/>'
  print '  <key>uploadSymbols</key>'
  print '  <true/>'
  print '</dict>'
  print '</plist>'
} > "$EXPORT_OPTIONS"

archive_cmd=(
  xcodebuild
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "$archive_destination"
  -archivePath "$ARCHIVE_PATH"
  "${auth_args[@]}"
  archive
)

export_cmd=(
  xcodebuild
  -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportPath "$EXPORT_DIR"
  -exportOptionsPlist "$EXPORT_OPTIONS"
  "${auth_args[@]}"
)

echo "App Store Connect upload"
echo "  Version:      $version ($build)"
echo "  Team ID:      $team_id"
echo "  Platform:     $archive_platform_label"
echo "  Auth mode:    $AUTH_MODE"
echo "  Destination:  $DESTINATION"
echo "  Archive path: $ARCHIVE_PATH"
echo "  Export dir:   $EXPORT_DIR"
if [[ "$AUTH_MODE" == "api-key" ]]; then
  echo "  Key path:     $ASC_KEY_PATH"
fi
echo

if [[ "$DRY_RUN" == true ]]; then
  if [[ "$SKIP_ARCHIVE" == false ]]; then
    printf '%q ' "${archive_cmd[@]}"
    echo
  fi
  printf '%q ' "${export_cmd[@]}"
  echo
  exit 0
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_DIR"

if [[ "$SKIP_ARCHIVE" == false ]]; then
  "${archive_cmd[@]}"
else
  [[ -d "$ARCHIVE_PATH" ]] || { echo "Archive does not exist: $ARCHIVE_PATH" >&2; exit 1; }
fi

"${export_cmd[@]}"
