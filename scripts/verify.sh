#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

TARGET_ROOT="$(resolve_ambxst_target "$@")" || exit 1
readonly TARGET_ROOT
readonly PATCH_FILE="${PROJECT_ROOT}/patches/ambxst-integration.patch"
readonly SOURCE_DIR="${PROJECT_ROOT}/src/modules/widgets/shortcuts"
readonly SOURCE_OVERLAY="${SOURCE_DIR}/ShortcutsOverlay.qml"
readonly SOURCE_DATA="${SOURCE_DIR}/ShortcutData.js"
readonly TEST_FILE="${PROJECT_ROOT}/tests/shortcut-data.test.js"

validate_ambxst_paths "${TARGET_ROOT}" || exit 1

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

required_project_files=(
    "${PROJECT_ROOT}/AGENTS.md"
    "${PROJECT_ROOT}/REQUIREMENTS.md"
    "${PROJECT_ROOT}/README.md"
    "${PROJECT_ROOT}/ambxst-shortcuts-overlay.code-workspace"
    "${SOURCE_OVERLAY}"
    "${SOURCE_DATA}"
    "${PATCH_FILE}"
    "${PROJECT_ROOT}/scripts/install.sh"
    "${PROJECT_ROOT}/scripts/uninstall.sh"
    "${PROJECT_ROOT}/scripts/verify.sh"
    "${PROJECT_ROOT}/scripts/common.sh"
    "${TEST_FILE}"
    "${PROJECT_ROOT}/tests/hardening.test.js"
    "${PROJECT_ROOT}/tests/transactional-scripts.test.sh"
    "${PROJECT_ROOT}/tests/fixtures/verify-stub.sh"
    "${PROJECT_ROOT}/tests/fixtures/git-wrapper.sh"
    "${PROJECT_ROOT}/tests/fixtures/fs-wrapper.sh"
)

for file in "${required_project_files[@]}"; do
    [[ -f "${file}" ]] || fail "Falta un archivo del proyecto: ${file}"
done

# Bash parses only its first script operand; remaining operands become $@.
for script in "${PROJECT_ROOT}/scripts/"*.sh \
    "${PROJECT_ROOT}/tests/"*.sh "${PROJECT_ROOT}/tests/fixtures/"*.sh; do
    bash -n "${script}"
done
node "${TEST_FILE}"
node "${PROJECT_ROOT}/tests/hardening.test.js"

qml_linter=""
if command -v qmllint6 >/dev/null 2>&1; then
    qml_linter="$(command -v qmllint6)"
elif [[ -x /usr/lib/qt6/bin/qmllint ]]; then
    qml_linter=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1; then
    qml_linter="$(command -v qmllint)"
fi
if [[ -n "${qml_linter}" ]]; then
    printf 'QML lint: %s (%s); no equivale a validación runtime de Quickshell.\n' "${qml_linter}" "$("${qml_linter}" --version 2>&1)"
    "${qml_linter}" -I "${TARGET_ROOT}" "${SOURCE_OVERLAY}" "${SOURCE_DATA}"
else
    printf 'AVISO: qmllint no está disponible; se omitió esa comprobación.\n' >&2
fi

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

direct_applies=false
inverse_applies=false
git -C "${TARGET_ROOT}" apply --check "${PATCH_FILE}" >/dev/null 2>&1 && direct_applies=true
git -C "${TARGET_ROOT}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1 && inverse_applies=true

readonly TARGET_OVERLAY="${TARGET_ROOT}/modules/widgets/shortcuts/ShortcutsOverlay.qml"
readonly TARGET_DATA="${TARGET_ROOT}/modules/widgets/shortcuts/ShortcutData.js"

installed_files="$(classify_overlay_files "${TARGET_ROOT}" "${SOURCE_DIR}")" || exit 1

if [[ "${direct_applies}" == true && "${inverse_applies}" == false && "${installed_files}" == "absent" ]]; then
    printf 'OK: proyecto válido; overlay no instalado en %s.\n' "${TARGET_ROOT}"
elif [[ "${direct_applies}" == false && "${inverse_applies}" == true && "${installed_files}" == "matching" ]]; then
    printf 'OK: proyecto válido; overlay instalado y coincidente en %s.\n' "${TARGET_ROOT}"
else
    fail "Estado ambiguo: parche directo=${direct_applies}, inverso=${inverse_applies}, archivos=${installed_files}"
fi
