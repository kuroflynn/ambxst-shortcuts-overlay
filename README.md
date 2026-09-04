# Ambxst Shortcuts Overlay

<p align="center">
  <strong>Native shortcut reference for Ambxst</strong><br>
  <code>v0.1.0</code> · <code>Ambxst 1.2.6</code> · <code>SUPER + /</code>
</p>

![Ambxst Shortcuts Overlay showing active shortcuts grouped in three responsive columns](docs/assets/shortcut-overlay-view.png)

A fast, read-only overlay for checking active keyboard shortcuts without leaving the desktop or opening Ambxst settings.

This repository is the only editable source of truth. The Ambxst source tree is an installation and test target, while dotfiles remain declarative configuration only.

## Highlights

- Reads the active `binds.json` dynamically instead of embedding a fixed shortcut list.
- Groups, deduplicates, and compacts shortcuts into a responsive, scrollable layout.
- Follows keyboard focus across monitors and closes with `Esc`.
- Integrates with Ambxst's native theme, overlays, and mutual-exclusion behavior.
- Provides transactional, reversible installation with no new runtime dependency.

## Layout

```text
src/modules/widgets/shortcuts/
    ShortcutsOverlay.qml
    ShortcutData.js
patches/
    ambxst-integration.patch
docs/assets/
    shortcut-overlay-view.png
scripts/
    common.sh
    install.sh
    uninstall.sh
    verify.sh
tests/
    shortcut-data.test.js
    transactional-scripts.test.sh
    fixtures/
CHANGELOG.md
```

- `src/` contains the canonical overlay implementation.
- `patches/ambxst-integration.patch` contains only the required changes to Ambxst's shared files.
- `scripts/` provides checked, scoped installation, verification, and removal.
- `tests/` validates parsing and model construction without a running Ambxst session.
- `references/` may contain optional local visual references. It is ignored by Git and is never required.

## Workspace and external roots

The tracked VS Code workspace contains only this project (`.`), so a clone does not depend on the original machine's directory layout. If local inspection benefits from extra roots, create `ambxst-shortcuts-overlay.local.code-workspace`; that machine-specific file is ignored without changing the existing `references/*` rule.

- `$HOME/.local/src/ambxst` is the portable fallback installation and runtime-test target only.
- Ambxst dotfiles, wherever the user keeps them, remain declarative configuration only.

Do not develop directly in either external tree, and do not copy this project into dotfiles.

## Target resolution

All three scripts resolve and validate the Ambxst source in the same order:

1. The optional explicit argument: `scripts/verify.sh /absolute/path/to/ambxst`.
2. `AMBXST_SOURCE_DIR`.
3. The single absolute path stored in `${XDG_DATA_HOME:-$HOME/.local/share}/ambxst/shell_repo`.
4. `$HOME/.local/src/ambxst` as a portable fallback.

The selected path must exist, be absolute, be the root of a Git worktree, and contain the expected Ambxst files. Empty or relative values, `/`, the complete home directory, malformed registry files, and unrelated repositories are rejected. An explicit argument always overrides environment, registry, and fallback values.

## Use

Open or close the installed overlay directly with:

```bash
ambxst run shortcuts
```

The suggested personal bind is `SUPER + /`. It toggles the overlay, while `Esc` closes it from inside the panel. The bind belongs to the user's Ambxst configuration: `scripts/install.sh` and `scripts/uninstall.sh` never create, change, or remove it. After uninstalling the overlay, remove the personal bind manually if it is no longer wanted.

## Verify

Verification is read-only:

```bash
scripts/verify.sh
scripts/verify.sh /path/to/ambxst
```

It checks project structure, script and QML/JavaScript syntax, parser fixtures, patch scope, patch applicability, installation state, and installed-file identity.

`verify.sh` performs no writes. The destructive-failure simulations are separate and operate only in a fresh temporary directory:

```bash
tests/transactional-scripts.test.sh
```

## Install deliberately

```bash
scripts/install.sh
scripts/install.sh /path/to/ambxst
```

Installation copies the two canonical source files and applies the focused integration patch. Its rollback remains armed until final verification succeeds. If rollback sees a concurrent modification or cannot reverse the patch cleanly, it preserves the affected files and reports the exact manual-recovery scope instead of overwriting or hiding the failure. It refuses partial, ambiguous, or locally modified states. It never changes `binds.json` and never reloads or restarts Ambxst.

## Remove deliberately

```bash
scripts/uninstall.sh
scripts/uninstall.sh /path/to/ambxst
```

Removal first verifies that the installed files exactly match this project, reverses only the integration patch, and deletes only those two known files. Its rollback remains armed through final verification and will not overwrite a file created or modified concurrently. Manually modified installations and unsafe rollback states are reported for manual recovery. No reload is performed.

## Version `v0.1.0`

The release has been validated on Ambxst `1.2.6`, including:

- real installation, uninstall, and reinstall;
- repeated opening and closing, including closing with `Esc`;
- scrolling and keyboard navigation;
- placement on both monitors according to focus;
- mutual exclusion with other overlays;
- automated parser and transactional-script tests.

The independent project remains the sole canonical source. The Ambxst tree is only a deployment and runtime-validation target. Development and versioning happen here; deployment stays deliberate, and reload remains a separate authorized operation protected by a recent checkpoint.
