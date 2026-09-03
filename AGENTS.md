# Project instructions

## Mandatory context

- Read `REQUIREMENTS.md` completely before analyzing or changing code.
- Treat this repository as the design and development workspace for the Ambxst keyboard-shortcuts overlay.
- Treat the Ambxst folder included in the VS Code workspace as an external integration target. Do not add project documentation, experiments, backups, or unrelated files to the dotfiles repository.
- Inspect the real Ambxst implementation before choosing integration points. Do not assume file names or architecture from the requirements document.

## Working rules

- Before editing, inspect Git status, the active branch, repository root, and the real target of `~/.config/ambxst`.
- Before reloading Ambxst/Hyprland or applying changes to the live `~/.config/ambxst`, confirm a recent Timeshift snapshot or a git checkpoint of the dotfiles exists. If neither exists, stop and ask the user to create one first — a bad reload must not risk an unbootable or broken session.
- Preserve all pre-existing user changes. Never stash, discard, revert, overwrite, commit, tag, or push them without explicit approval.
- Before the first implementation edit, report the intended files and explain briefly why each one is needed.
- Reuse Ambxst's existing overlay, state-management, theming, animation, focus, and shortcut patterns whenever possible.
- Keep `binds.json` as the source of truth. Do not hardcode the user's current shortcut list into QML.
- Do not change existing shortcuts, unrelated Ambxst behavior, Hyprland configuration, Plasma configuration, Yazi configuration, or system packages unless explicitly requested.
- Prefer the smallest coherent integration. Avoid introducing dependencies or a separate background service.
- Keep user-facing labels in Spanish, using neutral/Chilean Spanish register (no Argentine voseo forms like "corré" or "podés"). Internal identifiers, code symbols, and file names may remain in English when consistent with Ambxst.
- If the installed Ambxst version contradicts this document, stop and describe the conflict before proceeding.

## Validation

- Validate JSON parsing, empty/error states, toggle behavior, focus handling, keyboard navigation, scrolling, and multi-monitor placement.
- Use Ambxst's existing reload or development workflow after discovering it from the repository. Do not invent commands.
- After implementation, show the focused diff, the checks performed, any remaining limitations, and the exact files intended for deployment.

## Definition of done

- Every acceptance criterion in `REQUIREMENTS.md` is satisfied or explicitly marked as unresolved.
- The overlay reads the active shortcuts dynamically and does not modify `binds.json`.
- The shell starts and reloads without QML errors.
- Existing Ambxst panels and shortcuts continue working.
