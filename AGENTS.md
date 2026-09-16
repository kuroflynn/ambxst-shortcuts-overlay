# Project instructions

## Mandatory context

- Read `REQUIREMENTS.md` completely before analyzing or changing code.
- Treat this repository as the only source of truth for the Ambxst keyboard-shortcuts overlay.
- Treat `v0.2.0` as the current release baseline: a native Ambxst mod (`kuroflynn.shortcuts-overlay`) declared for Ambxst `>=1.3.3 <1.4.0`, tested base `af9f8ad4...`. Treat `v0.1.1` (validated against Ambxst `1.2.6`) and `v0.1.0` as prior release baselines retained at their tags.
- Treat `payload/modules/widgets/shortcuts/` as the canonical overlay implementation, `patches/ambxst-integration.patch` as the canonical shared-file integration, and `ambxst.mod.json` as the package declaration.
- Treat the resolved Ambxst source (commonly `$HOME/.local/src/ambxst`) only as an external inspection and composition target. Never develop or write in that tree.
- Treat the user's Ambxst dotfiles only as declarative configuration. Do not place project sources, scripts, patches, tests, documentation, experiments, or backups there.
- Inspect the installed Ambxst implementation and its mod system (`docs/mods/`, `backend/pkg/mods/`) before changing integration points. Do not assume file names or architecture from the requirements document.

## Working rules

- Before editing or inspecting, check Git status, the active branch, repository roots, and the real target of `~/.config/ambxst`.
- Resolve the Ambxst target **only** through an explicit argument to `scripts/verify.sh` (`bash scripts/verify.sh /ruta/a/ambxst`). There is no automatic resolution: no `AMBXST_SOURCE_DIR`, no registry lookup, no fallback directory. Reject unsafe roots (absolute path, not `/`, not `$HOME`, must exist with the expected Ambxst/Git structure) and do not claim provenance or semantic compatibility from structural checks alone. `verify.sh --package-only` skips the target entirely.
- Develop, validate, review, and version changes in this repository first. Activation and removal are deliberate operations performed by the Ambxst mod manager, not by this project.
- Preserve all pre-existing user changes. Never stash, discard, reset, clean, overwrite, commit, tag, or push them without explicit approval.
- Before reloading Ambxst/Hyprland or activating/modifying the live configuration, confirm a recent Timeshift snapshot or Git checkpoint exists. If neither exists, stop.
- This project never installs, uninstalls, reloads Ambxst/Quickshell, or modifies `binds.json`. `scripts/verify.sh` is read-only and composes only under `/tmp`.
- Reuse Ambxst's overlay, state-management, theming, animation, focus, and shortcut patterns.
- Keep `binds.json` as the runtime shortcut-data source of truth. Do not hardcode the user's shortcut list into QML.
- Do not change unrelated Ambxst behavior, audio, Bluetooth, Hyprland, Plasma, Yazi, packages, backups, or `.orig` files. Never touch pre-existing v0.1.1 recovery material.
- Prefer the smallest coherent integration and introduce no runtime dependency or background service.
- Keep user-facing labels in neutral/Chilean Spanish. Internal identifiers may remain in English when consistent with Ambxst.
- Keep `references/` local, optional, and ignored by Git; its absence must never block work.
- Expose the overlay through `ambxst run shortcuts`. The suggested `SUPER + /` bind belongs to the user's personal configuration and must never be created, changed, or removed by this project. After removing the mod, tell the user to remove the personal bind manually if it is no longer wanted.
- The manifest declares exactly two `overlay` operations and one `patch`, no `replace: true`, no `expectedSha256`, and `testedBaseCommits` limited to commits actually validated against the current release.

## Deployment workflow

1. Change canonical files under `payload/` and, when necessary, update `ambxst.mod.json` and the focused patch under `patches/`.
2. Run `scripts/verify.sh [ambxst-target]` and the project tests (`bash tests/run.sh`).
3. Review and version the project changes here.
4. Let the user activate the mod through the Ambxst mod manager (`ambxst mods ...`) only with explicit deployment authorization.
5. Reload Ambxst separately and only with explicit authorization and a confirmed safety checkpoint.

`verify.sh` validates the package structure, the manifest against the vendored `docs/mods/manifest.schema.json` and the backend runtime checks (`scripts/manifest_validate.py`), the fixed package policy, patch scope, payload syntax, and — when given an Ambxst tree — composes the mod in `/tmp` via `scripts/compose.py` without writing to the live tree. `verify.sh` owns an exact, fresh `mktemp -d` generation directory under `/tmp`, passes it explicitly to `compose.py`, and cleans only that exact path (no logs/grep/patterns). The layout engine preserves git-archive file modes (executables `0755`) and aborts, never succeeding, when `git apply --3way` fails without unmerged files. Targets are validated with `git rev-parse`, so linked Git worktrees are accepted; an empty target argument is a usage error (only `--package-only` omits the destination). The composition engine also checks that the target tree's own `docs/mods/manifest.schema.json` byte-matches the vendored copy (drift guard). Run the suite with `PYTHONDONTWRITEBYTECODE=1` so no `scripts/__pycache__` is produced. There is no `install.sh`/`uninstall.sh` in `v0.2.0`; the legacy installer lives at tag `v0.1.1`.

## Validation

- Validate JSON parsing, empty/error states, enabled and layout-specific bindings, hardware-event exclusion, alternatives, family compaction, long combinations, toggle behavior, focus, keyboard navigation, scrolling, and multi-monitor placement.
- Validate shell behavior through Ambxst's discovered workflow; do not invent commands.
- Verify the integration patch affects only `modules/services/Visibilities.qml`, `modules/services/GlobalShortcuts.qml`, and `shell.qml`.
- Verify the manifest against `docs/mods/manifest.schema.json` and the manager's runtime checks in `backend/pkg/mods/` (no `replace: true` without `expectedSha256`, verbatim patch with three-way-merge fallback, tested-base recording).
- After implementation, show the focused project diff, checks performed, remaining limitations, and the exact package contents.

The `v0.1.0` runtime baseline was verified on Ambxst `1.2.6`: real install, uninstall and reinstall; repeated toggle and `Esc` close; scrolling and keyboard navigation; placement on both monitors according to focus; and mutual exclusion with other overlays.

The `v0.1.1` runtime baseline was verified on Ambxst `1.2.6` (T018–T021; **DEPRECATED since v0.2.0**, superseded by `docs/qa/v0.2.0/REPORT.md`): migration install from the v0.1.0 installation, reload, repeated toggle and `Esc` close, scrolling and keyboard navigation, placement on both monitors, overlay coexistence/exclusion with Dashboard, lock/unlock, and suspend/wake. T020-4 (live layout switch with the overlay open) was not executed: the overlay keeps pointer and focus while open, making the layout selector unreachable; that is not an overlay failure.

The `v0.2.0` native-mod baseline is verified structurally (manifest, composition in `/tmp`, verbatim patch on `af9f8ad4...`) and its runtime smoke validation was completed on Ambxst `1.3.3`; results are documented in `docs/qa/v0.2.0/REPORT.md` (verdict: ready).

## Definition of done

- Every acceptance criterion in `REQUIREMENTS.md` is satisfied for the release being delivered.
- The canonical overlay reads active shortcuts dynamically and never modifies `binds.json`.
- The manifest is schema-valid, scoped, and `replace`-free; the patch affects only the three shared files.
- The verifier and all tests pass with no writes to the live Ambxst tree.
- Ambxst starts or reloads without overlay-attributable QML errors when runtime validation is authorized.
- Existing Ambxst panels, audio, Bluetooth, and shortcuts continue working.