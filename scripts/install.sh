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

if git -C "${TARGET_ROOT}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
    [[ -f "${TARGET_OVERLAY}" && ! -L "${TARGET_OVERLAY}" \
        && -f "${TARGET_DATA}" && ! -L "${TARGET_DATA}" ]] \
        || fail "La integración existe, pero los archivos instalados faltan o no son regulares"
    cmp -s "${SOURCE_OVERLAY}" "${TARGET_OVERLAY}" || fail "La copia instalada de ShortcutsOverlay.qml fue modificada"
    cmp -s "${SOURCE_DATA}" "${TARGET_DATA}" || fail "La copia instalada de ShortcutData.js fue modificada"
    printf 'OK: el overlay ya está instalado y coincide con el proyecto.\n'
    exit 0
fi

git -C "${TARGET_ROOT}" apply --check "${PATCH_FILE}" >/dev/null 2>&1 || fail "El parche no puede aplicarse limpiamente"
[[ ! -e "${TARGET_OVERLAY}" && ! -L "${TARGET_OVERLAY}" \
    && ! -e "${TARGET_DATA}" && ! -L "${TARGET_DATA}" ]] \
    || fail "Existen archivos de destino sin una integración reconocible"

rollback_needed=true
target_dir_created=false
overlay_created=false
data_created=false
overlay_temp=""
data_temp=""
rollback_dir=""

is_safe_aux_path() {
    local path="$1"
    [[ -n "${path}" && "${path}" == "${TARGET_DIR}/"* && "${path}" != "${TARGET_DIR}" ]]
}

cleanup_temp() {
    local path="$1"
    [[ -n "${path}" ]] || return 0
    if ! is_safe_aux_path "${path}"; then
        printf 'ERROR: se rechazó una ruta temporal insegura: %s\n' "${path}" >&2
        return 1
    fi
    if [[ -e "${path}" || -L "${path}" ]]; then
        rm -- "${path}" || {
            printf 'ERROR: no se pudo limpiar el temporal %s.\n' "${path}" >&2
            return 1
        }
    fi
}

