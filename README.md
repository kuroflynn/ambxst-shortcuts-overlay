# Ambxst Shortcuts Overlay

<p align="center">
  <strong>Native shortcut reference for Ambxst</strong><br>
  <code>v0.1.1 (release)</code> · <code>Ambxst 1.2.6</code> · <code>SUPER + /</code>
</p>

![Ambxst Shortcuts Overlay showing active shortcuts grouped in three responsive columns](docs/assets/shortcut-overlay-view.png)

A fast, read-only overlay for checking active keyboard shortcuts without leaving the desktop or opening Ambxst settings.

This repository is the only editable source of truth. The Ambxst source tree is an installation and test target, while dotfiles remain declarative configuration only.

## Highlights

- Reads the active `binds.json` dynamically instead of embedding a fixed shortcut list.
- Groups, deduplicates, and compacts shortcuts into a responsive, scrollable layout.
- Follows keyboard focus across monitors and closes with `Esc`.
- Integrates with Ambxst's native theme, overlays, and mutual-exclusion behavior.
- Provides scoped deployment with durable recovery and no new overlay runtime dependency.

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
    gen_candidate
    install.sh
    uninstall.sh
    verify.sh
tests/
    run.sh
    shortcut-data.test.js
    hardening.test.js
    verify.test.sh
    transactional-scripts.test.sh
    deployment.test.py
    qml.test.py
    full-tree-cycle.test.py
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

