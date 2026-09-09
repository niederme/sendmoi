#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
mkdir -p build/enrichment-tools
xcrun swiftc -parse-as-library -D SENDMOI_ENRICHMENT_CHECKS -target arm64-apple-macos15.0 \
  SendMoi/Models.swift SendMoi/Services/GmailDeliveryService.swift \
  SendMoi/Services/GmailShared.swift SendMoi/Services/GoogleOAuthConfig.swift \
  SendMoi/Services/SharedContainer.swift scripts/enrichment/ExtractionChecks.swift \
  -o build/enrichment-tools/extraction-checks
build/enrichment-tools/extraction-checks
