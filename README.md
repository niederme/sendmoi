# MailMoi

Minimal native SwiftUI app for iPhone, iPad, and macOS that sends a rich HTML email through the Gmail API and keeps an offline queue so shared links are never dropped.

## What the MVP does

- Authenticates with Gmail using OAuth 2.0 + PKCE.
- Uses the authenticated Gmail account as the sender.
- Lets you choose a recipient from recent addresses or type a new one.
- Lets you set a default recipient once and reuse it automatically.
- Uses the article title as the email subject.
- Uses only Apple-native frameworks (`SwiftUI`, `AuthenticationServices`, `Network`, `Security`).
- Includes a native Share Extension target for iPhone, iPad, and macOS share sheets.
- Sends this HTML body:

```html
<h2 style="margin-bottom: 10px;">Title</h2>
<p style="margin-bottom: 10px;"><i>Excerpt</i></p>
<p><a href="URL">URL</a></p>
```

- Writes every draft to a local JSON queue before any network call.
- Retries queued sends when the app regains connectivity, launches, or becomes active.
- Shares queue data and recent recipients through the App Group `group.com.niederme.mailmoi`.

## Setup For Personal Device Installs

1. Open [MailMoi/Services/GoogleOAuthConfig.swift](/Users/niederme/~Repos/mail-moi/MailMoi/Services/GoogleOAuthConfig.swift) and set `GoogleOAuthConfig.clientID` to your Google OAuth client ID.
2. In Google Cloud, create an OAuth client that supports native app sign-in and make its redirect URI match `GoogleOAuthConfig.redirectURI`.
3. If you change the OAuth client ID and need a different redirect scheme, update both:
   - [MailMoi/Services/GoogleOAuthConfig.swift](/Users/niederme/~Repos/mail-moi/MailMoi/Services/GoogleOAuthConfig.swift)
   - [MailMoi/Info.plist](/Users/niederme/~Repos/mail-moi/MailMoi/Info.plist)
4. Open [MailMoi.xcodeproj](/Users/niederme/~Repos/mail-moi/MailMoi.xcodeproj) in Xcode.
5. In `Signing & Capabilities`, turn on `Automatically manage signing` and make sure both targets use the same Team:
   - `MailMoi`
   - `MailMoiShare`
6. Confirm the App Group capability is present for both targets and matches `group.com.niederme.mailmoi`.
7. Connect your iPhone or iPad, choose it as the active run destination, and run the `MailMoi` scheme from Xcode.

No TestFlight or App Store Connect setup is required for this flow. Xcode will install a development-signed build directly on your device.

## Share Extension

- The `MailMoiShare` extension appears in native share sheets.
- It pre-fills title, excerpt, and URL from the shared item when the host app provides them.
- If a default recipient is already set and the share item includes enough data, it sends immediately and dismisses itself.
- If the extension cannot send right away (offline, expired session, API failure), it saves directly into the shared offline queue instead.
- If Safari or another host app only provides a URL, the extension still lets you edit the title and excerpt before saving.

## Notes

- Background delivery while the app is fully terminated is not implemented yet. The queue is durable; sending resumes when the app next launches or regains focus.
- Command-line builds still need local development provisioning for `com.niederme.MailMoi` and `com.niederme.MailMoi.ShareExtension`. In Xcode, that is handled by automatic signing; with `xcodebuild`, use `-allowProvisioningUpdates`.
