#!/usr/bin/env python3
"""Effective manifest validation against Ambxst's schema and backend.

The JSON-Schema evaluator below is intentionally dependency-free (no
`jsonschema` module is required) but drives validation directly from the real
`manifest.schema.json` document shipped in docs/mods/ (byte-identical to
Ambxst's docs, verified by verify.sh when a target is given). It implements the
keywords this schema actually uses, so the effectiveness comes from the schema
document itself, not from copied checks.

A second layer mirrors backend/pkg/mods/manifest.go Validate(): constraints the
schema cannot express with plain JSON Schema (source files must exist and be
regular inside the package, `expectedSha256` is forbidden without
`replace: true`, dependencies must not be self-references, dependencySources
must sit in dependencies, and the package tree must not contain symlinks).
"""
import json
import os
import re
import sys
from pathlib import Path

MANIFEST_SCHEMA = Path(__file__).resolve().parents[1] / "docs" / "mods" / "manifest.schema.json"

ID_PATTERN = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SHA256_PATTERN = re.compile(r"^[a-fA-F0-9]{64}$")


class ValidationError(Exception):
    pass


# ---------------------------------------------------------------------------
# Minimal JSON-Schema (draft 2020-12) evaluator for the keyword subset the
# manifest schema uses. `$ref` is resolved inside the same document ($defs).
# ---------------------------------------------------------------------------

_DEFS: dict = {}


def _safe_ref(ref):
    if not ref.startswith("#/$defs/"):
        raise ValidationError(f"referencia externa no soportada: {ref!r}")
    name = ref[len("#/$defs/"):]
    if name not in _DEFS:
        raise ValidationError(f"definición desconocida: {name!r}")
    return _DEFS[name]


