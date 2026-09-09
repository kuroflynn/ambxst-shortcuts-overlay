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
if git -C "${ROOT_ACCESS}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
    [[ "${installed_files}" == matching ]] || fail "La instalación existente no es regular"
    printf 'OK: el overlay ya está instalado y coincide con el proyecto.\n'
    exit 0
fi
[[ "${installed_files}" == absent ]] || fail "Existen archivos sin una integración reconocible"
git -C "${ROOT_ACCESS}" apply --check "${PATCH_FILE}" || exit 1

published=()
RECOVERY_PATH=""
OVERLAY_ACCESS=""
overlay_dir_created=false
[[ -e "${WIDGETS_ACCESS}/shortcuts" ]] || overlay_dir_created=true

rollback() {
    local status=$? failed=false patch_safe=false name target retired
    trap - EXIT
    set +e # Record every unsafe recovery step instead of aborting the EXIT trap.
    printf 'ERROR: la instalación falló; intentando restaurar el estado previo.\n' >&2
    if ! check_pinned_paths || ! validate_ambxst_paths "${TARGET_ROOT}"; then
        failed=true
    elif git -C "${ROOT_ACCESS}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
        if git -C "${ROOT_ACCESS}" apply --reverse "${PATCH_FILE}"; then patch_safe=true
        else
            ambxst_target_error "falló la reversión del parche; revisa ${TARGET_ROOT}/shell.qml, ${TARGET_ROOT}/modules/services/Visibilities.qml y ${TARGET_ROOT}/modules/services/GlobalShortcuts.qml"
            failed=true
        fi
    elif git -C "${ROOT_ACCESS}" apply --check "${PATCH_FILE}" >/dev/null 2>&1; then patch_safe=true
    else
        ambxst_target_error "El parche cambió; recuperación manual para ${TARGET_ROOT}/shell.qml, ${TARGET_ROOT}/modules/services/Visibilities.qml y ${TARGET_ROOT}/modules/services/GlobalShortcuts.qml"
        failed=true
    fi
    if [[ "${patch_safe}" == true ]]; then
        for name in "${published[@]}"; do
            target="${OVERLAY_ACCESS}/${name}"
            [[ "$(ambxst_path_kind "${target}")" != absent ]] || continue
            # Replacement files are not ours. In-place edits retain the original
            # durable inode link; leave the visible edited file where it is.
            if [[ "$(ambxst_path_kind "${target}")" != file || ! "${target}" -ef "${RECOVERY_TX_ACCESS}/${name}" ]] \
                    || ! cmp -s "${SOURCE_DIR}/${name}" "${target}"; then
                ambxst_target_error "${TARGET_ROOT}/modules/widgets/shortcuts/${name} fue modificado durante la transacción; no se retiró."
                failed=true; continue
            fi
            retired="${RECOVERY_TX_ACCESS}/retired-${name}"
            if ! move_exact "${target}" "${retired}"; then failed=true; continue; fi
            if [[ "$(ambxst_path_kind "${retired}")" != file ]] || ! cmp -s "${SOURCE_DIR}/${name}" "${retired}"; then
                ambxst_target_error "${name} cambió durante rollback; se conservó ${RECOVERY_PATH}/retired-${name}"
                restore_exact "${retired}" "${target}" "${TARGET_ROOT}/modules/widgets/shortcuts/${name}" || :
                failed=true
            fi
        done
    fi
    if [[ "${overlay_dir_created}" == true && -n "${OVERLAY_ACCESS}" ]] && check_pinned_paths; then
        rmdir -- "${WIDGETS_ACCESS}/shortcuts" 2>/dev/null || : # preserve nonempty directories
    fi
    report_recovery
    [[ "${failed}" == false ]] || ambxst_target_error "rollback incompleto; revisa las rutas indicadas para recuperación manual."
    (( status != 0 )) || status=1
    exit "${status}"
}
trap rollback EXIT
open_overlay_directory
create_recovery install

publish_file() {
    local name="$1" candidate source="${SOURCE_DIR}/$1" staged="${RECOVERY_TX_ACCESS}/$1"
    check_pinned_paths || return 1
    candidate="$(stage_file "${name}" "${SOURCE_DIR}")" || return 1
    move_exact "${candidate}" "${staged}"
    [[ "$(ambxst_path_kind "${staged}")" == file ]] && cmp -s "${source}" "${staged}" \
        || fail "La copia preparada de ${name} cambió"
    # The staged name survives both commit and rollback (including open FDs).
    if ! link_exact "${staged}" "${OVERLAY_ACCESS}/${name}"; then
        fail "no se publicó ${TARGET_ROOT}/modules/widgets/shortcuts/${name}; destino concurrente o ruta modificada."
    fi
    published+=("${name}")
    cmp -s "${source}" "${OVERLAY_ACCESS}/${name}" || fail "${name} cambió durante publicación"
}
publish_file ShortcutsOverlay.qml
publish_file ShortcutData.js
check_pinned_paths
validate_ambxst_paths "${TARGET_ROOT}"
git -C "${ROOT_ACCESS}" apply "${PATCH_FILE}"
check_pinned_paths
"${SCRIPT_DIR}/verify.sh" "${TARGET_ROOT}"
check_pinned_paths
trap - EXIT
report_recovery
printf 'OK: overlay instalado. No se modificó binds.json y no se recargó Ambxst.\n'
