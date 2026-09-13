#!/usr/bin/env python3
"""Native-mod composition engine (parity with Ambxst backend/pkg/mods/manager.go).

Builds the packaged mod inside a throwaway directory under /tmp the same way
the backend builds generation trees:

  * exports the target HEAD as an object-less git worktree;
  * inits a fresh repo whose object store is linked to the target's via
    .git/objects/info/alternates (so --3way can always reach base blobs);
  * disables hooks completely: core.hooksPath -> <generation>/.git/unused-hooks
    (a directory that does not exist) plus --no-verify on every commit;
  * forces merge.conflictStyle=diff3, commit.gpgsign=false, core.autocrlf=false;
  * overlays refuse a destination that already exists unless the operation
    declares replace (already rejected at manifest level, but enforced here too);
  * patches apply with --check --whitespace=error-all, falling back to --3way,
    and finally to a resolve-of-added-blocks step that only keeps both sides
    when the conflict base is empty (ours first, then theirs); a --3way failure
    that leaves no unmerged files is a hard error, never a success;
  * tree modes from the archive are preserved (executable bits, 0755);
  * targets are validated with git rev-parse, so linked Git worktrees work.

The caller may pass an exact, empty `workdir` (owned by the caller) instead of
letting the engine pick a /tmp subdir. The target tree is only read, never
written.
"""
import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


class ComposeError(Exception):
    pass


def _parse_version(text):
    base = text.strip().split("-", 1)[0]
    parts = base.split(".")
    if len(parts) != 3:
        return None
    try:
        out = tuple(int(part) for part in parts)
    except ValueError:
        return None
    if any(part < 0 for part in out):
        return None
    return out


def _in_range(version, constraint, what):
    """Mirror of backend version.matchesVersion (>=, <=, >, <, default =)."""
    if constraint.strip() == "":
        return True
    current = _parse_version(version)
    if current is None:
        raise ComposeError(f"versión no reconocida en {what}: {version!r}")
    for term in constraint.split():
        operator = "="
        value = term
        for candidate in (">=", "<=", ">", "<", "="):
            if term.startswith(candidate):
                operator = candidate
                value = term[len(candidate):]
                break
        required = _parse_version(value)
        if required is None:
            raise ComposeError(f"término de rango no reconocido: {term!r}")
        if operator == ">=":
            ok = current >= required
        elif operator == "<=":
            ok = current <= required
        elif operator == ">":
            ok = current > required
        elif operator == "<":
            ok = current < required
        else:
            ok = current == required
        if not ok:
            return False
    return True


