# Changelog

## [v0.2.0] - 2026-09-12

- Rebuilt the package as a native Ambxst mod (`kuroflynn.shortcuts-overlay`, manifest `ambxst.mod.json`, API 1, `ambxst >=1.3.3 <1.4.0`, MIT). No overlay behavior or design changes; the v0.1.1 `ShortcutsOverlay.qml`/`ShortcutData.js` content and the focused integration patch are preserved.
- Moved the canonical overlay from `src/modules/widgets/shortcuts/` to `payload/modules/widgets/shortcuts/`. The patch now ships as a `patch` operation; both overlay targets are absent from the tested base, so no `replace: true` is used.
- Removed the legacy installer (`scripts/install.sh`, `uninstall.sh`, `common.sh`, `gen_candidate`) from this branch; it remains available at tag `v0.1.1`. `assets`/activation/removal are handled by the Ambxst mod manager, never by this project.
- Rewrote `scripts/verify.sh` as a read-only native-package verifier: manifest constraints (schema, fixed three-operation layout, no `replace: true`/`expectedSha256`, safe payload paths, recorded range and tested base), payload presence, patch scope (`Visibilities.qml`, `GlobalShortcuts.qml`, `shell.qml`), payload/Bash syntax, `qmllint`, and, when given an Ambxst tree, manager-style composition in `/tmp` only.
- Added `tests/manifest.test.py` (87 checks) and `tests/composition.test.py` (base export, overlay copy, verbatim patch, byte-identical payloads, read-only delivered tree); rewrote `tests/verify.test.sh` as mutation tests for the new verifier; dropped legacy installer tests and fixtures; adapted `run.sh`, the JS/py test paths, and `.gitignore`.
- Compatibility recorded as tested on Ambxst base `af9f8ad4...` (tag `1.3.3`); patch applies verbatim there. Native activation and real-session runtime validation completed in `docs/qa/v0.2.0/REPORT.md` (verdict: ready).

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
- Real-session runtime validation on Ambxst 1.2.6: T018 PASS, T019-A PASS, T019-B PASS, T020-1/2/3 PASS, T020-4 NOT EXECUTED (layout selector unreachable with the overlay open), T021-A/B/C PASS (overlay coexistence, lock/unlock, suspend/wake). See docs/qa/v0.1.1/REPORT.md adenda J. **DEPRECATED since v0.2.0:** T018–T021 must not be reused; the v0.2.0 native smoke QA lives in `docs/qa/v0.2.0/REPORT.md`.

## [v0.1.0] - 2026-09-04

- Native keyboard-shortcuts overlay for Ambxst.
- Dynamic, read-only loading from `binds.json`.
- Shortcut grouping, deduplication, and numbered-family compaction.
- Responsive design with scrolling, keyboard navigation, and multi-monitor support.
- Transactional installation and uninstall with safe rollback behavior.
- Automated parser and transactional-script tests.
- Direct invocation with `ambxst run shortcuts` and suggested personal bind `SUPER + /`.
