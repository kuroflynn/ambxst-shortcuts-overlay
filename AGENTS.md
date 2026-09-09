# Project instructions

## Mandatory context

- Read `REQUIREMENTS.md` completely before analyzing or changing code.
- Treat this repository as the only source of truth for the Ambxst keyboard-shortcuts overlay.
- Treat `v0.1.1`, validated against Ambxst `1.2.6` (isolated hardening and real-session runtime), as the current release baseline. Treat `v0.1.0` as the first release baseline.
- Treat `src/modules/widgets/shortcuts/` as the canonical overlay implementation and `patches/ambxst-integration.patch` as the canonical shared-file integration.
- Treat the resolved Ambxst source (commonly `$HOME/.local/src/ambxst`) only as an external inspection, installation, and test target. Never develop the overlay directly in that tree.
- Treat the user's Ambxst dotfiles only as declarative configuration. Do not place project sources, scripts, patches, tests, documentation, experiments, or backups there.
- Inspect the installed Ambxst implementation before changing integration points. Do not assume file names or architecture from the requirements document.

## Working rules

- Before editing or deploying, inspect Git status, the active branch, repository roots, and the real target of `~/.config/ambxst`.
- Resolve the Ambxst target in this order: explicit script argument, `AMBXST_SOURCE_DIR`, `${XDG_DATA_HOME:-$HOME/.local/share}/ambxst/shell_repo`, then `$HOME/.local/src/ambxst`. Reject unsafe roots and roots missing the expected Ambxst/Git structure; do not claim provenance or semantic compatibility from structural checks alone.
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
- Expose the overlay through `ambxst run shortcuts`. The suggested `SUPER + /` bind belongs to the user's personal configuration and must never be created, changed, or removed by `install.sh` or `uninstall.sh`.
- After uninstalling, tell the user to remove the personal bind manually if it is no longer wanted.

## Deployment workflow

1. Change canonical files under `src/` and, when necessary, regenerate the focused patch under `patches/`.
2. Run `scripts/verify.sh [ambxst-target]` and the project tests.
3. Review and version the project changes here.
4. Run `scripts/install.sh [ambxst-target]` only with explicit deployment authorization.
5. Reload Ambxst separately and only with explicit authorization and a confirmed safety checkpoint.

Use `scripts/uninstall.sh [ambxst-target]` to remove only a pristine installation made from this project. It must reject locally modified installed files.
Both install and uninstall remain transactional through their final verification. Retain overlay inodes and staging hardlinks under `.ambxst-shortcuts-recovery/`; never automatically purge them based on content checks. Use exact destinations and pinned Linux directory descriptors, reject symbolic deployment ancestors and serialize cooperating deployments. Preserve ambiguous content and report unsafe recovery operations explicitly. The concurrency contract and its same-permission relocation/shared-file/crash limits are defined in REQUIREMENTS.md and README.md; do not claim absolute isolation or immutable backups.

## Validation

- Validate JSON parsing, empty/error states, enabled and layout-specific bindings, hardware-event exclusion, alternatives, family compaction, long combinations, toggle behavior, focus, keyboard navigation, scrolling, and multi-monitor placement.
- Validate shell behavior through Ambxst's discovered workflow; do not invent commands.
- Verify the integration patch affects only `modules/services/Visibilities.qml`, `modules/services/GlobalShortcuts.qml`, and `shell.qml`.
- After implementation, show the focused project diff, checks performed, remaining limitations, and exact deployment files.

The `v0.1.0` runtime baseline has already been verified on Ambxst `1.2.6`: real install, uninstall and reinstall; repeated toggle and `Esc` close; scrolling and keyboard navigation; placement on both monitors according to focus; and mutual exclusion with other overlays.

The `v0.1.1` runtime baseline is verified on Ambxst `1.2.6`: migration install from the v0.1.0 installation, reload, repeated toggle and `Esc` close, scrolling and keyboard navigation, placement on both monitors, overlay coexistence/exclusion with Dashboard, lock/unlock, and suspend/wake. T020-4 (live layout switch with the overlay open) was not executed: the overlay keeps pointer and focus while open, making the layout selector unreachable; that is not an overlay failure.

## Definition of done

- Every acceptance criterion in `REQUIREMENTS.md` is satisfied for the release being delivered.
- The canonical overlay reads active shortcuts dynamically and never modifies `binds.json`.
- Installation and uninstallation are safe, idempotent, scoped, and never reload the session.
- Ambxst starts or reloads without overlay-attributable QML errors when runtime validation is authorized.
- Existing Ambxst panels, audio, Bluetooth, and shortcuts continue working.
