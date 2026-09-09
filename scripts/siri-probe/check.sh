#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
mkdir -p build/siri-probe-tools
xcrun swiftc -parse-as-library -D SENDMOI_SIRI_PROBE -target arm64-apple-macos15.0 \
  SendMoi/Models.swift SendMoi/Services/GmailDeliveryService.swift \
  SendMoi/Services/GmailShared.swift SendMoi/Services/GoogleOAuthConfig.swift \
  SendMoi/Services/SharedContainer.swift scripts/siri-probe/ProbeChecks.swift \
  -o build/siri-probe-tools/probe-checks
build/siri-probe-tools/probe-checks "$@"
