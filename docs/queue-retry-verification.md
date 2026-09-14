# Share extension queue retry verification

Branch: `codex/queue-retry`. Worktree: `.worktrees/queue-retry`.

Opening the extension now starts a bounded backlog attempt before auto-send. The new share waits for that attempt, then receives its own delivery budget. Preview waiting uses a deadline that does not wait for an uncooperative preview task. Extension sends use the available content instead of restarting article enrichment; local attachments are retained and remote images remain URL references.

Queue delivery has an exclusive process lock, and removals, failure updates, and enrichment replacements operate on the current queue under a separate mutation lock. App analytics no longer delay the next email. Repeated appends of the same queue ID are ignored.

## Automated verification

Passed with Xcode 27.0 (27A266a): iOS Simulator and macOS builds, plus isolated Swift regression checks for queue identities, concurrent appends, preserving appended items during removal, delivery lock contention, preventing late enrichment from resurrecting an item, and a preview deadline whose losing task ignores cancellation.

From this worktree:

```sh
python3 tests/test_queue_retry.py
xcodebuild -project SendMoi.xcodeproj -scheme SendMoi -destination 'generic/platform=iOS Simulator' -derivedDataPath .deriveddata-local CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SendMoi.xcodeproj -scheme SendMoi -destination 'generic/platform=macOS' -derivedDataPath build/queue-mac CODE_SIGNING_ALLOWED=NO build
```

The project has no XCTest target. The Python runner compiles the production QueueStore with temporary storage and minimal model stubs, and extracts the production deadline helper for isolated Swift execution. It does not send email or access the real app container.

## Device verification

The signed Debug build was installed and launched on Karin Air on September 14, 2026. The user reported that it seems to be working. The full scenario matrix below has not been independently completed.

1. Install this branch on the iOS 27 phone using the SendMoi scheme in this worktree's Xcode project.
2. With connectivity disabled, share two distinct test links to yourself. Leave the main app closed.
3. Restore connectivity and share a third link through SendMoi with auto-send enabled.
4. Verify in Gmail that the older queued messages arrive as well as the new share, without first opening SendMoi. Then inspect the queue in SendMoi.
5. Repeat with auto-send disabled; merely opening the extension should attempt the existing backlog while the new share remains editable.
6. Exercise a slow article preview. Sending should fall back to available content rather than waiting indefinitely for enrichment.

These checks send real messages and have not been performed by the agent. This change does not add an iOS background scheduler. Large backlogs can need multiple extension openings or the main app. A Gmail request accepted just before cancellation can still have an ambiguous delivery outcome; the queue lock prevents competing local senders but does not provide server-side exactly-once delivery.
