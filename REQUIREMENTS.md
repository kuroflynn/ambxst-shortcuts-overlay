# Ambxst keyboard-shortcuts overlay (native mod)

Status: `v0.2.0` — native Ambxst mod (`kuroflynn.shortcuts-overlay`) declared against Ambxst `1.3.3`; composition and patch applicability verified on base `af9f8ad4...`.
Baseline: `v0.1.1` was the previous release, validated against Ambxst `1.2.6` (isolated hardening + real-session runtime). `v0.1.0` / `6ec3870` was the first release baseline. Defects are recorded in `docs/qa/v0.1.0/` and `docs/qa/v0.1.1/`.
Target environment: Arch Linux, Hyprland, Quickshell, Ambxst
Primary language: Spanish

## 0. Project architecture and current phase

- This repository is the independent project and the only editable source of truth.
- Canonical overlay files live under `payload/modules/widgets/shortcuts/`; the focused integration for Ambxst shared files lives under `patches/ambxst-integration.patch`. `ambxst.mod.json` describes the package.
- The resolved Ambxst source, commonly `$HOME/.local/src/ambxst`, is only an external inspection and composition target. Development must not occur directly there.
- The user's Ambxst dotfiles remain declarative configuration and must not contain project files.
- Development, tests, review, and versioning happen here before any activation through the Ambxst mod manager.
- Activation, deactivation, removal, and permission handling are performed by Ambxst's own mod manager (`ambxst mods ...`). This project never installs into, uninstalls from, or reloads the live Ambxst tree, and never modifies `binds.json`.
- `scripts/verify.sh` resolves its target **only** from an explicit argument (`--package-only` skips the target entirely); there is no automatic resolution via environment variables, registries, or fallback directories. The result must be an absolute, existing, Git worktree root with the expected Ambxst structure, must reject dangerous broad roots, and must carry a `docs/mods/manifest.schema.json` byte-identical to the vendored copy. Structural validation is not proof of identity/provenance; forks remain supported. Patch applicability does not demonstrate semantic compatibility with future versions.
- The tracked workspace contains only this project. Optional external roots belong in an ignored, machine-local workspace file.
- `references/` remains local, optional, ignored by Git, and unnecessary in a clone.
- The installed overlay is exposed as `ambxst run shortcuts` (a `shortcuts` global action registered by the mod's patch). The suggested `SUPER + /` bind belongs to the user's personal configuration and is never modified by this project; after removing the mod, the user removes that bind manually if it is no longer wanted.
- The former v0.1.1 installer (`scripts/install.sh`, `uninstall.sh`, `common.sh`, `gen_candidate`) and its recovery state are legacy and remain available at tag `v0.1.1`; pre-existing recovery material is left untouched.

## 1. Purpose

Build a native keyboard-shortcuts cheat sheet integrated visually and functionally into Ambxst.

The user must be able to remember a single shortcut, open the overlay instantly, and consult the rest of the active shortcuts without navigating through the Dashboard, opening Ambxst settings, or using a terminal command.

This is a read-only reference surface. It is not a shortcut editor.

## 2. Current problem

Ambxst exposes shortcut configuration through its settings, but that interface is designed for administration rather than quick consultation. Hyprland can list bindings through command-line tools, but it does not provide the desired native visual overlay.

The current shortcut collection is already large enough that memorizing every combination is impractical. It includes Ambxst actions, window management, workspace navigation, scrolling layout actions, multimedia controls, brightness controls, and system actions.

## 3. User experience

### 3.1 Opening and closing

- `ambxst run shortcuts` toggles the overlay directly.
- The configured personal shortcut `SUPER + /` toggles the overlay.
- Pressing `SUPER + /` while it is open closes it.
- `Esc` closes it immediately.
- Only one instance may be visible at a time.
- Opening it must not launch a terminal or a separate desktop application.
- It follows Ambxst's existing focus convention and appears on the focused monitor.

### 3.2 Visual presentation

- The overlay must look native to the installed Ambxst theme.
- Reuse existing theme tokens, typography, colors, borders, corner radii, shadows, blur, spacing, and animations instead of duplicating visual constants.
- Use a centered, clearly bounded panel above normal windows.
- The title is `Atajos de teclado`.
- The content should be scannable in a few seconds, with action descriptions visually separated from key combinations.
- Key combinations should appear as distinct keycaps or compact pills when compatible with Ambxst's design language.
- The layout must adapt to both the laptop display and the 2560×1440 external monitor without clipping.
- Prefer multiple balanced columns on wide screens and a scrollable layout when vertical space is insufficient.
- When available locally, material under `references/` may be consulted for the current Ambxst visual language, but it is optional and not a rigid mockup of the new overlay. Git ignores this directory, and its absence from a repository clone must not block development or implementation.

### 3.3 Content organization

Group shortcuts into human-readable sections derived from their action identifiers and meaning. The expected groups are:

1. Ambxst and applications
2. Windows and focus
3. Workspaces
4. Layout and columns
5. System and session
6. Multimedia and brightness

The exact number and placement of columns may change responsively, but the semantic grouping must remain clear.

## 4. Shortcut data

### 4.1 Source of truth

- Read the active configuration from `~/.config/ambxst/binds.json`, or from the existing Ambxst service/model that already represents that file.
- Prefer reusing an existing Ambxst model or service over parsing the file a second time.
- Never write to or normalize `binds.json` from the overlay.
- Do not use `defaultAmbxstBinds` as displayed active state when it differs from the user's current bindings.
- Show enabled active bindings only. The "enabled/active" representation must come from inspecting the real `binds.json` and/or the Ambxst model, not from assumption.
- Changes to `binds.json` must be reflected at least the next time the overlay opens. Live updating while open is desirable if the existing Ambxst data model supports it naturally.

### 4.2 Labels

- Prefer an existing localized or human-readable Ambxst label when available.
- Provide concise Spanish labels for known action identifiers.
- If an unknown future action appears, fall back safely to its configured name or identifier instead of omitting it or crashing.
- Normalize key names for display without changing their actual meaning. Examples: `ESCAPE` → `Esc`, `PERIOD` → `.`, `COMMA` → `,`, arrow keys → arrow glyphs where visually supported.
- Use a consistent modifier order: `SUPER`, `CTRL`, `ALT`, `SHIFT`, followed by the primary key.

### 4.3 Compaction and deduplication

The overlay should reduce noise without hiding useful alternatives.

- Compress `Workspace 1` through `Workspace 10` into one row such as `SUPER + 1…0`.
- If the bound series is incomplete (for example only workspaces 1 through 6 are bound), compact the contiguous range that exists instead of assuming all 10, e.g. `SUPER + 1…6`, and fall back to individual rows if the bound set is not a contiguous range starting at 1.
- Apply the same compaction, including the incomplete-series rule above, to moving a window to workspaces, moving silently, and moving columns when a numbered series exists.
- Combine equivalent actions that have several key combinations into one row. Example: focus up may show `SUPER + ↑` and `SUPER + CTRL + K` together.
- Keep alternative keyboard schemes visible when they are genuinely useful; do not silently discard them as duplicates.
- Exclude non-keyboard hardware events such as `switch:Lid Switch`, display-off-on-lid-close, and display-on-on-lid-open.
- Mouse bindings may appear in the window section with readable labels if they remain active.
- Dedicated multimedia and brightness keys should appear in their own compact section.

## 5. Interaction and accessibility

- The overlay is primarily read-only and keyboard-driven.
- `Esc` must work regardless of which internal item has focus.
- Scrolling must work with the mouse wheel or trackpad when content exceeds available space.
- If Ambxst already has a standard focus-trap or keyboard-navigation pattern, reuse it.
- Text and key labels must maintain adequate contrast using the active theme.
- Animations should be short and consistent with existing Ambxst overlays, with no distracting transitions.

## 6. State and integration

- Add a dedicated visibility state for the shortcuts overlay using Ambxst's existing global-state conventions.
- Register the `shortcuts` global action so it can be toggled with `ambxst run shortcuts`.
- Keep shortcut registration in the user's personal configuration; this project must never modify `binds.json`.
- Integrate the visual component into the same shell/overlay layer used by comparable Ambxst panels.
- Reuse the existing close-on-Escape and mutual-exclusion behavior if Ambxst provides it.
- Opening the shortcuts overlay should close or yield to incompatible overlays according to existing shell behavior.
- Do not alter the current behavior of Dashboard, Config, Launcher, Clipboard, Notes, Power Menu, Overview, or Tools.

The focused integration patch is limited to `modules/services/Visibilities.qml`, `modules/services/GlobalShortcuts.qml`, and `shell.qml`. Canonical overlay sources remain under this independent project's `payload/modules/widgets/shortcuts/` tree.

## 7. Reliability and performance

- A missing, empty, malformed, or temporarily unreadable bindings file must not crash Quickshell or Ambxst.
- Show a concise empty/error state inside the panel when shortcut data cannot be loaded.
- Avoid spawning external processes on every render or row.
- Avoid network access and new runtime dependencies.
- Parsing, grouping, and sorting should complete quickly enough that opening feels immediate.
- Repeated toggling must not leak components, create duplicate shortcuts, or leave invisible focus-grabbing windows.
- The parser accepts JavaScript arrays and Qt 6 `V4Sequence` lists, bounds list sizes and construction work, contains malformed-data errors, and labels the displayed count as rows of shortcuts after compaction. Limits are 2,097,152 JSON code units, 4,096 custom entries/object keys, 64 keys/actions/layouts per binding/action, 32 modifiers, 32,768 code units per text, argument depth 24 and a shared 100,000-unit work budget. Exceeding a limit shows an error instead of silently truncating. These bounds target JSON and trusted QML models, not arbitrary JavaScript getters/proxies. Long labels wrap within the row.
- The manifest declares no `replace: true`; both overlay targets are absent from the tested base, so the manager's overlay-add is a pure addition. This project does not install a `commands` entry and adds no background service.
- Composition assumes the manager's algorithm (base `git archive HEAD`, fixed init identity, overlay copies in manifest order, verbatim patch with a three-way-merge fallback) and only verifies it in `/tmp`; it never mutates the delivered tree.

## 8. Out of scope

- Editing, rebinding, enabling, or disabling shortcuts.
- Replacing Ambxst's existing Binds settings panel.
- Building a standalone GTK, Qt Widgets, Electron, web, or terminal application.
- Changing Hyprland bindings unrelated to registering the overlay toggle.
- Redesigning the Ambxst Dashboard.
- Modifying Yazi or Plasma configuration.
- Adding search, favorites, usage analytics, synchronization, or cloud services in this version.
- Operating the Ambxst mod manager (install/activate/remove); activation is a deliberate user action outside this project.
- Maintaining the v0.1.1 installer and recovery contract at runtime; it remains documented and retained at tag `v0.1.1`.

## 9. Acceptance criteria

The following criteria describe the `v0.1.0`/`v0.1.1` validation on Ambxst `1.2.6` (results in `docs/qa/v0.1.0/REPORT.md` and `docs/qa/v0.1.1/REPORT.md`, adenda J; T020-4 was not executed). For `v0.2.0`, the packaging criteria below replace the installer-centric ones and the runtime criteria remain pending for a native activation:

1. `SUPER + /` and `ambxst run shortcuts` open and close the overlay reliably (runtime: pending v0.2.0 activation).
2. `Esc` closes it reliably (runtime: pending v0.2.0 activation).
3. The overlay appears as a native Ambxst surface on the appropriate monitor (runtime: pending v0.2.0 activation).
4. It reads the current active shortcuts dynamically rather than embedding the supplied sample list.
5. It shows the main Ambxst, window, workspace, layout, system, and multimedia groups.
6. Numbered workspace families are compacted into readable rows.
7. Equivalent alternative bindings are combined without losing information.
8. Lid-switch and other non-keyboard hardware events are not shown.
9. Long content remains usable through responsive columns and scrolling.
10. Invalid or missing shortcut data produces a contained error state and no shell crash.
11. Existing Ambxst panels, animations, and shortcuts continue working (runtime: pending v0.2.0 activation).
12. Ambxst starts or reloads without new QML errors or warnings attributable to the overlay (runtime: pending v0.2.0 activation).
13. The implementation introduces no new runtime dependency and performs no network access.
14. `ambxst.mod.json` matches the schema: id `kuroflynn.shortcuts-overlay`, version `0.2.0`, API 1, `ambxst` `>=1.3.3 <1.4.0`, MIT, `testedBaseCommits` limited to genuinely validated commits (`af9f8ad4...`), no dependencies/conflicts/commands/settings, one read-only permission, two `overlay` operations plus one `patch`, and no `replace: true`.
15. Post-review, project-only validations: the manifest checker passes 119 checks against the vendored schema and the backend parity rules (exact `const` semantics — `true` never equals `1` — and `propertyNames`/`additionalProperties` apply even without `properties`); the composition test (69 checks) composes in `/tmp`, asserts byte-identical payloads, dead-hook hardening, three-way-merge fallback, concurrent-insertion resolution, abort on a `--3way` failure without unmerged files, executable-mode preservation, linked-worktree targets, and a read-only delivered tree; `verify.sh` (18 checks) rejects invalid manifests, `replace: true`, widened patch scope, broken payload/Bash, missing payloads, empty or invalid CLI usage, and never writes to the target.

## 10. Delivery workflow

1. Open `ambxst-shortcuts-overlay.code-workspace` in VS Code; it intentionally tracks only the project root.
2. Resolve and inspect the external Ambxst installation target. Add optional external roots only to an ignored machine-local workspace.
3. Read `AGENTS.md` and this document.
4. Inspect the installed Ambxst architecture, mod system (`docs/mods/`, `backend/pkg/mods/`), and Git state without developing in that external tree.
5. Present the proposed manifest, payload, and patch before editing.
6. Implement and validate incrementally in this repository (manifest → payload → patch → tests → docs).
7. Run `scripts/verify.sh`, then review and version the complete project diff.
8. Activate through the Ambxst mod manager only after explicit approval.
9. Reload Ambxst separately only after explicit approval and confirmation of a recent safety checkpoint.
10. Commit, tag, or push only after explicit user approval.

## 11. `v0.2.0` validation record

- Standard working tree verified; feature branch `feat/native-mod` created from `main`.
- `src/` moved to `payload/`; legacy installer scripts removed from the branch (retained at tag `v0.1.1`).
- Manifest, composition, verify mutations, adapter, and Qt `qmltestrunner` tests all pass project-locally.
- Patch applies verbatim to the `1.3.3` tree (`af9f8ad4...`); `modules/widgets/shortcuts/` is absent from the base.
- Activation, toggle, `Esc`, scrolling, dual-monitor, coexistence, lock/unlock, and suspend/wake runtime validation remains **pending** (not authorized in this phase).

## 12. Known environment context

- The Ambxst configuration is maintained through the user's dotfiles repository.
- The expected tracked source is `~/.dotfiles/ambxst/.config/ambxst`; the runtime path is `~/.config/ambxst`.
- The portable fallback composable base tree is `$HOME/.local/src/ambxst` (currently `1.3.3`, `af9f8ad4...`).
- Canonical overlay development belongs only in this repository under `payload/` and `patches/`, described by `ambxst.mod.json`.
- Current Ambxst configuration includes a sizeable `binds.json` with both built-in and custom bindings.
- The system uses Hyprland and Quickshell on Arch Linux.
- The external display is 2560×1440, and the laptop display is 2560×1600 with scaling; the panel must remain usable on both.
- Pre-existing v0.1.1 recovery material (`.ambxst-shortcuts-recovery/`) and any `*.orig` files in the Ambxst tree must never be touched by this project.