ensure_rollback_dir() {
    local created=""
    [[ -z "${rollback_dir}" ]] || return 0
    if ! created="$(mktemp -d -- "${TARGET_DIR}/.ambxst-shortcuts-install-rollback.XXXXXX")"; then
        printf 'ERROR: no se pudo crear una cuarentena de rollback dentro de %s.\n' "${TARGET_DIR}" >&2
        return 1
    fi
    if [[ -z "${created}" || "${created}" != /* || ! -d "${created}" ]] \
            || ! is_safe_aux_path "${created}"; then
        printf 'ERROR: mktemp devolvió una cuarentena insegura: %s\n' "${created:-<vacía>}" >&2
        if [[ -n "${created}" ]] && is_safe_aux_path "${created}" && [[ -d "${created}" ]]; then
            rmdir -- "${created}" || printf 'ERROR: tampoco se pudo limpiar %s.\n' "${created}" >&2
        fi
        return 1
    fi
    rollback_dir="${created}"
}

restore_without_overwrite() {
    local quarantine="$1"
    local target="$2"
    if [[ -e "${target}" || -L "${target}" ]]; then
        printf 'ERROR: reapareció %s; se conservó también %s para recuperación manual.\n' \
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
}

quarantine_created_file() {
    local source="$1"
    local target="$2"
    local created_name="$3"
    local -n created_ref="${created_name}"
    local quarantine=""

    [[ "${created_ref}" == true ]] || return 0
    if [[ ! -e "${target}" && ! -L "${target}" ]]; then
        created_ref=false
        return 0
    fi
    ensure_rollback_dir || return 1
    quarantine="${rollback_dir}/$(basename -- "${target}")"
    if ! mv -- "${target}" "${quarantine}"; then
        if [[ ! -e "${target}" && ! -L "${target}" ]]; then
            created_ref=false
            return 0
        fi
        printf 'ERROR: no se pudo mover %s a la cuarentena %s.\n' "${target}" "${quarantine}" >&2
        return 1
    fi

    if cmp -s "${source}" "${quarantine}"; then
        if rm -- "${quarantine}"; then
            created_ref=false
            return 0
        fi
        printf 'ERROR: no se pudo eliminar la copia canónica en cuarentena %s.\n' "${quarantine}" >&2
        return 1
    fi

    printf 'ERROR: %s fue modificado durante la transacción; no se eliminó.\n' "${target}" >&2
    if restore_without_overwrite "${quarantine}" "${target}"; then
        created_ref=false
    fi
    return 1
}

rollback() {
    local status=$?
    local rollback_failed=false
    local patch_safe=false

    trap - EXIT
    [[ "${rollback_needed}" == true ]] || exit "${status}"
    printf 'ERROR: la instalación falló; intentando restaurar el estado previo.\n' >&2

    cleanup_temp "${overlay_temp}" || rollback_failed=true
    cleanup_temp "${data_temp}" || rollback_failed=true

    if git -C "${TARGET_ROOT}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
        if git -C "${TARGET_ROOT}" apply --reverse "${PATCH_FILE}" >/dev/null; then
            patch_safe=true
        else
            printf 'ERROR: falló la reversión del parche; recuperación manual requerida para %s, %s y %s.\n' \
                "${TARGET_ROOT}/modules/services/GlobalShortcuts.qml" \
                "${TARGET_ROOT}/modules/services/Visibilities.qml" \
                "${TARGET_ROOT}/shell.qml" >&2
            rollback_failed=true
        fi
    elif git -C "${TARGET_ROOT}" apply --check "${PATCH_FILE}" >/dev/null 2>&1; then
        patch_safe=true
    else
        printf 'ERROR: el parche cambió durante la transacción; no se retiraron archivos propios. Revisa manualmente %s, %s y %s.\n' \
            "${TARGET_ROOT}/modules/services/GlobalShortcuts.qml" \
            "${TARGET_ROOT}/modules/services/Visibilities.qml" \
            "${TARGET_ROOT}/shell.qml" >&2
        rollback_failed=true
    fi

    if [[ "${patch_safe}" == true ]]; then
        quarantine_created_file "${SOURCE_OVERLAY}" "${TARGET_OVERLAY}" overlay_created || rollback_failed=true
        quarantine_created_file "${SOURCE_DATA}" "${TARGET_DATA}" data_created || rollback_failed=true
    fi

    if [[ -n "${rollback_dir}" && -d "${rollback_dir}" ]]; then
        if ! rmdir -- "${rollback_dir}" >/dev/null 2>&1; then
            printf 'ERROR: se conservó la cuarentena no vacía %s para recuperación manual.\n' "${rollback_dir}" >&2
            rollback_failed=true
        fi
    fi
    if [[ "${target_dir_created}" == true ]]; then
        # Un directorio no vacío puede contener material concurrente y debe conservarse.
        rmdir -- "${TARGET_DIR}" >/dev/null 2>&1 || :
    fi

    if [[ "${rollback_failed}" == true ]]; then
        printf 'ERROR: rollback incompleto; revisa los archivos indicados antes de volver a ejecutar el instalador.\n' >&2
    fi
    (( status != 0 )) || status=1
    exit "${status}"
}
trap rollback EXIT

if [[ -e "${TARGET_DIR}" || -L "${TARGET_DIR}" ]]; then
    [[ -d "${TARGET_DIR}" && ! -L "${TARGET_DIR}" ]] \
        || fail "El destino del overlay existe pero no es un directorio regular: ${TARGET_DIR}"
else
    mkdir -- "${TARGET_DIR}"
    target_dir_created=true
fi

publish_file() {
    local source="$1"
    local target="$2"
    local temp_name="$3"
    local created_name="$4"
    local -n temp_ref="${temp_name}"
    local -n created_ref="${created_name}"
    local candidate=""

    if ! candidate="$(mktemp -- "${TARGET_DIR}/.$(basename -- "${target}").install.XXXXXX")"; then
        printf 'ERROR: no se pudo crear un temporal para %s.\n' "${target}" >&2
        return 1
    fi
    temp_ref="${candidate}"
    if [[ -z "${candidate}" || "${candidate}" != /* || ! -f "${candidate}" || -L "${candidate}" ]] \
            || ! is_safe_aux_path "${candidate}"; then
        printf 'ERROR: mktemp devolvió una ruta temporal insegura: %s\n' "${candidate:-<vacía>}" >&2
        return 1
    fi

    install -m 0644 -- "${source}" "${temp_ref}" || {
        printf 'ERROR: no se pudo preparar el temporal %s.\n' "${temp_ref}" >&2
        return 1
    }
    if ! ln -P -- "${temp_ref}" "${target}"; then
        printf 'ERROR: no se publicó %s porque el destino apareció o no admite creación atómica.\n' "${target}" >&2
        return 1
    fi
    created_ref=true
    if ! rm -- "${temp_ref}"; then
        printf 'ERROR: %s fue publicado, pero no se pudo limpiar el temporal %s.\n' \
            "${target}" "${temp_ref}" >&2
        return 1
    fi
    temp_ref=""
}

publish_file "${SOURCE_OVERLAY}" "${TARGET_OVERLAY}" overlay_temp overlay_created
publish_file "${SOURCE_DATA}" "${TARGET_DATA}" data_temp data_created
git -C "${TARGET_ROOT}" apply "${PATCH_FILE}"

"${PROJECT_ROOT}/scripts/verify.sh" "${TARGET_ROOT}"
rollback_needed=false
trap - EXIT
printf 'OK: overlay instalado. No se modificó binds.json y no se recargó Ambxst.\n'
