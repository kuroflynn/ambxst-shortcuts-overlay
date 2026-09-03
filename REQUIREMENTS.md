# Ambxst keyboard-shortcuts overlay

Status: Draft 0.2 — canonical-project migration
Target environment: Arch Linux, Hyprland, Quickshell, Ambxst  
Primary language: Spanish

## 0. Project architecture and current phase

- This repository is the independent project and the only editable source of truth.
- Canonical overlay files live under `src/`; the focused integration for Ambxst shared files lives under `patches/`.
- The resolved Ambxst source, with `$HOME/.local/src/ambxst` as portable fallback, is only an installation and runtime-test target. Development must not occur directly there.
- The user's Ambxst dotfiles remain declarative configuration and must not contain project files.
- Development, tests, review, and versioning happen here before deliberate installation.
- Installation and uninstallation must be scoped, idempotent, and must never reload Ambxst or restart Quickshell automatically.
- The scripts resolve their target, in order, from an explicit argument, `AMBXST_SOURCE_DIR`, `${XDG_DATA_HOME:-$HOME/.local/share}/ambxst/shell_repo`, or `$HOME/.local/src/ambxst`. The result must be an absolute, existing, validated Ambxst Git root and must reject dangerous broad roots.
- The tracked workspace contains only this project. Optional external roots belong in an ignored, machine-local workspace file.
- `references/` remains local, optional, ignored by Git, and unnecessary in a clone.
- Registration of `SUPER + F1` and every modification to `binds.json` are deferred to a later phase. Acceptance criterion 1 therefore remains explicitly unresolved in the current phase.

## 1. Purpose

Build a standalone keyboard-shortcuts cheat sheet integrated visually and functionally into Ambxst.

The user must be able to remember a single shortcut, open the overlay instantly, and consult the rest of the active shortcuts without navigating through the Dashboard, opening Ambxst settings, or using a terminal command.

This is a read-only reference surface. It is not a shortcut editor.

## 2. Current problem

Ambxst exposes shortcut configuration through its settings, but that interface is designed for administration rather than quick consultation. Hyprland can list bindings through command-line tools, but it does not provide the desired native visual overlay.

The current shortcut collection is already large enough that memorizing every combination is impractical. It includes Ambxst actions, window management, workspace navigation, scrolling layout actions, multimedia controls, brightness controls, and system actions.

## 3. User experience

### 3.1 Opening and closing

- `SUPER + F1` toggles the overlay.
- Pressing `SUPER + F1` while it is open closes it.
- `Esc` closes it immediately.
- Only one instance may be visible at a time.
- Opening it must not launch a terminal or a separate desktop application.
- It should follow Ambxst's existing convention for choosing the monitor on which an overlay appears, preferably the focused or active monitor.

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
- Inspect the installed schema before implementation. The supplied sample contains the top-level keys `ambxst`, `custom`, and `defaultAmbxstBinds`, but the implementation must follow the current runtime schema rather than assuming it is immutable.
- Never write to or normalize `binds.json` from the overlay.
- Do not use `defaultAmbxstBinds` as displayed active state when it differs from the user's current bindings.
- Show enabled active bindings only. Before writing any parsing code, determine and document how "enabled/active" is actually represented in the installed schema (e.g. an explicit flag, or precedence of `custom` over `ambxst` over `defaultAmbxstBinds`) — this must come from inspecting the real `binds.json` and/or the Ambxst model, not from assumption.
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
- Register a dedicated action or global shortcut using the current Ambxst shortcut infrastructure.
- Integrate the visual component into the same shell/overlay layer used by comparable Ambxst panels.
- Reuse the existing close-on-Escape and mutual-exclusion behavior if Ambxst provides it.
- Opening the shortcuts overlay should close or yield to incompatible overlays according to existing shell behavior.
- Do not alter the current behavior of Dashboard, Config, Launcher, Clipboard, Notes, Power Menu, Overview, or Tools.

The exact QML files and services to modify are intentionally not prescribed here. They must be selected after inspecting the installed Ambxst version and its established architecture.

## 7. Reliability and performance

