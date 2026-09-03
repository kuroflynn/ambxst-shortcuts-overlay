#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

TARGET_ROOT="$(resolve_ambxst_target "$@")" || exit 1
readonly TARGET_ROOT
readonly PATCH_FILE="${PROJECT_ROOT}/patches/ambxst-integration.patch"
readonly SOURCE_DIR="${PROJECT_ROOT}/src/modules/widgets/shortcuts"
readonly SOURCE_OVERLAY="${SOURCE_DIR}/ShortcutsOverlay.qml"
readonly SOURCE_DATA="${SOURCE_DIR}/ShortcutData.js"
readonly TARGET_DIR="${TARGET_ROOT}/modules/widgets/shortcuts"
readonly TARGET_OVERLAY="${TARGET_DIR}/ShortcutsOverlay.qml"
readonly TARGET_DATA="${TARGET_DIR}/ShortcutData.js"

"${PROJECT_ROOT}/scripts/verify.sh" "${TARGET_ROOT}"

if ! git -C "${TARGET_ROOT}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
    if git -C "${TARGET_ROOT}" apply --check "${PATCH_FILE}" >/dev/null 2>&1 \
            && [[ ! -e "${TARGET_OVERLAY}" && ! -L "${TARGET_OVERLAY}" \
                && ! -e "${TARGET_DATA}" && ! -L "${TARGET_DATA}" ]]; then
        printf 'OK: el overlay ya está retirado.\n'
        exit 0
    fi
    fail "El parche inverso no puede aplicarse limpiamente; no se retiró nada"
fi

[[ -d "${TARGET_DIR}" && ! -L "${TARGET_DIR}" ]] \
    || fail "El directorio instalado del overlay falta o no es regular"
[[ -f "${TARGET_OVERLAY}" && ! -L "${TARGET_OVERLAY}" \
    && -f "${TARGET_DATA}" && ! -L "${TARGET_DATA}" ]] \
    || fail "Instalación parcial: faltan archivos regulares del overlay"
cmp -s "${SOURCE_OVERLAY}" "${TARGET_OVERLAY}" || fail "ShortcutsOverlay.qml fue modificado manualmente; no se retiró"
cmp -s "${SOURCE_DATA}" "${TARGET_DATA}" || fail "ShortcutData.js fue modificado manualmente; no se retiró"

rollback_needed=true
overlay_moved=false
data_moved=false
quarantine_dir=""
overlay_quarantine=""
data_quarantine=""

is_safe_quarantine_path() {
    local path="$1"
    [[ -n "${path}" && -n "${quarantine_dir}" \
        && "${path}" == "${quarantine_dir}/"* && "${path}" != "${quarantine_dir}" ]]
}

restore_moved_file() {
    local target="$1"
    local quarantine="$2"
    local moved_name="$3"
    local -n moved_ref="${moved_name}"

    [[ "${moved_ref}" == true ]] || return 0
    if ! is_safe_quarantine_path "${quarantine}" \
            || [[ ! -e "${quarantine}" && ! -L "${quarantine}" ]]; then
        printf 'ERROR: falta la cuarentena esperada %s para restaurar %s.\n' \
            "${quarantine}" "${target}" >&2
        return 1
    fi
    if [[ -e "${target}" || -L "${target}" ]]; then
        printf 'ERROR: reapareció %s; no se sobrescribió y se conservó %s para recuperación manual.\n' \
            "${target}" "${quarantine}" >&2
        return 1
    fi
    if ! ln -P -- "${quarantine}" "${target}"; then
        printf 'ERROR: no se pudo restaurar %s sin sobrescribir; se conservó %s.\n' \
            "${target}" "${quarantine}" >&2
        return 1
    fi
    if ! rm -- "${quarantine}"; then
        printf 'ERROR: %s fue restaurado, pero no se pudo limpiar su cuarentena %s.\n' \
            "${target}" "${quarantine}" >&2
        return 1
    fi
    moved_ref=false
}

rollback() {
    local status=$?
    local rollback_failed=false

    trap - EXIT
    [[ "${rollback_needed}" == true ]] || exit "${status}"
    printf 'ERROR: la desinstalación falló; intentando restaurar la instalación.\n' >&2

    restore_moved_file "${TARGET_OVERLAY}" "${overlay_quarantine}" overlay_moved || rollback_failed=true
    restore_moved_file "${TARGET_DATA}" "${data_quarantine}" data_moved || rollback_failed=true

    if git -C "${TARGET_ROOT}" apply --check "${PATCH_FILE}" >/dev/null 2>&1; then
        if ! git -C "${TARGET_ROOT}" apply "${PATCH_FILE}" >/dev/null; then
            printf 'ERROR: falló la reaplicación del parche; recuperación manual requerida para %s, %s y %s.\n' \
                "${TARGET_ROOT}/modules/services/GlobalShortcuts.qml" \
                "${TARGET_ROOT}/modules/services/Visibilities.qml" \
                "${TARGET_ROOT}/shell.qml" >&2
            rollback_failed=true
        fi
    elif ! git -C "${TARGET_ROOT}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
        printf 'ERROR: el parche cambió durante la transacción y no puede reaplicarse. Revisa manualmente %s, %s y %s.\n' \
            "${TARGET_ROOT}/modules/services/GlobalShortcuts.qml" \
            "${TARGET_ROOT}/modules/services/Visibilities.qml" \
            "${TARGET_ROOT}/shell.qml" >&2
        rollback_failed=true
    fi

    if [[ -n "${quarantine_dir}" && -d "${quarantine_dir}" ]]; then
        if ! rmdir -- "${quarantine_dir}" >/dev/null 2>&1; then
            printf 'ERROR: se conservó la cuarentena no vacía %s para recuperación manual.\n' \
                "${quarantine_dir}" >&2
            rollback_failed=true
        fi
    fi

    if [[ "${rollback_failed}" == true ]]; then
        printf 'ERROR: rollback incompleto; revisa los archivos indicados antes de volver a ejecutar el desinstalador.\n' >&2
    fi
    (( status != 0 )) || status=1
    exit "${status}"
}
trap rollback EXIT

