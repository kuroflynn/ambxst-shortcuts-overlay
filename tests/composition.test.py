#!/usr/bin/env python3
"""Manager-style mod composition in /tmp; the delivered tree is never written.

Drives scripts/compose.py (parity with Ambxst backend/pkg/mods/manager.go) and
covers the Astra review findings as regressions:

  1. Git hooks are completely disabled in the throwaway generation (dead
     core.hooksPath plus --no-verify); a poisoned GIT_TEMPLATE_DIR proves no hook
     runs, not even the one that would write both probes (a marker inside the
     test tree, outside the generation).
  2. An overlay whose destination already exists in the base is refused.
  3. The rock-solid fallback is replicated: verbatim apply first, then --3way,
     then resolve-of-added-blocks; alternates + merge.conflictStyle=diff3 are
     configured exactly like the backend, and concurrent insertions keep both
     sides (ours first) while a non-empty conflict base aborts. A --3way
     failure that leaves no unmerged files is an error, never a success.
  4. verify.sh CLI contract (--package-only | explicit target | usage-fail).
  5. Manifest validation is delegated to the real schema + backend (negative
     typed cases live in manifest.test.py).
  6. _safe_extract preserves git-archive modes (executable 0755).
  7. Linked Git worktrees are valid targets (root via git rev-parse).

Nothing is ever created or written under $HOME, and the suite never leaves a
scripts/__pycache__ behind (PYTHONDONTWRITEBYTECODE / sys.dont_write_bytecode).

Also asserts the source target used as the base is never written.
"""
import contextlib
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = PROJECT / "scripts"
PATCH = PROJECT / "patches" / "ambxst-integration.patch"
PAYLOAD = PROJECT / "payload" / "modules" / "widgets" / "shortcuts"
MANIFEST_FILE = PROJECT / "ambxst.mod.json"
sys.dont_write_bytecode = True
sys.path.insert(0, str(SCRIPT_DIR))
from compose import (  # noqa: E402
    ComposeError,
    compose,
    merge_added_blocks,
)

assertions = 0


def check(condition, message):
    global assertions
    assertions += 1
    if not condition:
        raise AssertionError(message)


def message(name):
    global assertions
    assertions += 1
    print(f"ok {assertions} - {name}", flush=True)


