# SendMoi 1.3

Improved share-sheet reliability and queued email delivery. Fixed issues where slow previews could delay sending or leave emails waiting until you opened SendMoi.

## Release candidate

- Build: 156 for iOS and macOS.
- Both archives were uploaded successfully on September 14, 2026. App Review submission is a separate step.
- Queue fix: `1da00e3`.
- Verified: iOS Simulator and macOS builds, isolated queue/deadline regression checks, signed device build installed on Karin Air. The user reported successful testing and confirmed readiness.
- Scope: queue retries, bounded preview/model waits, and safer shared queue updates. PR #75 and the Siri/enrichment experimental branches are not included.

## Reproduce archive and upload

Check the latest App Store Connect build number before preparing a new candidate. Run from the release worktree:

```sh
./scripts/prepare_release.sh --version 1.3 --build 156
make upload-ios-app-store-connect
make upload-macos-app-store-connect
```

The upload targets use API-key authentication and manual distribution signing. Both archives use the prepared build number. The export command prefers Apple system tools to avoid incompatible Homebrew rsync flags during IPA packaging. An upload does not submit a version for App Review or publish it to the App Store.
