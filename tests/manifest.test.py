#!/usr/bin/env python3
"""Permanent validation of ambxst.mod.json and the native package layout.

Mirrors the checks implemented in Ambxst's backend/pkg/mods/manifest.go plus the
contractual decisions fixed for the v0.2.0 release. Failures here mean the
package would be rejected by the mod manager or ship unintended decisions.
"""
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
sys.dont_write_bytecode = True
import manifest_validate as mv

PROJECT = Path(__file__).resolve().parents[1]
ID = "kurostain.shortcuts-overlay"
VERSION = "0.2.0"
RANGE = ">=1.3.3 <1.4.0"
# Every entry must be a full commit that this release has really been validated
# against (composition and, where documented, runtime). Adding an entry requires
# extending this allowlist with the actual validated commit.
TESTED_BASE_COMMITS = {"af9f8ad4f42d7cd77f57a7c75f6a2a5d1fb59674"}

assertions = 0


def check(condition, message):
    global assertions
    assertions += 1
    if not condition:
        raise AssertionError(message)


def main():
    manifest = json.loads((PROJECT / "ambxst.mod.json").read_text(encoding="utf-8"))

    known_keys = {
        "$schema", "manifestVersion", "id", "name", "version", "description",
        "license", "author", "authorUrl", "homepage", "compatibility",
        "dependencies", "dependencySources", "conflicts", "commands",
        "permissions", "settings", "operations",
    }
    check(set(manifest) <= known_keys, f"claves desconocidas: {set(manifest) - known_keys}")

    check(manifest["manifestVersion"] == 1, "manifestVersion debe ser 1")
    check(manifest["id"] == ID, f"id debe ser {ID}")
    check(re.fullmatch(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$", manifest["id"]), "id no cumple el patrón")
    check(bool(manifest.get("name")), "name es obligatorio")
    check(manifest["version"] == VERSION, f"version debe ser {VERSION}")
    check(re.fullmatch(r"^[0-9]+\.[0-9]+\.[0-9]+$", manifest["version"]), "version no cumple el patrón")
    check(manifest.get("license") == "MIT", "license debe ser MIT")
    check(manifest.get("author") == "KuroStain", "author debe ser KuroStain")
    check(manifest.get("description"), "description debe existir")

    compat = manifest["compatibility"]
    check(compat.get("api") == 1, "compatibility.api debe ser 1")
    check(compat.get("ambxst") == RANGE, f"compatibility.ambxst debe ser {RANGE}")
    tested = compat.get("testedBaseCommits") or []
    check(len(tested) > 0, "testedBaseCommits no debe estar vacío")
    check(len(tested) == len(set(tested)), "testedBaseCommits no debe repetir commits")
    check(all(re.fullmatch(r"[0-9a-fA-F]{40}", c) for c in tested), "testedBaseCommits requiere SHA-256 de 40 hex")
    check(all(c in TESTED_BASE_COMMITS for c in tested), "testedBaseCommits contiene commits no validados en esta release")

    check(manifest.get("dependencies") == [], "dependencies debe estar vacío")
    check(manifest.get("conflicts") == [], "conflicts debe estar vacío")
    check(manifest.get("commands") == [], "commands debe estar vacío")
    check("dependencySources" not in manifest or manifest["dependencySources"] == {}, "dependencySources debe estar ausente o vacío")
    check("settings" not in manifest, "settings debe estar ausente")

    permissions = manifest.get("permissions") or []
    check(len(permissions) > 0, "permissions debe ser descriptiva y no vacía")
    check(len(permissions) == len(set(permissions)), "permissions no debe repetir entradas")
    check(all(isinstance(p, str) and p.strip() for p in permissions), "permissions debe ser una lista de texto")

    ops = manifest["operations"]
    check(len(ops) == 3, "operations debe declarar exactamente 3 operaciones")
    expected = [
        ("overlay", "payload/modules/widgets/shortcuts/ShortcutsOverlay.qml", "modules/widgets/shortcuts/ShortcutsOverlay.qml"),
        ("overlay", "payload/modules/widgets/shortcuts/ShortcutData.js", "modules/widgets/shortcuts/ShortcutData.js"),
        ("patch", "patches/ambxst-integration.patch", None),
    ]
    for op, (op_type, source, target) in zip(ops, expected, strict=True):
        check(op["type"] == op_type, f"operación inesperada: {op}")
        check(op["source"] == source, f"source esperado {source}, se obtuvo {op.get('source')}")
        check(op.get("target") == target, f"target esperado {target}, se obtuvo {op.get('target')}")
        check(not op.get("replace", False), f"no debe usar replace: true ({op})")
        check(not op.get("expectedSha256"), f"no debe declarar expectedSha256 ({op})")
        check(not op.get("replace") or op.get("expectedSha256"), "replace exige expectedSha256")
    for op in ops:
        for key in ("replace", "expectedSha256"):
            check(key not in op, f"operation no debe declarar {key}")

    # Operation sources must exist as regular files inside the package.
    for op in ops:
        source_file = PROJECT / op["source"]
        check(source_file.is_file() and not source_file.is_symlink(), f"source no regular: {op['source']}")
        target = op.get("target")
        if target is not None:
            check(Path(target).is_absolute() is False, f"target debe ser relativo: {target}")
            check(target not in (".", "..") and not target.startswith("../"), f"target no seguro: {target}")

    # validatePackageTree: no symlinks among the files the package ships.
    tracked = subprocess.check_output(
        ["git", "-C", str(PROJECT), "ls-files"], text=True
    ).splitlines()
    check(len(tracked) > 0, "el repositorio debe tener archivos rastreados")
    for relative in tracked:
        candidate = PROJECT / relative
        check(not candidate.is_symlink(), f"enlace simbólico no permitido: {relative}")

    # Migration guards: the legacy installer tree must be gone from this line.
    for legacy in ["scripts/install.sh", "scripts/uninstall.sh", "scripts/common.sh", "scripts/gen_candidate"]:
        check(not (PROJECT / legacy).exists(), f"el instalador legacy no debe existir en v0.2.0: {legacy}")
    check(not (PROJECT / "src").exists(), "src/ no debe existir en v0.2.0 (migrado a payload/)")

    validate_effective_manifest()
    print(f"OK: {assertions} comprobaciones del manifiesto y estructura nativa.")


MANIFEST_TEMPLATE = {
    "manifestVersion": 1,
    "id": "kurostain.shortcuts-overlay",
    "name": "Shortcuts overlay",
    "version": "0.2.0",
    "compatibility": {"api": 1, "ambxst": ">=1.3.3 <1.4.0"},
    "dependencies": [],
    "conflicts": [],
    "operations": [
        {"type": "overlay", "source": "payload/modules/widgets/shortcuts/ShortcutsOverlay.qml",
         "target": "modules/widgets/shortcuts/ShortcutsOverlay.qml"},
        {"type": "patch", "source": "patches/ambxst-integration.patch"},
    ],
}


def validate_effective_manifest():
    """Finding 5: real validation against Ambxst's schema + backend parity,
    with negative type cases (including name: 42) driving the evaluator."""
    global assertions

    schema = json.loads((PROJECT / "docs" / "mods" / "manifest.schema.json").read_text(encoding="utf-8"))
    check(schema["$schema"].endswith("2020-12/schema"), "schema vendado no es draft 2020-12")
    check("overlay" in schema["$defs"] and "patch" in schema["$defs"], "schema vendado sin $defs overlay/patch")
    assertions += 2

    # Positive: the released manifest passes the real schema + backend parity.
    mv.validate_manifest(PROJECT / "ambxst.mod.json", PROJECT)
    check(True, "el manifiesto de la release pasa la validación schema/backend")
    assertions += 1

    def probe(mutator, needle, label):
        """Build a temp package from the template, apply `mutator`, expect rejection
        whose message contains `needle` (or None meaning 'any error')."""
        global assertions
        assertions += 1
        document = json.loads(json.dumps(MANIFEST_TEMPLATE))
        mutator(document)
        with tempfile.TemporaryDirectory(prefix="ambxst-manifest-neg-", dir="/tmp") as directory:
            root = Path(directory)
            (root / "patches").mkdir()
            (root / "payload" / "modules" / "widgets" / "shortcuts").mkdir(parents=True)
            for relative in ["patches/ambxst-integration.patch",
                             "payload/modules/widgets/shortcuts/ShortcutsOverlay.qml"]:
                Path(root / relative).write_text("placeholder\n", encoding="utf-8")
            manifest_path = root / "ambxst.mod.json"
            manifest_path.write_text(json.dumps(document, indent=2), encoding="utf-8")
            try:
                mv.validate_manifest(manifest_path, root)
            except mv.ValidationError as error:
                if needle is not None and needle not in str(error):
                    raise AssertionError(f"{label}: error sin el detalle esperado {needle!r}: {error}") from error
                return
            raise AssertionError(f"mutación no rechazada: {label}")

    # Schema-level type/value negatives (finding 5).
    probe(lambda d: d.update(name=42), "name", "name: 42 (tipo string)")
    probe(lambda d: d.update(version=42), "version", "version: 42 (tipo string)")
    probe(lambda d: d.update(manifestVersion=2), "debe ser 1", "manifestVersion != 1")
    probe(lambda d: d.update(manifestVersion=True), "debe ser 1", "manifestVersion: true (booleano != entero)")
    probe(lambda d: d["compatibility"].update(api=True), "debe ser 1", "compatibility.api: true (booleano != entero)")
    probe(lambda d: d.update(id="BAD ID"), "patrón", "id con espacios")
    probe(lambda d: d.update(operations="patch"), "array", "operations como texto")
    probe(lambda d: d.update(operations=[]), "cantidad", "operations vacío")
    probe(lambda d: d["operations"][0].update(type="nuke"), "alternativa", "tipo de operación desconocido")
    probe(lambda d: d["operations"][0].update(target="../escapa"), "alternativa", "target escapando del paquete")
    probe(lambda d: d["operations"][0].update(target="/absoluto"), "alternativa", "target absoluto")
    probe(lambda d: d["operations"][0].update(trailing=1), "alternativa", "clave extra en overlay")
    probe(lambda d: d["compatibility"].update(bogus=1), "propiedad desconocida", "clave desconocida en compatibility")
    probe(lambda d: d.update(surprise=1), "propiedad desconocida", "clave top-level desconocida")
    probe(lambda d: d["operations"][0].update(replace=True), "alternativa", "replace sin expectedSha256")
    probe(lambda d: d.setdefault("compatibility", {}).update(testedBaseCommits=["aaaaaaa", "aaaaaaa"]),
          "repetido", "testedBaseCommits duplicados")
    # propertyNames / additionalProperties must apply even without "properties".
    probe(lambda d: d.update(dependencySources={"BAD KEY": "x"}),
          "patrón", "dependencySources con clave fuera del patrón")
    probe(lambda d: d.update(dependencySources={"ok.mod": 42}),
          "string", "dependencySources con valor no string")
    # Backend parity negatives (the schema alone cannot catch them).
    probe(lambda d: d["operations"][0].update(expectedSha256="0" * 64),
          "expectedSha256 sin replace", "expectedSha256 sin replace (paridad backend)")
    probe(lambda d: d["operations"][0].update(source="no-such-file"),
          "source no es un archivo regular", "source inexistente (paridad backend)")
    probe(lambda d: d.update(dependencies=["kurostain.shortcuts-overlay"]),
          "sí mismo", "dependencia auto-referencial (paridad backend)")
    probe(lambda d: d.update(dependencySources={"ghost.mod": "https://example.invalid/a.pk3"}),
          "no está declarada", "dependencySource sin dependency (paridad backend)")
    check(True, "los casos negativos de tipo se rechazan (schema + backend)")
    assertions += 1

    # Backend tree scan: symlinks anywhere in the package must be refused.
    with tempfile.TemporaryDirectory(prefix="ambxst-manifest-symlink-", dir="/tmp") as directory:
        root = Path(directory)
        (root / "patches").mkdir()
        (root / "payload" / "modules" / "widgets" / "shortcuts").mkdir(parents=True)
        (root / "patches" / "ambxst-integration.patch").write_text("placeholder\n", encoding="utf-8")
        (root / "payload" / "modules" / "widgets" / "shortcuts" / "ShortcutsOverlay.qml").write_text("placeholder\n", encoding="utf-8")
        os.symlink("/etc/hostname", root / "patches" / "evil-link")
        document = json.loads(json.dumps(MANIFEST_TEMPLATE))
        manifest_path = root / "ambxst.mod.json"
        manifest_path.write_text(json.dumps(document, indent=2), encoding="utf-8")
        try:
            mv.validate_manifest(manifest_path, root)
        except mv.ValidationError:
            pass
        else:
            raise AssertionError("el árbol con enlace simbólico debió rechazarse")
        check(True, "el paquete no debe contener enlaces simbólicos (paridad backend)")
        assertions += 1


if __name__ == "__main__":
    main()