# SendMoi Privacy Policy

Last updated: March 1, 2026

SendMoi is a local-first app that helps you send shared links as emails through your own Gmail account. This policy explains what SendMoi handles, where that data goes, and what stays on your device.

## What SendMoi Accesses

SendMoi may access the following information when you use the app:

- Your Gmail account email address.
- OAuth tokens used to keep you signed in to Gmail.
- Email recipients you enter or save as defaults/recent recipients.
- The title, excerpt, and URL of content you share into the app.
- Queued email content that has not been sent yet.

If you share a web link, SendMoi may also fetch the linked page and its preview image to improve the outgoing email with:

- A better title.
- Excerpt text.
- A short summary.
- An inline preview image.

## How Your Data Is Used

SendMoi uses this information only to provide its core features:

- Sign you in with Google.
- Send email through the Gmail API on your behalf.
- Remember your default and recent recipients.
- Queue emails offline and retry them later.
- Enrich shared links before sending when metadata is available.

SendMoi does not use your data for advertising, analytics, profiling, or sale to third parties.

## Where Data Is Stored

SendMoi stores data locally on your device, including:

- Gmail session information used to keep you signed in.
- Your saved default and recent recipients.
- Any queued emails waiting to be sent.

This local storage may be kept in standard app storage, the system keychain, and shared app container storage used by the SendMoi Share Extension.

## What Is Sent Off Your Device

SendMoi does not run its own backend service. When network requests happen, they are sent directly from your device to the services needed for the feature you are using:

- Google authentication endpoints, to sign you in and refresh your Gmail session.
- Gmail API endpoints, to send email through your Gmail account.
- The websites you share, when SendMoi fetches page metadata or preview images to improve the outgoing email.

If summary generation is available on your device through Apple system frameworks, SendMoi may use those on-device capabilities to create a short article summary before sending. SendMoi does not send article text to a SendMoi-operated server for summarization.

## Third Parties

SendMoi relies on third-party services only where necessary to provide the app:

- Google, for authentication and Gmail delivery.
- The websites whose links you choose to share, for metadata and preview retrieval.
- Apple system frameworks and platform services used to run the app and its Share Extension.

Those services operate under their own privacy terms and policies.

## Your Choices

You can control your data in several ways:

- Sign out of Gmail from within SendMoi to remove the saved Gmail session used by the app.
- Delete queued emails from the app before they are sent.
- Change or clear the default recipient at any time.
- Stop sharing links into SendMoi if you do not want page metadata to be fetched.

## Children’s Privacy

SendMoi is not directed to children under 13 and is not designed to knowingly collect personal information from children.

## Changes To This Policy

This policy may be updated as SendMoi changes. The "Last updated" date at the top of this document reflects the latest revision.

## Contact

For questions about SendMoi or this policy, use the project repository:

[https://github.com/niederme/sendmoi](https://github.com/niederme/sendmoi)
