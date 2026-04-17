#!/bin/sh
set -e

# Write Analytics.plist from Xcode Cloud environment variables.
# Set ANALYTICS_FIREBASE_APP_ID and ANALYTICS_API_SECRET in the
# Xcode Cloud workflow environment before running builds.

PLIST_PATH="$CI_WORKSPACE/SendMoi/Services/Analytics.plist"

if [ -z "$ANALYTICS_FIREBASE_APP_ID" ] || [ -z "$ANALYTICS_API_SECRET" ]; then
    echo "Warning: ANALYTICS_FIREBASE_APP_ID or ANALYTICS_API_SECRET not set. Analytics will be disabled."
    FIREBASE_APP_ID=""
    API_SECRET=""
else
    FIREBASE_APP_ID="$ANALYTICS_FIREBASE_APP_ID"
    API_SECRET="$ANALYTICS_API_SECRET"
fi

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>FirebaseAppID</key>
	<string>${FIREBASE_APP_ID}</string>
	<key>APISecret</key>
	<string>${API_SECRET}</string>
</dict>
</plist>
EOF

echo "Analytics.plist written to $PLIST_PATH"
