> **Paused September 11, 2026. Historical quality candidate, not the active Siri update plan.** Retained below for separate review; this document is not an instruction to continue implementation or ship these changes. See [Use SendMoi through Siri](https://github.com/niederme/sendmoi/blob/codex/siri-probe/docs/superpowers/plans/2026-09-11-sendmoi-by-voice.md) for the active direction.

# Enrichment quality candidate

This branch splits the shared extraction changes from `codex/siri-probe` onto `main` at 663bd36. It contains no App Intent, probe app, probe warning copy, or delivery/queue changes. No merge or release is authorized by its existence.

The candidate prefers article paragraphs, filters chrome and captions, avoids full-page HTML layout during extraction, rejects recognized challenge titles, and improves extractive fallback behavior. It retains the current sentence-clipping limitation.

Run `scripts/enrichment/check.sh` for deterministic extraction checks. These are narrow source-level checks, not a share-extension regression suite; no Xcode test target has been added.

Before merge, add fixture-backed coverage for X/social posts, selected text, list-based and mixed paragraph/list articles, non-Safari shares with no preprocessor, and normal share-sheet enrichment/error paths. Assess title, supplied excerpt preservation, source URL, image selection, and summary coverage. Paragraph preference may discard useful list material and must be reviewed against those cases. Keep the frozen ten-article sample as supplementary evidence, not representative traffic.

The limited-preview warning remains exclusively inside SENDMOI_SIRI_PROBE on the separate experiment branch. No real-email warning-copy decision is included here.
