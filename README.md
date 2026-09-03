# Ambxst Shortcuts Overlay

Development workspace for a native Ambxst keyboard-shortcuts cheat sheet.

The project documentation stays separate from the user's dotfiles. The VS Code workspace exposes the real Ambxst configuration as a second root so Codex can inspect and modify the integration target without mixing project files into `~/.dotfiles`.

## Start

Place this directory directly under a folder in your home directory, for example:

```text
~/Projects/ambxst-shortcuts-overlay
```

Then open:

```text
ambxst-shortcuts-overlay.code-workspace
```

The workspace uses a relative path that expects the project directory to be exactly two levels below the home directory, such as `~/Projects/ambxst-shortcuts-overlay` or `~/Proyectos/ambxst-shortcuts-overlay`.

If the project directory is ever moved or renamed, the relative path to the Ambxst configuration root inside `ambxst-shortcuts-overlay.code-workspace` will stop resolving. Update the `path` value for the second folder entry in that file to match the new location before reopening the workspace.

## Files

- `AGENTS.md`: persistent instructions automatically loaded by Codex.
- `REQUIREMENTS.md`: product behavior, constraints, and acceptance criteria.
- `references/`: optional local visual material for consulting the current Ambxst design language. Git ignores this directory, so its contents are not versioned and are not required in a repository clone.
- `src/`: reserved for project-owned prototypes or isolated implementation files when appropriate.
- `ambxst-shortcuts-overlay.code-workspace`: multi-root workspace containing this project and the real Ambxst configuration.

## Important separation

- Project documents and experiments belong here. Optional visual references may be kept under `references/`; Git ignores them and the project must remain usable without them.
- Only the minimum final runtime configuration and QML integration belong in the dotfiles repository.
- Opening the workspace does not itself modify Ambxst.
