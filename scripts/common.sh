#!/usr/bin/env bash

ambxst_target_error() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

resolve_ambxst_target() {
    local candidate=""
    local data_home=""
    local registry_file=""
    local resolved=""
    local resolved_home=""
    local git_root=""
    local -a registry_lines=()

    if (( $# > 1 )); then
        ambxst_target_error "Uso: $0 [ambxst-target]"
        return 1
    fi

    if (( $# == 1 )); then
        candidate="$1"
        [[ -n "${candidate}" ]] || {
            ambxst_target_error "El destino explícito no puede estar vacío"
            return 1
        }
    elif [[ ${AMBXST_SOURCE_DIR+x} == x ]]; then
        candidate="${AMBXST_SOURCE_DIR}"
        [[ -n "${candidate}" ]] || {
            ambxst_target_error "AMBXST_SOURCE_DIR no puede estar vacío"
            return 1
        }
    else
        [[ -n "${HOME:-}" ]] || {
            ambxst_target_error "HOME no está definido; indica el destino explícitamente"
            return 1
        }
        data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
        registry_file="${data_home}/ambxst/shell_repo"
        if [[ -e "${registry_file}" ]]; then
            [[ -f "${registry_file}" && -r "${registry_file}" ]] || {
                ambxst_target_error "El registro de Ambxst no es un archivo legible: ${registry_file}"
                return 1
            }
            mapfile -t registry_lines < "${registry_file}"
            if (( ${#registry_lines[@]} != 1 )) || [[ -z "${registry_lines[0]}" ]]; then
                ambxst_target_error "El registro de Ambxst debe contener una única ruta no vacía: ${registry_file}"
                return 1
            fi
            candidate="${registry_lines[0]}"
        else
            candidate="${HOME}/.local/src/ambxst"
        fi
    fi

    [[ "${candidate}" == /* ]] || {
        ambxst_target_error "El destino debe ser una ruta absoluta: ${candidate}"
        return 1
    }
    [[ -d "${candidate}" ]] || {
        ambxst_target_error "El destino no existe o no es un directorio: ${candidate}"
        return 1
    }

    resolved="$(cd -- "${candidate}" && pwd -P)" || {
        ambxst_target_error "No se pudo resolver el destino: ${candidate}"
        return 1
    }
    [[ "${resolved}" != / ]] || {
        ambxst_target_error "La raíz del sistema no puede ser un destino Ambxst"
        return 1
    }

    if [[ -n "${HOME:-}" && -d "${HOME}" ]]; then
        resolved_home="$(cd -- "${HOME}" && pwd -P)" || resolved_home=""
        [[ -z "${resolved_home}" || "${resolved}" != "${resolved_home}" ]] || {
            ambxst_target_error "El directorio HOME completo no puede ser un destino Ambxst"
            return 1
        }
    fi

    [[ -f "${resolved}/shell.qml" \
        && -f "${resolved}/modules/services/Visibilities.qml" \
        && -f "${resolved}/modules/services/GlobalShortcuts.qml" \
        && -d "${resolved}/modules/widgets" ]] || {
        ambxst_target_error "El destino no tiene la estructura esperada de Ambxst: ${resolved}"
        return 1
    }

    git -C "${resolved}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        ambxst_target_error "El destino debe ser un árbol de trabajo Git de Ambxst: ${resolved}"
        return 1
    }
    git_root="$(git -C "${resolved}" rev-parse --show-toplevel)" || return 1
    [[ "${git_root}" == "${resolved}" ]] || {
        ambxst_target_error "El destino debe ser la raíz del árbol de trabajo de Ambxst: ${resolved}"
        return 1
    }

    printf '%s\n' "${resolved}"
}