- A missing, empty, malformed, or temporarily unreadable bindings file must not crash Quickshell or Ambxst.
- Show a concise empty/error state inside the panel when shortcut data cannot be loaded.
- Avoid spawning external processes on every render or row.
- Avoid network access and new runtime dependencies.
- Parsing, grouping, and sorting should complete quickly enough that opening feels immediate.
- Repeated toggling must not leak components, create duplicate shortcuts, or leave invisible focus-grabbing windows.
- Installation and uninstallation remain transactional until their final verification succeeds. Rollback operations must first confirm that their patch direction still applies and that project-owned files still match the canonical source.
- A concurrent modification during rollback must never be overwritten or deleted. Any unsafe or failed rollback operation must remain visible as a manual-recovery error naming the affected path; critical failures must not be suppressed.

## 8. Out of scope

- Editing, rebinding, enabling, or disabling shortcuts.
- Replacing Ambxst's existing Binds settings panel.
- Building a standalone GTK, Qt Widgets, Electron, web, or terminal application.
- Changing Hyprland bindings unrelated to registering the overlay toggle.
- Redesigning the Ambxst Dashboard.
- Modifying Yazi or Plasma configuration.
- Adding search, favorites, usage analytics, synchronization, or cloud services in the first version.

## 9. Acceptance criteria

The first version is accepted when all of the following are true:

1. `SUPER + F1` opens and closes the overlay reliably.
2. `Esc` closes it reliably.
3. The overlay appears as a native Ambxst surface on the appropriate monitor.
4. It reads the current active shortcuts dynamically rather than embedding the supplied sample list.
5. It shows the main Ambxst, window, workspace, layout, system, and multimedia groups.
6. Numbered workspace families are compacted into readable rows.
7. Equivalent alternative bindings are combined without losing information.
8. Lid-switch and other non-keyboard hardware events are not shown.
9. Long content remains usable through responsive columns and scrolling.
10. Invalid or missing shortcut data produces a contained error state and no shell crash.
11. Existing Ambxst panels, animations, and shortcuts continue working.
12. Ambxst starts or reloads without new QML errors or warnings attributable to the overlay.
13. The implementation introduces no new runtime dependency and performs no network access.
14. The final diff contains only the project documentation and the minimum required Ambxst integration files. Any exploratory prototype placed under `src/` during development stays inside this project workspace and is not part of the dotfiles diff; remove or clearly mark unused prototypes before final delivery so they don't get mistaken for integration files. Optional local visual material under `references/` remains ignored by Git and is not required in a repository clone.

## 10. Delivery workflow

1. Open `ambxst-shortcuts-overlay.code-workspace` in VS Code; it intentionally tracks only the project root.
2. Resolve and inspect the external Ambxst installation target. Add optional external roots only to an ignored machine-local workspace.
3. Read `AGENTS.md` and this document.
4. Inspect the installed Ambxst architecture and Git state without developing in that external tree.
5. Present the proposed canonical and integration files before editing.
6. Implement and validate incrementally in this repository.
7. Run `scripts/verify.sh`, then review and version the complete project diff.
8. Install deliberately with `scripts/install.sh` only after explicit approval.
9. Reload separately only after explicit approval and confirmation of a recent safety checkpoint.
10. Commit, tag, or push only after explicit user approval.

## 11. Known environment context

- The Ambxst configuration is maintained through the user's dotfiles repository.
- The expected tracked source is `~/.dotfiles/ambxst/.config/ambxst`.
- The expected runtime path is `~/.config/ambxst`; verify whether it is a symlink before editing.
- The portable fallback installation/test source tree is `$HOME/.local/src/ambxst`; it is not the overlay's source of truth and may be overridden through the documented resolution order.
- Canonical overlay development belongs only in this repository under `src/` and `patches/`.
- Current Ambxst configuration includes a sizeable `binds.json` with both built-in and custom bindings.
- The system uses Hyprland and Quickshell on Arch Linux.
- The external display is 2560×1440, and the laptop display is 2560×1600 with scaling; the panel must remain usable on both.
