# Project instructions

## Mandatory context

- Read `REQUIREMENTS.md` completely before analyzing or changing code.
- Treat this repository as the only source of truth for the Ambxst keyboard-shortcuts overlay.
- Treat `src/modules/widgets/shortcuts/` as the canonical overlay implementation and `patches/ambxst-integration.patch` as the canonical shared-file integration.
- Treat the resolved Ambxst source (commonly `$HOME/.local/src/ambxst`) only as an external inspection, installation, and test target. Never develop the overlay directly in that tree.
- Treat the user's Ambxst dotfiles only as declarative configuration. Do not place project sources, scripts, patches, tests, documentation, experiments, or backups there.
- Inspect the installed Ambxst implementation before changing integration points. Do not assume file names or architecture from the requirements document.

## Working rules

- Before editing or deploying, inspect Git status, the active branch, repository roots, and the real target of `~/.config/ambxst`.
- Resolve the Ambxst target in this order: explicit script argument, `AMBXST_SOURCE_DIR`, `${XDG_DATA_HOME:-$HOME/.local/share}/ambxst/shell_repo`, then `$HOME/.local/src/ambxst`. Reject unsafe or non-Ambxst roots.
- Develop, validate, review, and version changes in this repository first. Deploy only through an explicit, deliberate installation step.
- Preserve all pre-existing user changes. Never stash, discard, reset, clean, overwrite, commit, tag, or push them without explicit approval.
- Before reloading Ambxst/Hyprland or applying changes to the live configuration, confirm a recent Timeshift snapshot or Git checkpoint exists. If neither exists, stop.
- Never make `scripts/install.sh` or `scripts/uninstall.sh` reload Ambxst, restart Quickshell, or modify `binds.json`.
- Reuse Ambxst's overlay, state-management, theming, animation, focus, and shortcut patterns.
- Keep `binds.json` as the runtime shortcut-data source of truth. Do not hardcode the user's shortcut list into QML.
- Do not change unrelated Ambxst behavior, audio, Bluetooth, Hyprland, Plasma, Yazi, packages, backups, or `.orig` files.
- Prefer the smallest coherent integration and introduce no runtime dependency or background service.
- Keep user-facing labels in neutral/Chilean Spanish. Internal identifiers may remain in English when consistent with Ambxst.
- Keep `references/` local, optional, and ignored by Git; its absence must never block work.
- `SUPER + F1` registration and changes to `binds.json` belong to a later phase and are not authorized yet.

## Deployment workflow

1. Change canonical files under `src/` and, when necessary, regenerate the focused patch under `patches/`.
2. Run `scripts/verify.sh [ambxst-target]` and the project tests.
3. Review and version the project changes here.
4. Run `scripts/install.sh [ambxst-target]` only with explicit deployment authorization.
5. Reload Ambxst separately and only with explicit authorization and a confirmed safety checkpoint.

Use `scripts/uninstall.sh [ambxst-target]` to remove only a pristine installation made from this project. It must reject locally modified installed files.
Both install and uninstall remain transactional through their final verification. A rollback must preserve concurrently modified files, report any operation it cannot safely undo, and require manual recovery instead of hiding a partial rollback.

## Validation

- Validate JSON parsing, empty/error states, enabled and layout-specific bindings, hardware-event exclusion, alternatives, family compaction, long combinations, toggle behavior, focus, keyboard navigation, scrolling, and multi-monitor placement.
- Validate shell behavior through Ambxst's discovered workflow; do not invent commands.
- Verify the integration patch affects only `modules/services/Visibilities.qml`, `modules/services/GlobalShortcuts.qml`, and `shell.qml`.
- After implementation, show the focused project diff, checks performed, remaining limitations, and exact deployment files.

## Definition of done

- Every acceptance criterion in `REQUIREMENTS.md` is satisfied or explicitly marked unresolved/deferred.
- The canonical overlay reads active shortcuts dynamically and never modifies `binds.json`.
- Installation and uninstallation are safe, idempotent, scoped, and never reload the session.
- Ambxst starts or reloads without overlay-attributable QML errors when runtime validation is authorized.
- Existing Ambxst panels, audio, Bluetooth, and shortcuts continue working.