The selected path must exist, be absolute, be the root of a Git worktree, and contain the expected Ambxst files. Empty or relative values, `/`, the complete home directory, malformed registry files, and roots missing the expected structure are rejected. A path containing a line feed or carriage return is rejected before any resolution or write, whatever its source (argument, `AMBXST_SOURCE_DIR`, registry or fallback); spaces, tabs and UTF-8 remain valid. These are structural checks, not proof of project identity or provenance; structurally matching forks and local branches remain allowed. Patch applicability is an additional textual check, not a semantic compatibility guarantee. An explicit argument always overrides environment, registry, and fallback values.

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
bash tests/run.sh
# Optional full-tree validation; reads this repository and deploys only to /tmp:
python3 tests/full-tree-cycle.test.py /absolute/path/to/ambxst-git
```

## Install deliberately

```bash
scripts/install.sh
scripts/install.sh /path/to/ambxst
```

Installation copies the two canonical source files and applies the focused integration patch. Its rollback remains armed until final verification succeeds. Prepared overlay inodes retain a hardlink in the recovery directory. If rollback detects a concurrent modification or cannot reverse the patch cleanly, it preserves ambiguous files and reports manual recovery. See the concurrency limits below. It refuses partial, ambiguous, or locally modified states. It never changes `binds.json` and never reloads or restarts Ambxst.

## Remove deliberately

```bash
scripts/uninstall.sh
scripts/uninstall.sh /path/to/ambxst
```

Removal first verifies that the installed files exactly match this project, reverses only the integration patch, and moves the two runtime files into durable recovery. Its rollback remains armed through final verification; exact-destination restoration refuses an existing destination. Manually modified installations and unsafe rollback states are reported for manual recovery. No reload is performed.

## v0.1.1 hardening and recovery policy

`v0.1.1` is released. **v0.1.1 probado contra Ambxst 1.2.6** both in isolated archive copies and on the real installation (migration from v0.1.0, reload, and runtime T018–T021). Applying the patch to a later version does not establish semantic compatibility. The [QA report](docs/qa/v0.1.1/REPORT.md) records tests, limitations, and the runtime results; the [v0.1.0 audit](docs/qa/v0.1.0/REPORT.md) remains unchanged.

Runtime results on the real Ambxst `1.2.6` session: **T018 PASS** (toggle and `Esc`), **T019-A PASS** (scrolling, keyboard navigation, dual-monitor focus), **T019-B PASS** (distinct monitor scales), **T020-1/2/3 PASS** (live `binds.json` refresh and malformed-JSON error containment), **T020-4 NOT EXECUTED** (the layout selector is not reachable while the overlay keeps pointer/focus, so no `onCompositorLayoutChanged` event existed to evaluate; not an overlay failure), **T021-A PASS** (coexistence and mutual exclusion with Dashboard), **T021-B PASS** (lock/unlock), **T021-C PASS** (suspend/wake). See REPORT.md adenda J.

Deployments require Linux `/proc`, Bash, Git, GNU coreutils supporting `ln -T` and `mv --no-copy -T --update=none-fail`, and `flock` (util-linux). Tested versions: coreutils 9.11 and util-linux 2.42.3. No package is installed by these scripts. Node and Python 3 are development/verification tools; the isolated visual probe also needs Qt 6 `qmltestrunner`.

Install and uninstall deliberately retain `TARGET_ROOT/.ambxst-shortcuts-recovery/`:

- `install.XXXXXX/` holds prepared files and their hardlinks. Successful installation leaves `ShortcutsOverlay.qml` and `ShortcutData.js` there.
- `uninstall.XXXXXX/` holds the retired runtime inodes, including writes through an already-open descriptor after final verification or process exit.
- Failed preparation/rollback can retain partial staging files (`.NAME.install.XXXXXX`) and `retired-NAME` files in the reported transaction directory. These are documented recovery material, never automatically purged.
- An idempotent second install/uninstall creates no new transaction directory. Completed cycles retain recovery entries intentionally; repeated cycles accumulate them.

Recovery links refer to mutable inodes: they are **not immutable backups**. Neither elapsed time nor matching checksums proves that an open writer has finished. Cleanup is manual, after stopping writers, reviewing retained contents and securing any needed independent backup. Never edit a recovery hardlink assuming it is independent of the installed file. Install/uninstall do not garbage-collect old recovery entries.

All three entrypoints reject symbolic links (including dangling links) in deployment ancestors and require regular shared/overlay files. Deployment uses open directory descriptors for overlay writes and exact-destination, non-overwriting publication/restoration. It rechecks physical locations and serializes cooperating deployments using `flock`. Replacing an ancestor pathname with a symlink does not redirect descriptor-based leaf operations to the symlink destination.

Staging never re-opens the temporary pathname for a truncating write. The candidate name is generated without creating a file (`scripts/gen_candidate`), and the inode is created by a single atomic exclusive open (`set -o noclobber` + `exec {fd}>`, `O_WRONLY|O_CREAT|O_EXCL`). A name already occupied by anything (regular file, symlink, directory, FIFO) is abandoned and retried, never truncated, deleted or followed, and never blocks the install on a special node. `install.sh` writes and verifies the prepared content only through that already-open descriptor; a later substitution of the temporary name cannot redirect that write. `cat`, `chmod` and a name-still-resolves-to-the-opened-object identity check are a single verified preparation: any failure aborts without publishing.

This is not a security boundary against arbitrary processes with the same permissions. Such a process can move an opened directory outside the root between checks, alter mounts, delete the recovery itself or change shared files while Git applies the patch. Git patch checks and rollback do not provide an atomic snapshot of all shared files or protection from arbitrary in-place writers. Detected unsafe states stop with manual-recovery diagnostics; abrupt termination or power loss can still require manual repair. No crash-durability/fsync guarantee is made. See the [design comparison](docs/qa/v0.1.1/DESIGN.md).

The exact deployment files remain:

```text
modules/widgets/shortcuts/ShortcutsOverlay.qml
modules/widgets/shortcuts/ShortcutData.js
modules/services/Visibilities.qml
modules/services/GlobalShortcuts.qml
shell.qml
```

The integration patch is unchanged. Recovery directories are the additional documented footprint. A modified installation or an installation from a different source version is refused; upgrading the live v0.1.0 installation requires a separately reviewed deployment plan.

`verify.sh` prefers `qmllint6`, then `/usr/lib/qt6/bin/qmllint` on Arch, then `qmllint` from PATH. It prints the exact path/version. This validation used `/usr/lib/qt6/bin/qmllint` 6.11.2; the PATH fallback here is Qt 5's `qmllint` 1.0. Unresolved `qs.*`/Quickshell context warnings can occur outside the running shell. A successful exit checks syntax/static analysis only and never means runtime PASS. Missing lint is reported explicitly.

The parser accepts JavaScript arrays and Qt 6 `V4Sequence` lists, bounds list sizes and construction work, contains malformed-data errors, and labels the displayed count as **rows of shortcuts** after compaction. Limits are 2,097,152 JSON code units, 4,096 custom entries/object keys, 64 keys/actions/layouts per binding/action, 32 modifiers, 32,768 code units per text, argument depth 24 and a shared 100,000-unit work budget (visited values, text and combination comparisons). Exceeding a limit shows an error instead of silently truncating. These bounds target JSON and trusted QML models, not arbitrary JavaScript getters/proxies. Long labels wrap within the row.

## Version `v0.1.0`

The release has been validated on Ambxst `1.2.6`, including:

- real installation, uninstall, and reinstall;
- repeated opening and closing, including closing with `Esc`;
- scrolling and keyboard navigation;
- placement on both monitors according to focus;
- mutual exclusion with other overlays;
- automated parser and transactional-script tests.

The independent project remains the sole canonical source. The Ambxst tree is only a deployment and runtime-validation target. Development and versioning happen here; deployment stays deliberate, and reload remains a separate authorized operation protected by a recent checkpoint.