def _run(args, cwd, check=True):
    result = subprocess.run(args, cwd=cwd,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and result.returncode != 0:
        message = (result.stderr or result.stdout or "").strip() or "sin salida"
        raise ComposeError(f"git falló ({args[-1]}): {message}")
    return result


def _git(target, *args, check=True):
    return _run(["git", "-C", target, *args], cwd=target, check=check)


def _safe_join(root, relative):
    if relative.startswith("/") or relative == "":
        raise ComposeError(f"ruta insegura: {relative!r}")
    root_abs = os.path.abspath(root)
    candidate = os.path.abspath(os.path.join(root, relative))
    if os.path.commonpath([root_abs, candidate]) != root_abs:
        raise ComposeError(f"ruta escapa del paquete: {relative!r}")
    return candidate


def _safe_extract(tar, destination):
    destination = os.path.abspath(destination)
    for member in tar:
        name = member.name
        if name in (".", "..") or name.startswith("/") or name.startswith("\\"):
            raise ComposeError(f"entrada insegura en el árbol base: {name!r}")
        cleaned = os.path.normpath(name)
        if cleaned == ".." or cleaned.startswith(".." + os.sep) or os.path.isabs(cleaned):
            raise ComposeError(f"entrada insegura en el árbol base: {name!r}")
        dest = os.path.abspath(os.path.join(destination, cleaned))
        if os.path.commonpath([destination, dest]) != destination:
            raise ComposeError(f"entrada fuera del destino: {name!r}")
        if member.isdir():
            os.makedirs(dest, exist_ok=True)
            if member.mode:
                os.chmod(dest, stat.S_IMODE(member.mode))
        elif member.issym():
            link = member.linkname
            normalized = os.path.normpath(link)
            if link.startswith("/") or normalized == ".." or normalized.startswith(".." + os.sep):
                raise ComposeError(f"enlace simbólico inseguro: {name!r} -> {link!r}")
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            os.symlink(link, dest)
        elif member.isfile():
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            source = tar.extractfile(member)
            if source is None:
                raise ComposeError(f"no se pudo leer la entrada {name!r}")
            with open(dest, "wb") as sink:
                shutil.copyfileobj(source, sink)
            if member.mode:
                os.chmod(dest, stat.S_IMODE(member.mode))
        else:
            raise ComposeError(f"entrada no soportada en el árbol base: {name!r} ({member.type})")


def _export_base(target, destination):
    archive = subprocess.run(["git", "-C", target, "archive", "--format=tar", "HEAD"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if archive.returncode != 0:
        message = archive.stderr.decode(errors="replace").strip() or "sin salida"
        raise ComposeError(f"no se pudo exportar el HEAD del objetivo: {message}")
    with tarfile.open(fileobj=io.BytesIO(archive.stdout), mode="r|") as tar:
        _safe_extract(tar, destination)


def _git_objects_dir(target):
    result = _git(target, "rev-parse", "--git-path", "objects")
    path = result.stdout.strip()
    if not path:
        raise ComposeError("no se pudo resolver el directorio de objetos del objetivo")
    if not os.path.isabs(path):
        path = os.path.join(target, path)
    return path


def _read_trimmed(path):
    try:
        return Path(path).read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _init_repository(generation, target):
    _run(["git", "-C", generation, "init", "-q"], cwd=generation)
    for key, value in [
        ("core.hooksPath", os.path.join(generation, ".git", "unused-hooks")),
        ("core.autocrlf", "false"),
        ("commit.gpgsign", "false"),
        ("merge.conflictStyle", "diff3"),
        ("user.name", "Ambxst Mods"),
        ("user.email", "mods@ambxst.invalid"),
    ]:
        _run(["git", "config", key, value], cwd=generation)
    alternates = os.path.join(generation, ".git", "objects", "info", "alternates")
    os.makedirs(os.path.dirname(alternates), exist_ok=True)
    with open(alternates, "w", encoding="utf-8") as handle:
        handle.write(_git_objects_dir(target) + "\n")
    _commit_step(generation, "base")


def _commit_step(generation, message):
    _run(["git", "add", "-A", "-f", "."], cwd=generation)
    _run(["git", "commit", "--allow-empty", "--no-verify", "-q", "-m", message], cwd=generation)


def _file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def _apply_overlay(generation, source_abs, operation):
    target_rel = operation["target"]
    target_abs = _safe_join(generation, target_rel)
    if os.path.exists(target_abs):
        if os.path.isdir(target_abs):
            raise ComposeError(f"el destino del overlay es un directorio: {target_rel}")
        if not operation.get("replace"):
            raise ComposeError(f"el destino ya existe: {target_rel}")
        if not operation.get("expectedSha256") or not os.path.isfile(target_abs):
            raise ComposeError(f"overlay replace sin expectedSha256: {target_rel}")
        if _file_sha256(target_abs).lower() != operation["expectedSha256"].lower():
            raise ComposeError(f"el destino cambió respecto a expectedSha256: {target_rel}")
    elif operation.get("replace"):
        raise ComposeError(f"el destino del overlay no existe: {target_rel}")
    os.makedirs(os.path.dirname(target_abs), exist_ok=True)
    shutil.copyfile(source_abs, target_abs)


def merge_added_blocks(content):
    """Resolve diff3 conflicts that only contain added blocks (empty base).

    Returns (merged_text, ok). When any conflicted hunk has a non-empty base
    side (or markers are unterminated), ok is False and nothing is rewritten,
    mirroring backend semantics.
    """
    lines = content.split("\n")
    output = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("<<<<<<<"):
            output.append(line)
            index += 1
            continue
        ours, base, theirs = [], [], []
        section = "ours"
        index += 1
        closed = False
        while index < len(lines):
            current = lines[index]
            if current.startswith("|||||||"):
                section = "base"
            elif current == "=======":
                section = "theirs"
            elif current.startswith(">>>>>>>"):
                closed = True
                index += 1
                break
            else:
                if section == "ours":
                    ours.append(current)
                elif section == "base":
                    base.append(current)
                else:
                    theirs.append(current)
            index += 1
        if not closed:
            return content, False
        if base:
            return content, False
        output.extend(ours)
        output.extend(theirs)
    return "\n".join(output), True


def _resolve_added_blocks(generation):
    result = _run(["git", "diff", "--name-only", "--diff-filter=U"], cwd=generation)
    unmerged = [name for name in result.stdout.splitlines() if name.strip()]
    if not unmerged:
        raise ComposeError("git apply --3way falló sin archivos sin combinar")
    for relative in unmerged:
        path = _safe_join(generation, relative)
        if not os.path.isfile(path):
            raise ComposeError(f"archivo en conflicto inexistente: {relative}")
        content = Path(path).read_text(encoding="utf-8")
        merged, ok = merge_added_blocks(content)
        if not ok:
            raise ComposeError(f"conflicto no resoluble (base no vacío o marcadores rotos): {relative}")
        Path(path).write_text(merged, encoding="utf-8")
        _run(["git", "add", "--", relative], cwd=generation)


def _apply_patch(generation, patch_abs):
    wait_check = _run(["git", "apply", "--check", "--whitespace=error-all", patch_abs],
                      cwd=generation, check=False)
    if wait_check.returncode == 0:
        _run(["git", "apply", "--whitespace=error-all", patch_abs], cwd=generation)
        return "el parche aplica literalmente"
    wait_3way = _run(["git", "apply", "--3way", patch_abs], cwd=generation, check=False)
    if wait_3way.returncode == 0:
        return "el parche se compuso por merge de tres vías"
    _resolve_added_blocks(generation)
    return "conflictos por inserciones concurrentes resueltos (ambos bloques conservados)"


def compose(manifest_path, package_root, target, generations_root=None, workdir=None):
    try:
        manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    except Exception as error:  # noqa: BLE001
        raise ComposeError(f"parse manifest: {error}") from error
    if not os.path.isdir(target):
        raise ComposeError("objetivo no existe o no es un directorio")
    toplevel = _git(target, "rev-parse", "--show-toplevel", check=False)
    if toplevel.returncode != 0:
        raise ComposeError("objetivo no es un árbol de trabajo de git")
    if os.path.realpath(toplevel.stdout.strip()) != os.path.realpath(target):
        raise ComposeError("la raíz del árbol de trabajo no coincide con el objetivo")
    _git(target, "rev-parse", "--verify", "HEAD")

    compat = manifest.get("compatibility") or {}
    range_text = compat.get("ambxst")
    if not range_text:
        raise ComposeError("el manifiesto no declara compatibility.ambxst")
    version_text = _read_trimmed(os.path.join(target, "version")) or "0.0.0"
    if not _in_range(version_text, range_text, os.path.join(target, "version")):
        raise ComposeError(f"Ambxst {version_text} no cumple el rango declarado {range_text!r}")
    revision = _git(target, "rev-parse", "--short", "HEAD").stdout.strip()
    print(f"Objetivo: Ambxst {version_text} (revisión {revision}).")

    if workdir is not None:
        generation = Path(workdir)
        if not generation.is_dir():
            raise ComposeError(f"el directorio de trabajo no existe o no es un directorio: {workdir}")
        if any(generation.iterdir()):
            raise ComposeError(f"el directorio de trabajo no está vacío: {workdir}")
    else:
        generation = Path(tempfile.mkdtemp(prefix="ambxst-shortcuts-overlay.compose.",
                                           dir=generations_root or tempfile.gettempdir()))
    try:
        _export_base(target, str(generation))
        _init_repository(str(generation), target)
        for index, operation in enumerate(manifest.get("operations", []), start=1):
            op_type = operation.get("type")
            source_rel = operation.get("source", "")
            source_abs = _safe_join(package_root, source_rel)
            if not os.path.isfile(source_abs):
                raise ComposeError(f"operación {index}: source inexistente: {source_rel}")
            if op_type == "overlay":
                _apply_overlay(str(generation), source_abs, operation)
                method = "overlay copiado"
            elif op_type == "patch":
                method = _apply_patch(str(generation), source_abs)
            else:
                raise ComposeError(f"operación {index}: tipo desconocido {op_type!r}")
            _commit_step(str(generation), f"mod: operación {index} ({op_type})")
            print(f"aplicada operación {index}: {op_type} {source_rel} [{method}]")
        return str(generation)
    except Exception:
        shutil.rmtree(str(generation), ignore_errors=True)
        raise


def main(argv):
    if len(argv) not in (3, 4):
        print("Uso: python3 compose.py <ambxst.mod.json> <package-root> <target> [workdir]", file=sys.stderr)
        return 2
    try:
        generation = compose(argv[0], argv[1], argv[2],
                             workdir=argv[3] if len(argv) == 4 else None)
    except ComposeError as error:
        print(f"ERROR: composición fallida: {error}", file=sys.stderr)
        return 1
    print(f"OK: composición íntegra en {generation} (el objetivo no se modificó).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))