candidate_quarantine=""
if ! candidate_quarantine="$(mktemp -d -- "${TARGET_DIR}/.ambxst-shortcuts-uninstall.XXXXXX")"; then
    fail "No se pudo crear una cuarentena dentro de ${TARGET_DIR}"
fi
if [[ -n "${candidate_quarantine}" && "${candidate_quarantine}" == "${TARGET_DIR}/"* \
    && "${candidate_quarantine}" != "${TARGET_DIR}" ]]; then
    quarantine_dir="${candidate_quarantine}"
fi
if [[ -z "${candidate_quarantine}" || "${candidate_quarantine}" != /* \
    || ! -d "${candidate_quarantine}" || -L "${candidate_quarantine}" \
    || -z "${quarantine_dir}" ]]; then
    fail "mktemp devolvió una cuarentena insegura: ${candidate_quarantine:-<vacía>}"
fi
overlay_quarantine="${quarantine_dir}/ShortcutsOverlay.qml"
data_quarantine="${quarantine_dir}/ShortcutData.js"

move_to_quarantine() {
    local source="$1"
    local target="$2"
    local quarantine="$3"
    local moved_name="$4"
    local -n moved_ref="${moved_name}"

    if ! mv -- "${target}" "${quarantine}"; then
        if [[ ! -e "${target}" && ! -L "${target}" ]]; then
            printf 'ERROR: %s desapareció concurrentemente; no se recreará durante rollback.\n' "${target}" >&2
        else
            printf 'ERROR: no se pudo mover %s a la cuarentena %s.\n' "${target}" "${quarantine}" >&2
        fi
        return 1
    fi
    moved_ref=true

    if cmp -s "${source}" "${quarantine}"; then
        return 0
    fi

    printf 'ERROR: %s cambió durante la desinstalación; no se eliminará.\n' "${target}" >&2
    if restore_moved_file "${target}" "${quarantine}" "${moved_name}"; then
        printf 'ERROR: el contenido modificado fue restaurado en %s.\n' "${target}" >&2
    fi
    return 1
}

git -C "${TARGET_ROOT}" apply --reverse "${PATCH_FILE}"
move_to_quarantine "${SOURCE_OVERLAY}" "${TARGET_OVERLAY}" "${overlay_quarantine}" overlay_moved
move_to_quarantine "${SOURCE_DATA}" "${TARGET_DATA}" "${data_quarantine}" data_moved

"${PROJECT_ROOT}/scripts/verify.sh" "${TARGET_ROOT}"

[[ "${overlay_moved}" == true && "${data_moved}" == true ]] \
    || fail "La desinstalación no tiene ambos archivos en cuarentena"
[[ ! -e "${TARGET_OVERLAY}" && ! -L "${TARGET_OVERLAY}" \
    && ! -e "${TARGET_DATA}" && ! -L "${TARGET_DATA}" ]] \
    || fail "Un archivo reapareció después de la verificación; se activará el rollback"
cmp -s "${SOURCE_OVERLAY}" "${overlay_quarantine}" \
    || fail "ShortcutsOverlay.qml cambió dentro de la cuarentena; se activará el rollback"
cmp -s "${SOURCE_DATA}" "${data_quarantine}" \
    || fail "ShortcutData.js cambió dentro de la cuarentena; se activará el rollback"

rollback_needed=false
trap - EXIT

if ! rm -- "${overlay_quarantine}"; then
    fail "Desinstalación terminada, pero no se pudo limpiar la cuarentena ${overlay_quarantine}"
fi
overlay_moved=false
if ! rm -- "${data_quarantine}"; then
    fail "Desinstalación terminada, pero no se pudo limpiar la cuarentena ${data_quarantine}"
fi
data_moved=false
if ! rmdir -- "${quarantine_dir}"; then
    fail "Desinstalación terminada, pero no se pudo retirar la cuarentena ${quarantine_dir}"
fi
quarantine_dir=""
# El directorio puede contener material ajeno y solo se retira si está vacío.
rmdir -- "${TARGET_DIR}" >/dev/null 2>&1 || :
printf 'OK: overlay retirado. No se modificó binds.json y no se recargó Ambxst.\n'
