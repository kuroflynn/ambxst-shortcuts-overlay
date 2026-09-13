#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly MANIFEST_FILE="${PROJECT_ROOT}/ambxst.mod.json"
readonly MANIFEST_SCHEMA="${PROJECT_ROOT}/docs/mods/manifest.schema.json"
readonly PATCH_FILE="${PROJECT_ROOT}/patches/ambxst-integration.patch"
readonly PAYLOAD_DIR="${PROJECT_ROOT}/payload"
readonly TEST_FILE_JS="${PROJECT_ROOT}/tests/shortcut-data.test.js"
readonly TEST_FILE_HARDENING="${PROJECT_ROOT}/tests/hardening.test.js"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    local code="$1"
    local text
    text="$(cat <<'EOF'
Uso:
  verify.sh --package-only              Valida solo el paquete (sin destino Ambxst).
  verify.sh /ruta/a/ambxst              Valida el paquete y compone contra el destino
                                        Ambxst dado (solo lectura; `/tmp` únicamente).
  verify.sh -h | --help                 Muestra esta ayuda y sale con 0.

Sin argumentos el script falla: no existe resolución automática de destino
(no se consulta AMBXST_SOURCE_DIR ni registro alguno).
EOF
)"
    if [[ "${code}" -eq 0 ]]; then
        printf '%s\n' "${text}"
    else
        printf '%s\n' "${text}" >&2
    fi
    exit "${code}"
}