def run(args, cwd=None, check_result=True):
    result = subprocess.run([str(a) for a in args], cwd=cwd,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check_result and result.returncode != 0:
        raise AssertionError(f"comando falló: {args}\n{result.stderr}")
    return result


def git(target, *args, check_result=True):
    return run(["git", "-C", str(target), *args], check_result=check_result)


def materialize_base(target: Path):
    target.mkdir()
    (target / "modules" / "services").mkdir(parents=True)
    (target / "modules" / "widgets").mkdir()
    (target / "version").write_text("1.3.3\n")
    schema_src = PROJECT / "docs" / "mods" / "manifest.schema.json"
    schema_dst = target / "docs" / "mods" / "manifest.schema.json"
    schema_dst.parent.mkdir(parents=True, exist_ok=True)
    schema_dst.write_bytes(schema_src.read_bytes())
    files = {}
    current = None
    for line in PATCH.read_text(encoding="utf-8").splitlines():
        if line.startswith("diff --git "):
            current = line.split(" ")[2][2:]
            files[current] = []
        elif line.startswith("@@ "):
            start = int(line.split(" ")[1][1:].split(",")[0])
            while len(files[current]) < start - 1:
                files[current].append("// fixture padding")
        elif line[:1] in (" ", "-") and current:
            files[current].append(line[1:])
    for name, lines in files.items():
        out = target / name
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("\n".join(lines) + "\n")


def init_git(target: Path):
    git(target, "init", "-q")
    git(target, "config", "user.email", "test@ambxst.invalid")
    git(target, "config", "user.name", "Composition test")
    git(target, "add", "-A", "-f", ".")
    git(target, "commit", "-q", "--allow-empty", "-m", "base")
    git(target, "branch", "-M", "main")


def snapshot(root: Path):
    result = {}
    for f in sorted(root.rglob("*")):
        rel = f.relative_to(root)
        if ".git" in rel.parts:
            continue
        if f.is_dir():
            result[str(rel)] = ("dir",)
        elif f.is_symlink():
            result[str(rel)] = ("link", os.readlink(f))
        else:
            result[str(rel)] = ("file", hashlib.sha256(f.read_bytes()).hexdigest())
    return result


def run_verify(args):
    return subprocess.run([str(PROJECT / "scripts" / "verify.sh"), *[str(a) for a in args]],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90)


HOOK_TEMPLATE = """#!/usr/bin/env bash
if [[ -n "${OUTSIDE_MARKER:-}" ]]; then
    printf 'ran\\n' >> "${OUTSIDE_MARKER}"
fi
if [[ -n "${INSIDE_MARKER:-}" ]]; then
    printf 'ran\\n' >> "${INSIDE_MARKER}"
fi
"""


def with_hook_template(directory: Path):
    template = directory / "hook-template"
    (template / "hooks").mkdir(parents=True)
    for hook in ("pre-commit", "commit-msg", "post-commit"):
        path = template / "hooks" / hook
        path.write_text(HOOK_TEMPLATE, encoding="utf-8")
        os.chmod(path, 0o755)
    return template


with tempfile.TemporaryDirectory(prefix="ambxst-composition-", dir="/tmp") as directory:
    root = Path(directory)

    # ------------------------------------------------------------------ #
    # Scenario 1: main happy path through the engine (findings 1 & 3 cfg) #
    # ------------------------------------------------------------------ #
    target = root / "ambxst"
    materialize_base(target)
    init_git(target)
    before = snapshot(target)

    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        generation = compose(str(MANIFEST_FILE), str(PROJECT), str(target), generations_root=str(root))
    gen = Path(generation)
    stdout_text = output.getvalue()

    check(str(gen).startswith("/tmp/") or str(gen).startswith(str(root)), "generación debe estar en la base temporal")
    check("el parche aplica literalmente" in stdout_text, "el parche debe aplicar literalmente sobre la base materializada")
    check("overlay copiado" in stdout_text, "overlays deben componerse desde payload")
    check("aplicada operación 3" in stdout_text, "deben componerse las tres operaciones")

    shell = (gen / "shell.qml").read_text(encoding="utf-8")
    visibilities = (gen / "modules" / "services" / "Visibilities.qml").read_text(encoding="utf-8")
    shortcuts_svc = (gen / "modules" / "services" / "GlobalShortcuts.qml").read_text(encoding="utf-8")
    check("import qs.modules.widgets.shortcuts" in shell, "shell.qml sin import del módulo shortcuts")
    check("ShortcutsOverlay {" in shell, "shell.qml sin instancia de ShortcutsOverlay")
    check('"shortcuts"' in visibilities, "Visibilities.qml sin estado shortcuts")
    check('case "shortcuts"' in shortcuts_svc, "GlobalShortcuts.qml sin comando shortcuts")
    for name in ["ShortcutsOverlay.qml", "ShortcutData.js"]:
        composed = (gen / "modules" / "widgets" / "shortcuts" / name).read_bytes()
        check(composed == (PAYLOAD / name).read_bytes(), f"payload {name} no quedó íntegro en la composición")
    check(snapshot(target) == before, "la composición modificó el árbol entregado")
    message("composición del mod produce el árbol esperado con payloads íntegros (solo /tmp)")

    # Finding 1: hooks must be dead and pointed inside the temp generation.
    hooks_path = git(gen, "config", "core.hooksPath").stdout.strip()
    check(hooks_path == str(gen / ".git" / "unused-hooks"), f"hooksPath inesperado: {hooks_path}")
    check(not (gen / ".git" / "unused-hooks").exists(), "el directorio de hooks debe ser inexistente (muerto)")
    check(str(gen) in hooks_path, "hooksPath debe apuntar dentro de la generación temporal")
    check(git(gen, "config", "merge.conflictStyle").stdout.strip() == "diff3", "merge.conflictStyle debe ser diff3")
    check(git(gen, "config", "commit.gpgsign").stdout.strip() == "false", "commit.gpgsign debe desactivarse")
    check(git(gen, "config", "core.autocrlf").stdout.strip() == "false", "core.autocrlf debe desactivarse")

    # Finding 3: alternates must bridge the target object store (base blobs
    # stay reachable after updates, exactly like gitObjectsDir).
    alternates = (gen / ".git" / "objects" / "info" / "alternates").read_text(encoding="utf-8").strip()
    target_objects_raw = git(target, "rev-parse", "--git-path", "objects").stdout.strip()
    target_objects = (target / target_objects_raw).resolve() if not os.path.isabs(target_objects_raw) else target_objects_raw
    check(alternates == str(target_objects), f"alternates no apunta al object store del objetivo: {alternates}")
    check(os.path.isabs(alternates) and os.path.isdir(alternates), "alternates debe ser un directorio real")
    message("hooks desactivados (dead hooksPath dentro de /tmp) y alternates configurado")

    # ------------------------------------------------------------------ #
    # verify.sh CLI contract (finding 4)                                  #
    # ------------------------------------------------------------------ #
    package_only = run_verify(["--package-only"])
    check(package_only.returncode == 0, f"verify.sh --package-only falló:\n{package_only.stdout}")

    no_args = run_verify([])
    check(no_args.returncode != 0, "verify.sh sin argumentos debía fallar (sin resolución automática)")
    check("Uso:" in no_args.stdout, "verify.sh sin argumentos debe imprimir el uso")

    help_ok = run_verify(["-h"])
    check(help_ok.returncode == 0, "verify.sh -h debía terminar en 0")
    check("Uso:" in help_ok.stdout, "verify.sh -h debe imprimir el uso")

    target_run = run_verify([target])
    check(target_run.returncode == 0, f"verify.sh <target> falló:\n{target_run.stdout}")
    check("Objetivo: Ambxst 1.3.3" in target_run.stdout, "verify.sh no reconoció la versión del objetivo")
    check("aplica literalmente" in target_run.stdout, "verify.sh no confirmó la aplicación literal")
    check("íntegra" in target_run.stdout, "verify.sh no confirmó la composición íntegra")
    check(snapshot(target) == before, "verify.sh modificó el árbol entregado")
    message("verify.sh cumple el contrato (--package-only | target | uso) y no altera el destino")

    # ------------------------------------------------------------------ #
    # Finding 1: hostile hooks (GIT_TEMPLATE_DIR) never execute            #
    # ------------------------------------------------------------------ #
    template = with_hook_template(root / "hooks")
    outside = root / f"outside-no-hook-ran-{os.getpid()}.txt"
    inside = root / "inside-no-hook-ran.txt"
    for marker in (outside, inside):
        marker.unlink(missing_ok=True)
    env = os.environ.copy()
    env["GIT_TEMPLATE_DIR"] = str(template)
    env["OUTSIDE_MARKER"] = str(outside)
    env["INSIDE_MARKER"] = str(inside)

    # Control: a plain repo with the same template (no hooksPath dance)
    # proves the hooks are real and would write both probes (one inside the
    # test tree, one outside the generation; both under /tmp only).
    control = root / "hook-control"
    control.mkdir()
    (control / "file.txt").write_text("x\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(control), "init", "-q"], check=True, env=env)
    for key, value in (("user.email", "h@h"), ("user.name", "H")):
        subprocess.run(["git", "config", key, value], cwd=control, check=True, env=env)
    subprocess.run(["git", "add", ".", "-A"], cwd=control, check=True, env=env)
    subprocess.run(["git", "commit", "-qm", "boom"], cwd=control, check=True, env=env)
    check(outside.exists(), "el hook de control no escribió el marcador externo (probe rota)")
    check(inside.exists(), "el hook de control no escribió el marcador interno")
    outside.unlink(missing_ok=True)
    inside.unlink(missing_ok=True)

    # Composition through the engine under the poisoned environment.
    clone = root / "ambxst-hooks"
    materialize_base(clone)
    init_git(clone)
    stamped = os.environ
    keys = ("GIT_TEMPLATE_DIR", "OUTSIDE_MARKER", "INSIDE_MARKER")
    previous = {key: stamped.pop(key, None) for key in keys}
    try:
        stamped.update(env)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            gen_h = Path(compose(str(MANIFEST_FILE), str(PROJECT), str(clone),
                                 generations_root=str(root)))
    finally:
        for key in keys:
            stamped.pop(key, None)
            if previous[key] is not None:
                stamped[key] = previous[key]
    check("aplica literalmente" in output.getvalue(), "la composición con hooks hostiles no debió fallar")
    check(list(gen_h.rglob("*.hook-ran*")) == [], "la composición no debió ejecutar hooks en su árbol")
    check((gen_h / ".git" / "hooks" / "pre-commit").exists(),
          "git init copió el template hostil (probe válida)")
    check(not inside.exists(),
          "el hook hostil se ejecutó dentro de la generación durante la composición")
    check(not outside.exists(),
          "un hook hostil pudo escribir fuera de la generación (dentro del árbol /tmp) durante la composición")
    hooks_path = git(gen_h, "config", "core.hooksPath").stdout.strip()
    check(str(Path(hooks_path).resolve()).startswith(str(root)), "hooksPath debe quedar bajo la generación temporal")
    message("ningún hook (ni el que escribe fuera de la generación) se ejecuta durante la composición")

    # ------------------------------------------------------------------ #
    # Finding 2: overlay destination already present is refused            #
    # ------------------------------------------------------------------ #
    exists_target = root / "ambxst-exists"
    materialize_base(exists_target)
    overlay_dest = exists_target / "modules" / "widgets" / "shortcuts" / "ShortcutsOverlay.qml"
    overlay_dest.parent.mkdir(parents=True, exist_ok=True)
    overlay_dest.write_text("otra cosa\n", encoding="utf-8")
    init_git(exists_target)
    try:
        compose(str(MANIFEST_FILE), str(PROJECT), str(exists_target), generations_root=str(root))
    except ComposeError as error:
        check("ya existe" in str(error), f"motivo inesperado al rechazar el overlay: {error}")
    else:
        raise AssertionError("el overlay sobre un destino existente debía rechazarse")
    message("overlay con destino ya existente se rechaza antes de copiar")

# ------------------------------------------------------------------ #
    # Finding 3: three-way fallback on context drift (with alternates)     #
    # ------------------------------------------------------------------ #
    def make_conflict_tree(base_lines, mod1_fn, mod2_fn, label):
        repo = root / f"mini-{label}"
        repo.mkdir()
        patches = repo.parent / f"patches-{label}"
        patches.mkdir(exist_ok=True)
        (repo / "version").write_text("1.3.3\n")
        (repo / "f.txt").write_text("\n".join(base_lines) + "\n", encoding="utf-8")
        init_git(repo)
        git(repo, "checkout", "-qb", "mod1")
        mod1_fn(repo / "f.txt")
        git(repo, "add", "-A", "-f", ".")
        git(repo, "commit", "-qm", label + "-mod1")
        subprocess.run(["git", "-C", str(repo), "diff", "main", "HEAD", "--", "f.txt"],
                       stdout=open(patches / "p1.patch", "w"), check=True)
        git(repo, "checkout", "-qb", "mod2", "main")
        mod2_fn(repo / "f.txt")
        git(repo, "add", "-A", "-f", ".")
        git(repo, "commit", "-qm", label + "-mod2")
        subprocess.run(["git", "-C", str(repo), "diff", "main", "HEAD", "--", "f.txt"],
                       stdout=open(patches / "p2.patch", "w"), check=True)
        git(repo, "checkout", "-q", "main")
        return repo, patches

    def mini_manifest(patches_dir):
        manifest = {
            "manifestVersion": 1,
            "id": "mini.conflict",
            "compatibility": {"api": 1, "ambxst": ">=1.3.3 <2.0.0"},
            "operations": [
                {"type": "patch", "source": "p1.patch"},
                {"type": "patch", "source": "p2.patch"},
            ],
        }
        path = Path(patches_dir) / "mini.mod.json"
        path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return path

    def insertion_after(line_text, new_text, anchor):
        return line_text.replace(anchor + "\n", anchor + "\n" + new_text, 1)

    base_lines = ["L1", "L2", "L3", "L4"]

    def mod1_ins(path):
        path.write_text(insertion_after(path.read_text(encoding="utf-8"), "X1\nX2\n", "L1"), encoding="utf-8")

    def mod2_ins(path):
        path.write_text(insertion_after(path.read_text(encoding="utf-8"), "Y\n", "L1"), encoding="utf-8")

    repo_b, patches_b = make_conflict_tree(base_lines, mod1_ins, mod2_ins, "inserts")
    manifest_b = mini_manifest(patches_b)
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        gen_b = Path(compose(str(manifest_b), str(patches_b), str(repo_b), generations_root=str(root)))
    check("concurrentes" in output.getvalue(), f"debería resolverse la inserción concurrente:\n{output.getvalue()}")
    final = (gen_b / "f.txt").read_text(encoding="utf-8")
    check(final == "\n".join(["L1", "X1", "X2", "Y", "L2", "L3", "L4"]) + "\n",
          f"ambas inserciones deben conservarse (nuestra, luego suya): {final!r}")
    check(git(gen_b, "diff", "--name-only", "--diff-filter=U").stdout.strip() == "",
          "debe quedar sin archivos sin combinar tras la resolución")
    message("inserciones concurrentes en el mismo ancla conservan ambas partes (nuestra primero)")

    def mod1_edit(path):
        path.write_text(path.read_text(encoding="utf-8").replace("L2\n", "L2a\n", 1), encoding="utf-8")

    def mod2_edit(path):
        path.write_text(path.read_text(encoding="utf-8").replace("L2\n", "L2b\n", 1), encoding="utf-8")

    repo_c, patches_c = make_conflict_tree(base_lines, mod1_edit, mod2_edit, "edits")
    manifest_c = mini_manifest(patches_c)
    try:
        compose(str(manifest_c), str(patches_c), str(repo_c), generations_root=str(root))
    except ComposeError as error:
        check("base no vacío" in str(error), f"motivo inesperado al rechazar conflicto: {error}")
    else:
        raise AssertionError("un conflicto 3way con base no vacía debía abortar la composición")
    message("un conflicto 3way con base no vacía aborta (no se conservan bloques arbitrarios)")

    # Three-way fallback on context drift: p1 inserts at the top, p2 only
    # drifts a context line far away. The literal check fails (offset), the
    # three-way merge succeeds and keeps BOTH our insertion and the drifted
    # line -- proving alternates let git reach the original preimage blob.
    def mod2_drift(path):
        path.write_text(path.read_text(encoding="utf-8").replace("L4\n", "L4-plus\n", 1), encoding="utf-8")

    repo_d, patches_d = make_conflict_tree(base_lines, mod1_ins, mod2_drift, "drift")
    manifest_d = mini_manifest(patches_d)
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        gen_d = Path(compose(str(manifest_d), str(patches_d), str(repo_d), generations_root=str(root)))
    drift_text = output.getvalue()
    check("tres vías" in drift_text, f"el parche con deriva debía componerse por tres vías:\n{drift_text}")
    number_d = (gen_d / "f.txt").read_text(encoding="utf-8")
    check("X1\nX2\n" in number_d and "L4-plus" in number_d,
          f"el merge de tres vías perdió la inserción o la deriva: {number_d!r}")
    message("el parche con deriva de contexto se compone por merge de tres vías (alternates incluidos)")


    # --------------------- merge_added_blocks units --------------------- #
    empty_base_conflict = (
        "L1\n<<<<<<< ours\nX1\n||||||| base\n=======\nY\n>>>>>>> theirs\nL2\nL3\nL4"
    )
    merged, ok = merge_added_blocks(empty_base_conflict)
    check(ok and merged == "L1\nX1\nY\nL2\nL3\nL4", f"resolución de base vacía inesperada: {merged!r}")

    non_empty_conflict = "L1\n<<<<<<< ours\nL2a\n||||||| base\nL2\n=======\nL2b\n>>>>>>> theirs\nL3\nL4"
    merged, ok = merge_added_blocks(non_empty_conflict)
    check(not ok, "la base no vacía debe hacer fallar la resolución")

    unclosed = "L1\n<<<<<<< ours\nX1\nL2\nL3"
    merged, ok = merge_added_blocks(unclosed)
    check(not ok, "marcadores no cerrados deben hacer fallar la resolución")

    untouched = "L1\nL2\nL3\nL4"
    merged, ok = merge_added_blocks(untouched)
    check(ok and merged == untouched, "contenido sin conflictos debe pasar intacto")
    message("merge_added_blocks conserva solo inserciones con base vacía")

    # ------------------------------------------------------------------ #
    # Finding 2: a --3way failure with no unmerged files must abort          #
    # ------------------------------------------------------------------ #
    ghost_repo = root / "mini-ghost"
    ghost_repo.mkdir()
    ghost_patches = root / "patches-ghost"
    ghost_patches.mkdir()
    (ghost_repo / "version").write_text("1.3.3\n")
    (ghost_repo / "ghost.txt").write_text("G1\nG2\n", encoding="utf-8")
    init_git(ghost_repo)
    git(ghost_repo, "checkout", "-qb", "mod1")
    (ghost_repo / "ghost.txt").write_text("G1\nG2\nG3\n", encoding="utf-8")
    git(ghost_repo, "add", "-A", "-f", ".")
    git(ghost_repo, "commit", "-qm", "ghost-mod")
    subprocess.run(["git", "-C", str(ghost_repo), "diff", "main", "HEAD", "--", "ghost.txt"],
                   stdout=open(ghost_patches / "p1.patch", "w"), check=True)
    manifest_ghost = mini_manifest(ghost_patches)
    target_ghost = root / "ambxst-ghost"
    target_ghost.mkdir()
    (target_ghost / "version").write_text("1.3.3\n")
    init_git(target_ghost)
    try:
        compose(str(manifest_ghost), str(ghost_patches), str(target_ghost), generations_root=str(root))
    except ComposeError as error:
        check("sin archivos sin combinar" in str(error),
              f"motivo inesperado al fallar sin conflictos: {error}")
    else:
        raise AssertionError("un git apply --3way fallido sin archivos sin combinar debía abortar")
    message("un git apply --3way fallido sin archivos sin combinar aborta (no se convierte en éxito)")

    # ------------------------------------------------------------------ #
    # Finding 6: _safe_extract preserves git-archive modes (0755)            #
    # ------------------------------------------------------------------ #
    exec_target = root / "ambxst-exec"
    materialize_base(exec_target)
    tool = exec_target / "tools" / "run.sh"
    tool.parent.mkdir(parents=True, exist_ok=True)
    tool.write_text("#!/usr/bin/env bash\necho hi\n", encoding="utf-8")
    os.chmod(tool, 0o755)
    init_git(exec_target)
    check(bool(os.stat(tool).st_mode & 0o111), "el fixture ejecutable debe tener bit +x")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        gen_exec = Path(compose(str(MANIFEST_FILE), str(PROJECT), str(exec_target),
                                generations_root=str(root)))
    gen_tool = gen_exec / "tools" / "run.sh"
    check(gen_tool.exists(), "el archivo ejecutable no quedó en la composición")
    check(os.access(gen_tool, os.X_OK),
          "_safe_extract no conservó el bit de ejecución (0755) del git archive")
    message("_safe_extract conserva los permisos del git archive (ejecutables 0755)")

    # ------------------------------------------------------------------ #
    # Finding 7: linked Git worktrees are valid composition targets          #
    # ------------------------------------------------------------------ #
    linked_main = root / "linked-main"
    materialize_base(linked_main)
    init_git(linked_main)
    linked_wt = root / "linked-wt"
    git(linked_main, "worktree", "add", "-q", "--detach", str(linked_wt), "HEAD")
    check((linked_wt / ".git").is_file() and not (linked_wt / ".git").is_dir(),
          "el worktree debe ser vinculado (.git como archivo apuntador)")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        gen_wt = Path(compose(str(MANIFEST_FILE), str(PROJECT), str(linked_wt),
                              generations_root=str(root)))
    check("el parche aplica literalmente" in output.getvalue(),
          f"la composición contra un worktree vinculado falló:\n{output.getvalue()}")
    check((gen_wt / "shell.qml").exists(), "árbol compuesto desde worktree incompleto")
    message("un worktree Git vinculado es un objetivo válido para la composición")

    # ------------------------------------------------------------------ #
    # Bytecode hygiene: the suite must not leave scripts/__pycache__         #
    # ------------------------------------------------------------------ #
    check(not (SCRIPT_DIR / "__pycache__").exists(),
          "la suite generó scripts/__pycache__: ejecútala con PYTHONDONTWRITEBYTECODE=1")

assertions += 1
print(f"OK: composición y verificación validan el paquete nativo (solo /tmp), {assertions} comprobaciones.")