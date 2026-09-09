#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
output_dir="${1:-build/siri-probe-fidelity}"
mkdir -p build/siri-probe-tools "$output_dir"
xcrun swiftc -parse-as-library -D SENDMOI_SIRI_PROBE -target arm64-apple-macos15.0 \
  SendMoi/Models.swift SendMoi/Services/GmailDeliveryService.swift \
  SendMoi/Services/GmailShared.swift SendMoi/Services/GoogleOAuthConfig.swift \
  SendMoi/Services/SharedContainer.swift scripts/siri-probe/ProbeHarness.swift \
  -o build/siri-probe-tools/probe-harness
build/siri-probe-tools/probe-harness scripts/siri-probe/corpus.json SendMoiShare/SafariPreprocessor.js "$output_dir"