if (( $# == 0 )); then
    usage 1
fi

case "${1}" in
    -h|--help)
        usage 0
        ;;
    --package-only)
        (( $# == 1 )) || usage 1
        TARGET_ROOT=""
        ;;
    *)
        (( $# == 1 )) || usage 1
        [[ -n "${1}" ]] || usage 1
        TARGET_ROOT="${1}"
        ;;
esac

# ---------------------------------------------------------------------------
# 1. Required project files
# ---------------------------------------------------------------------------

required_project_files=(
    "${PROJECT_ROOT}/AGENTS.md"
    "${PROJECT_ROOT}/REQUIREMENTS.md"
    "${PROJECT_ROOT}/README.md"
    "${PROJECT_ROOT}/CHANGELOG.md"
    "${PROJECT_ROOT}/LICENSE"
    "${PROJECT_ROOT}/ambxst-shortcuts-overlay.code-workspace"
    "${MANIFEST_FILE}"
    "${MANIFEST_SCHEMA}"
    "${PATCH_FILE}"
    "${PROJECT_ROOT}/scripts/verify.sh"
    "${PROJECT_ROOT}/scripts/manifest_validate.py"
    "${PROJECT_ROOT}/scripts/compose.py"
    "${TEST_FILE_JS}"
    "${TEST_FILE_HARDENING}"
)

for file in "${required_project_files[@]}"; do
    [[ -f "${file}" ]] || fail "Falta un archivo del proyecto: ${file}"
done

# bash constraints: the first operand may be a manifest, targets, or scripts.
for script in "${PROJECT_ROOT}/scripts/"*.sh "${PROJECT_ROOT}/tests/"*.sh; do
    bash -n "${script}"
done

# ---------------------------------------------------------------------------
# 2. Manifest validation (effective: Ambxst schema + backend parity)
# ---------------------------------------------------------------------------

python3 "${SCRIPT_DIR}/manifest_validate.py" "${MANIFEST_FILE}" "${PROJECT_ROOT}" \
    || fail "el manifiesto no es válido"

# Maintainer contract for this release (the packaging policy, complementary to
# the schema/backend validation above; tests/manifest.test.py enforces the same).
python3 - "${MANIFEST_FILE}" "${PROJECT_ROOT}" <<'PY' || fail "la política de paquete no se cumple"
import json
import os
import re
import sys

manifest_path, root = sys.argv[1], sys.argv[2]
data = json.load(open(manifest_path, encoding="utf-8"))

def die(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)

if data.get("id") != "kurostain.shortcuts-overlay":
    die(f"id inesperado: {data.get('id')!r}")
if data.get("license") != "MIT":
    die(f"license debe ser MIT, se obtuvo {data.get('license')!r}")
if data.get("author") != "KuroStain":
    die(f"author debe ser KuroStain, se obtuvo {data.get('author')!r}")
compat = data.get("compatibility") or {}
if compat.get("api") != 1:
    die(f"compatibility.api debe ser 1, se obtuvo {compat.get('api')!r}")
if compat.get("ambxst") != ">=1.3.3 <1.4.0":
    die(f"compatibility.ambxst debe ser '>=1.3.3 <1.4.0', se obtuvo {compat.get('ambxst')!r}")
tested = compat.get("testedBaseCommits") or []
if tested != ["af9f8ad4f42d7cd77f57a7c75f6a2a5d1fb59674"]:
    die(f"testedBaseCommits fuera de la lista comprobada: {tested!r}")
for key in ("dependencies", "conflicts", "commands"):
    if data.get(key):
        die(f"{key} debe estar vacío; el paquete no los declara")
if data.get("dependencySources"):
    die("dependencySources debe estar ausente o vacío")
if data.get("settings") is not None:
    die("settings debe estar ausente; el paquete no declara ajustes")
permissions = data.get("permissions") or []
if not isinstance(permissions, list) or not permissions or any(not isinstance(p, str) or not p.strip() for p in permissions):
    die("permissions debe ser una lista descriptiva no vacía")
expected_operations = [
    ("overlay", "payload/modules/widgets/shortcuts/ShortcutsOverlay.qml", "modules/widgets/shortcuts/ShortcutsOverlay.qml"),
    ("overlay", "payload/modules/widgets/shortcuts/ShortcutData.js", "modules/widgets/shortcuts/ShortcutData.js"),
    ("patch", "patches/ambxst-integration.patch", ""),
]
operations = data.get("operations")
if not isinstance(operations, list) or len(operations) != 3:
    die(f"operations debe contener exactamente 3 operaciones")
for index, (op, expected) in enumerate(zip(operations, expected_operations), start=1):
    signature = (op.get("type"), op.get("source", ""), op.get("target", ""))
    if signature != expected:
        die(f"operación {index}: fuera del diseño esperado: {signature}")
if any(bool(op.get("replace")) or bool(op.get("expectedSha256")) for op in operations):
    die("las operaciones no deben declarar replace ni expectedSha256")
print("OK: política de paquete válida.")
PY

# ---------------------------------------------------------------------------
# 3. Payload and patch coherence
# ---------------------------------------------------------------------------

payload_files=(
    "${PAYLOAD_DIR}/modules/widgets/shortcuts/ShortcutsOverlay.qml"
    "${PAYLOAD_DIR}/modules/widgets/shortcuts/ShortcutData.js"
)
for file in "${payload_files[@]}"; do
    [[ -f "${file}" && ! -L "${file}" ]] || fail "Falta o no es regular un payload del manifiesto: ${file}"
done

mapfile -t patch_paths < <(git apply --numstat "${PATCH_FILE}" | awk '{ print $3 }' | LC_ALL=C sort)
expected_paths=(
    "modules/services/GlobalShortcuts.qml"
    "modules/services/Visibilities.qml"
    "shell.qml"
)
[[ "${#patch_paths[@]}" -eq "${#expected_paths[@]}" ]] || fail "El parche afecta una cantidad inesperada de archivos"
for index in "${!expected_paths[@]}"; do
    [[ "${patch_paths[index]}" == "${expected_paths[index]}" ]] || fail "Ruta no autorizada en el parche: ${patch_paths[index]}"
done
printf 'OK: el parche solo afecta %s.\n' "${expected_paths[*]}"

# ---------------------------------------------------------------------------
# 4. JavaScript / hardening tests
# ---------------------------------------------------------------------------

node "${TEST_FILE_JS}"
node "${TEST_FILE_HARDENING}"

# ---------------------------------------------------------------------------
# 5. qmllint (static, not a Quickshell runtime PASS)
# ---------------------------------------------------------------------------

qml_linter=""
if command -v qmllint6 >/dev/null 2>&1; then
    qml_linter="$(command -v qmllint6)"
elif [[ -x /usr/lib/qt6/bin/qmllint ]]; then
    qml_linter=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1; then
    qml_linter="$(command -v qmllint)"
fi
if [[ -n "${qml_linter}" ]]; then
    printf 'QML lint: %s (%s); no equivale a validación runtime de Quickshell.\n' "${qml_linter}" "$("${qml_linter}" --version 2>&1 | head -n 1)"
    "${qml_linter}" -I "${PAYLOAD_DIR}" \
        "${PAYLOAD_DIR}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
        "${PAYLOAD_DIR}/modules/widgets/shortcuts/ShortcutData.js"
else
    printf 'AVISO: qmllint no está disponible; se omitió esa comprobación.\n' >&2
fi

# ---------------------------------------------------------------------------
# 6. Composition against an explicit Ambxst target (read-only, /tmp only)
# ---------------------------------------------------------------------------

if [[ -z "${TARGET_ROOT}" ]]; then
    printf 'OK: paquete válido (verify.sh --package-only).\n'
    exit 0
fi

[[ "${TARGET_ROOT}" == /* ]] || fail "El destino debe ser una ruta absoluta: ${TARGET_ROOT}"
[[ -d "${TARGET_ROOT}" ]] || fail "El destino no existe o no es un directorio: ${TARGET_ROOT}"
[[ "${TARGET_ROOT}" != "/" ]] || fail "La raíz del sistema no puede ser un destino Ambxst"
if [[ -n "${HOME:-}" && -d "${HOME}" && "$(cd -- "${TARGET_ROOT}" && pwd -P)" == "$(cd -- "${HOME}" && pwd -P)" ]]; then
    fail "El directorio HOME completo no puede ser un destino Ambxst"
fi
[[ -f "${TARGET_ROOT}/version" \
    && -f "${TARGET_ROOT}/shell.qml" \
    && -f "${TARGET_ROOT}/modules/services/Visibilities.qml" \
    && -f "${TARGET_ROOT}/modules/services/GlobalShortcuts.qml" ]] \
    || fail "El destino no tiene la estructura esperada de Ambxst: ${TARGET_ROOT}"
git -C "${TARGET_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "El destino debe ser un árbol de trabajo Git de Ambxst: ${TARGET_ROOT}"
[[ "$(git -C "${TARGET_ROOT}" rev-parse --show-toplevel)" == "$(cd -- "${TARGET_ROOT}" && pwd -P)" ]] \
    || fail "El destino debe ser la raíz del árbol de trabajo de Ambxst: ${TARGET_ROOT}"

# The vendored schema must byte-match the target's own schema document.
target_schema="${TARGET_ROOT}/docs/mods/manifest.schema.json"
[[ -f "${target_schema}" ]] || fail "El destino no incluye docs/mods/manifest.schema.json"
vendor_sha="$(sha256sum "${MANIFEST_SCHEMA}" | awk '{ print $1 }')"
target_sha="$(sha256sum "${target_schema}" | awk '{ print $1 }')"
[[ "${vendor_sha}" == "${target_sha}" ]] \
    || fail "El schema vendado del paquete no coincide con el del destino Ambxst (drift)"

composition_root="$(mktemp -d /tmp/ambxst-shortcuts-overlay.verify.XXXXXX)"
readonly composition_root
cleanup() {
    rm -rf -- "${composition_root}"
}
trap cleanup EXIT

if ! compose_output="$(python3 "${SCRIPT_DIR}/compose.py" "${MANIFEST_FILE}" "${PROJECT_ROOT}" \
    "${TARGET_ROOT}" "${composition_root}" 2>&1)"; then
    printf '%s\n' "${compose_output}" >&2
    fail "la composición falló contra ${TARGET_ROOT}"
fi
printf '%s\n' "${compose_output}"

generation_dir="${composition_root}"

# Post-composition coherence (read-only snapshot of the delivered tree).
cmp -s "${PAYLOAD_DIR}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    "${generation_dir}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    || fail "ShortcutsOverlay.qml no quedó íntegro en la composición"
cmp -s "${PAYLOAD_DIR}/modules/widgets/shortcuts/ShortcutData.js" \
    "${generation_dir}/modules/widgets/shortcuts/ShortcutData.js" \
    || fail "ShortcutData.js no quedó íntegro en la composición"
grep -Fq 'import qs.modules.widgets.shortcuts' "${generation_dir}/shell.qml" \
    || fail "shell.qml no importa el módulo shortcuts"
grep -Fq 'ShortcutsOverlay {' "${generation_dir}/shell.qml" \
    || fail "shell.qml no instancia ShortcutsOverlay"
grep -Fq '"shortcuts"' "${generation_dir}/modules/services/Visibilities.qml" \
    || fail "Visibilities.qml no registra el módulo shortcuts"
grep -Fq 'case "shortcuts"' "${generation_dir}/modules/services/GlobalShortcuts.qml" \
    || fail "GlobalShortcuts.qml no registra el comando shortcuts"
printf 'OK: composición íntegra en directorio temporal (el árbol entregado no se modificó).\n'