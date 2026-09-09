#!/usr/bin/env bash
set -euo pipefail
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
source "${SCRIPT_DIR}/common.sh"
fail() { ambxst_target_error "$*"; exit 1; }
TARGET_ROOT="$(resolve_ambxst_target "$@")" || exit 1
readonly TARGET_ROOT
readonly PATCH_FILE="${PROJECT_ROOT}/patches/ambxst-integration.patch"
readonly SOURCE_DIR="${PROJECT_ROOT}/src/modules/widgets/shortcuts"
begin_deployment || exit 1
"${SCRIPT_DIR}/verify.sh" "${TARGET_ROOT}"
installed_files="$(classify_overlay_files "${TARGET_ROOT}" "${SOURCE_DIR}")" || exit 1
if ! git -C "${ROOT_ACCESS}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
    [[ "${installed_files}" == absent ]] && git -C "${ROOT_ACCESS}" apply --check "${PATCH_FILE}" >/dev/null 2>&1 \
        || fail "El parche inverso no puede aplicarse limpiamente; no se retiró nada"
    printf 'OK: el overlay ya está retirado. Las recuperaciones previas se conservan.\n'
    printf 'Si ya no lo necesitas, retira manualmente el bind personal SUPER + /.\n'
    exit 0
fi
[[ "${installed_files}" == matching ]] || fail "La instalación no coincide con el proyecto"
open_overlay_directory
moved=()
RECOVERY_PATH=""

rollback() {
    local status=$? failed=false name
    trap - EXIT
    set +e # Record every unsafe recovery step instead of aborting the EXIT trap.
    printf 'ERROR: la desinstalación falló; intentando restaurar la instalación.\n' >&2
    if check_pinned_paths && validate_ambxst_paths "${TARGET_ROOT}"; then
        for name in "${moved[@]}"; do
            restore_exact "${RECOVERY_TX_ACCESS}/${name}" "${OVERLAY_ACCESS}/${name}" \
                "${TARGET_ROOT}/modules/widgets/shortcuts/${name}" || failed=true
        done
        if git -C "${ROOT_ACCESS}" apply --check "${PATCH_FILE}" >/dev/null 2>&1; then
            if ! git -C "${ROOT_ACCESS}" apply "${PATCH_FILE}"; then
                ambxst_target_error "falló la reaplicación del parche; revisa ${TARGET_ROOT}/shell.qml, ${TARGET_ROOT}/modules/services/Visibilities.qml y ${TARGET_ROOT}/modules/services/GlobalShortcuts.qml"
                failed=true
            fi
        elif ! git -C "${ROOT_ACCESS}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
            ambxst_target_error "El parche cambió; recuperación manual para ${TARGET_ROOT}/shell.qml, ${TARGET_ROOT}/modules/services/Visibilities.qml y ${TARGET_ROOT}/modules/services/GlobalShortcuts.qml"
            failed=true
        fi
    else failed=true
    fi
    report_recovery
    [[ "${failed}" == false ]] || ambxst_target_error "rollback incompleto; revisa las rutas indicadas para recuperación manual."
    (( status != 0 )) || status=1
    exit "${status}"
}
trap rollback EXIT
create_recovery uninstall
check_pinned_paths
validate_ambxst_paths "${TARGET_ROOT}"
git -C "${ROOT_ACCESS}" apply --reverse "${PATCH_FILE}"
for name in ShortcutsOverlay.qml ShortcutData.js; do
    if ! move_exact "${OVERLAY_ACCESS}/${name}" "${RECOVERY_TX_ACCESS}/${name}"; then
        if [[ "$(ambxst_path_kind "${OVERLAY_ACCESS}/${name}")" == absent ]]; then
            fail "${TARGET_ROOT}/modules/widgets/shortcuts/${name} desapareció concurrentemente; no se recreará."
        fi
        fail "No se pudo mover ${name} a ${RECOVERY_PATH}"
    fi
    moved+=("${name}")
    check_pinned_paths
    [[ "$(ambxst_path_kind "${RECOVERY_TX_ACCESS}/${name}")" == file ]] \
        && cmp -s "${SOURCE_DIR}/${name}" "${RECOVERY_TX_ACCESS}/${name}" \
        || fail "${name} cambió durante la desinstalación; se conservará y se intentará restaurar."
done
"${SCRIPT_DIR}/verify.sh" "${TARGET_ROOT}"
check_pinned_paths
for name in ShortcutsOverlay.qml ShortcutData.js; do
    [[ "$(ambxst_path_kind "${OVERLAY_ACCESS}/${name}")" == absent ]] || fail "${name} reapareció después de verificar"
    [[ "$(ambxst_path_kind "${RECOVERY_TX_ACCESS}/${name}")" == file ]] \
        && cmp -s "${SOURCE_DIR}/${name}" "${RECOVERY_TX_ACCESS}/${name}" \
        || fail "${name} cambió en la recuperación; se activará rollback"
done
trap - EXIT
# Commit retires the runtime names; never unlink the retained inodes. A writer
# with an open descriptor can write after the last comparison, even after exit.
rmdir -- "${WIDGETS_ACCESS}/shortcuts" 2>/dev/null || : # only if empty
report_recovery
printf 'OK: overlay retirado. No se modificó binds.json y no se recargó Ambxst.\n'
printf 'Si ya no lo necesitas, retira manualmente el bind personal SUPER + /.\n'