def _json_type(value):
    """JSON type of a parsed value; booleans are never integers."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def _matches_type(node, expected):
    kind = _json_type(node)
    if expected == "integer":
        return kind == "integer"
    if expected == "number":
        return kind in ("integer", "number")
    return kind == expected


def _const_equal(node, required):
    return _json_type(node) == _json_type(required) and node == required


def _validate(node, schema, errors, path, depth=0):
    if not isinstance(schema, dict):
        return
    if depth > 50:
        errors.append(f"{path}: recursión excesiva")
        return

    if "$ref" in schema:
        local = []
        _validate(node, _safe_ref(schema["$ref"]), local, path, depth + 1)
        errors.extend(local)
        return

    if "type" in schema:
        expected = schema["type"]
        types = expected if isinstance(expected, list) else [expected]
        if not any(_matches_type(node, t) for t in types):
            errors.append(f"{path}: se esperaba {expected}, se obtuvo {type(node).__name__}")

    if "const" in schema and not _const_equal(node, schema["const"]):
        errors.append(f"{path}: debe ser {schema['const']!r}, se obtuvo {node!r}")

    if "required" in schema and isinstance(node, dict):
        for name in schema["required"]:
            if name not in node:
                errors.append(f"{path}: falta la propiedad requerida {name!r}")

    if "propertyNames" in schema and isinstance(node, dict):
        for key in node:
            _validate(key, schema["propertyNames"], errors, path)

    if "properties" in schema and isinstance(node, dict):
        props = schema["properties"]
        for key, subschema in props.items():
            if key in node:
                _validate(node[key], subschema, errors, f"{path}.{key}")

    if "additionalProperties" in schema and isinstance(node, dict):
        added = schema["additionalProperties"]
        props = schema.get("properties", {})
        if added is False:
            for key in node:
                if key not in props:
                    errors.append(f"{path}: propiedad desconocida {key!r}")
        elif isinstance(added, dict):
            for key, value in node.items():
                if key not in props:
                    _validate(value, added, errors, f"{path}.{key}")

    if "items" in schema and isinstance(node, list):
        for index, value in enumerate(node):
            _validate(value, schema["items"], errors, f"{path}[{index}]")

    for keyword in ("pattern",):
        if keyword in schema and isinstance(node, str):
            if not re.search(schema[keyword], node):
                errors.append(f"{path}: no cumple el patrón {schema[keyword]!r}")

    for keyword, op in (("minLength", "longitud"), ("maxLength", "longitud"),
                        ("minItems", "cantidad"), ("maxItems", "cantidad")):
        if keyword in schema and isinstance(node, (str, list)) and keyword.startswith("min") and len(node) < schema[keyword]:
            errors.append(f"{path}: {op} inferior a {schema[keyword]}")
        elif keyword in schema and isinstance(node, (str, list)) and keyword.startswith("max") and len(node) > schema[keyword]:
            errors.append(f"{path}: {op} superior a {schema[keyword]}")

    if "uniqueItems" in schema and schema["uniqueItems"] and isinstance(node, list):
        seen = []
        for item in node:
            if item in seen:
                errors.append(f"{path}: elemento repetido {item!r}")
            seen.append(item)

    if "oneOf" in schema:
        passing = 0
        for alternative in schema["oneOf"]:
            local = []
            _validate(node, alternative, local, path, depth + 1)
            if not local:
                passing += 1
        if passing != 1:
            errors.append(f"{path}: debe coincidir exactamente con una alternativa (coinciden {passing})")

    if "allOf" in schema:
        for clause in schema["allOf"]:
            _validate(node, clause, errors, path, depth + 1)

    if "not" in schema:
        local = []
        _validate(node, schema["not"], local, path, depth + 1)
        if not local:
            errors.append(f"{path}: no debe coincidir con el esquema")

    if "if" in schema and "then" in schema:
        local = []
        _validate(node, schema["if"], local, path, depth + 1)
        if not local:
            _validate(node, schema["then"], errors, path, depth + 1)


def validate_schema(document, schema):
    """Validate `document` against the parsed `schema`. Raises ValidationError."""
    if not isinstance(schema, dict) or not isinstance(document, dict):
        raise ValidationError("schema o documento no es un objeto")
    _DEFS.update(schema.get("$defs", {}))
    errors = []
    _validate(document, schema, errors, "$")
    if errors:
        raise ValidationError("\n".join(errors))


# ---------------------------------------------------------------------------
# Backend parity (backend/pkg/mods/manifest.go Validate + safeJoin + tree scan)
# ---------------------------------------------------------------------------

def _is_safe_relative(path):
    if not isinstance(path, str) or path == "" or os.path.isabs(path):
        return False
    clean = os.path.normpath(path)
    return clean != "." and clean != ".." and not clean.startswith(".." + os.sep)


def _check(condition, message):
    if not condition:
        raise ValidationError(message)


def _validate_sources_and_tree(manifest, root):
    for index, op in enumerate(manifest.get("operations", []), start=1):
        op_type = op.get("type")
        source = op.get("source", "")
        _check(_is_safe_relative(source), f"operación {index}: source inseguro {source!r}")
        source_path = os.path.join(root, os.path.normpath(source))
        _check(os.path.isfile(source_path) and not os.path.islink(source_path),
               f"operación {index}: source no es un archivo regular: {source}")
        if op_type == "overlay":
            target = op.get("target", "")
            _check(_is_safe_relative(target), f"operación {index}: target inseguro {target!r}")
            _check(not op.get("replace") or op.get("expectedSha256"),
                   f"operación {index}: replace exige expectedSha256")
            _check(not op.get("expectedSha256") or op.get("replace"),
                   f"operación {index}: expectedSha256 sin replace no está permitido")
            if op.get("expectedSha256"):
                _check(bool(SHA256_PATTERN.fullmatch(op["expectedSha256"])),
                       f"operación {index}: expectedSha256 inválido")
        else:
            _check(not op.get("target") and not op.get("replace") and not op.get("expectedSha256"),
                   f"operación {index}: campos de overlay en una operación patch")

    for current, directories, files in os.walk(root):
        if ".git" in directories:
            directories.remove(".git")
        for entry in directories + files:
            candidate = os.path.join(current, entry)
            _check(not os.path.islink(candidate),
                   f"el paquete no debe contener enlaces simbólicos: {os.path.relpath(candidate, root)}")


def _backend_validate(manifest, root):
    mod_id = manifest.get("id", "")
    _check(bool(ID_PATTERN.fullmatch(mod_id)), f"id inválido: {mod_id!r}")
    name = manifest.get("name", "")
    _check(isinstance(name, str) and name.strip() != "", "name es obligatorio")
    version = manifest.get("version", "")
    _check(bool(VERSION_PATTERN.fullmatch(version)), f"version inválida: {version!r}")
    compat_api = (manifest.get("compatibility") or {}).get("api", 0)
    _check(compat_api in (0, 1), f"api no soportado: {compat_api!r}")

    references = []
    for dep in manifest.get("dependencies", []):
        _check(bool(ID_PATTERN.fullmatch(dep)), f"dependency/conflict id inválido: {dep!r}")
        _check(dep != mod_id, "no puede referenciarse a sí mismo como dependency o conflict")
        _check(dep not in references, f"duplicate dependency/conflict {dep!r}")
        references.append(dep)
    for conflict in manifest.get("conflicts", []):
        _check(bool(ID_PATTERN.fullmatch(conflict)), f"dependency/conflict id inválido: {conflict!r}")
        _check(conflict != mod_id, "no puede referenciarse a sí mismo como dependency o conflict")
        _check(conflict not in references, f"duplicate dependency/conflict {conflict!r}")
        references.append(conflict)

    declared_deps = set(manifest.get("dependencies", []))
    for dep_id, source in (manifest.get("dependencySources") or {}).items():
        _check(bool(ID_PATTERN.fullmatch(dep_id)), f"dependency source id inválido: {dep_id!r}")
        _check(dep_id in declared_deps, f"dependency source {dep_id!r} no está declarada como dependency")
        _check(isinstance(source, str) and source.strip() != "", f"dependency source {dep_id!r} está vacía")

    _validate_sources_and_tree(manifest, root)


def validate_manifest(manifest_path, root, schema_path=None):
    """Parse + schema-validate + backend-validate. Raises ValidationError."""
    try:
        document = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    except Exception as error:  # noqa: BLE001 - surface any JSON failure
        raise ValidationError(f"parse manifest: {error}") from error
    schema = json.loads(Path(schema_path or MANIFEST_SCHEMA).read_text(encoding="utf-8"))
    validate_schema(document, schema)
    _backend_validate(document, root)
    return document


def main(argv):
    if len(argv) not in (2, 3):
        print("Uso: python3 manifest_validate.py <ambxst.mod.json> <package-root> [schema-path]", file=sys.stderr)
        return 2
    try:
        validate_manifest(argv[0], argv[1], argv[2] if len(argv) == 3 else None)
    except ValidationError as error:
        print(f"ERROR: manifest inválido: {error}", file=sys.stderr)
        return 1
    print("OK: manifiesto válido contra el schema y el backend de Ambxst.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))