# Changelog

## [v0.1.1] - 2026-09-09

- Hardening/fixes only; no new overlay features or integration patch changes.
- Retain deployment recovery inodes, including late writes through open descriptors; manual cleanup policy replaces automatic quarantine deletion.
- Exact-destination publication/restoration, pinned deployment directories, shared path classification and cooperative deployment locking.
- Check Bash syntax separately for every script.
- Bound malformed shortcut data while preserving Qt 6 list compatibility; contain construction errors in the UI.
- Classify hardware by actual events, preserve prototype-named action IDs, wrap long labels and label compacted-row counts correctly.
- Permanent parser, transactional, race, mutation and isolated Qt regressions; full temporary Ambxst 1.2.6 cycle.
- Clarify structural target validation, concurrency limits and static lint versus runtime validation.
- Post-review fixes: staging through an exclusively-created open descriptor (`set -o noclobber` + `exec {fd}>`, O_EXCL) with retry on collision and descriptor-only verified preparation, replacing the `mktemp` + reopen-by-name flow; fail-closed LF/CR rejection in target resolution (tabs, spaces and UTF-8 remain valid). See docs/qa/v0.1.1/REPORT.md adenda.
- Real-session runtime validation on Ambxst 1.2.6: T018 PASS, T019-A PASS, T019-B PASS, T020-1/2/3 PASS, T020-4 NOT EXECUTED (layout selector unreachable with the overlay open), T021-A/B/C PASS (overlay coexistence, lock/unlock, suspend/wake). See docs/qa/v0.1.1/REPORT.md adenda J.

## [v0.1.0] - 2026-09-04

- Native keyboard-shortcuts overlay for Ambxst.
- Dynamic, read-only loading from `binds.json`.
- Shortcut grouping, deduplication, and numbered-family compaction.
- Responsive design with scrolling, keyboard navigation, and multi-monitor support.
- Transactional installation and uninstall with safe rollback behavior.
- Automated parser and transactional-script tests.
- Direct invocation with `ambxst run shortcuts` and suggested personal bind `SUPER + /`.
