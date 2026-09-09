#!/usr/bin/env bash

ambxst_target_error() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

# Fail-closed pre-resolution guard: LF and CR are illegal in a deployment
# target. Tabs, spaces and UTF-8 remain valid. Message uses %q so the value
# itself cannot re-inject a control byte into the diagnostic.
reject_control_target() {
    local value="$1"
    if [[ "${value}" == *$'\n'* ]]; then
        ambxst_target_error "El destino contiene un salto de línea, no válido: $(printf '%q' "${value}")"
        return 1
    fi
    if [[ "${value}" == *$'\r'* ]]; then
        ambxst_target_error "El destino contiene un retorno de carro, no válido: $(printf '%q' "${value}")"
        return 1
    fi
    return 0
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
        if [[ -e "${registry_file}" || -L "${registry_file}" ]]; then
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

    reject_control_target "${candidate}" || return 1

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

# One classification for all three entrypoints. In particular, -e alone does
# not distinguish an absent path from a dangling symlink.
ambxst_path_kind() {
    if [[ -L "$1" ]]; then
        if [[ -e "$1" ]]; then printf 'symlink\n'; else printf 'dangling-symlink\n'; fi
    elif [[ -f "$1" ]]; then printf 'file\n'
    elif [[ -d "$1" ]]; then printf 'directory\n'
    elif [[ -e "$1" ]]; then printf 'other\n'
    else printf 'absent\n'; fi
}

validate_ambxst_paths() {
    local root="$1" relative kind
    for relative in modules modules/services modules/widgets; do
        kind="$(ambxst_path_kind "${root}/${relative}")"
        [[ "${kind}" == directory ]] || {
            ambxst_target_error "Ruta de despliegue no regular (${kind}): ${root}/${relative}"; return 1;
        }
    done
    for relative in shell.qml modules/services/Visibilities.qml modules/services/GlobalShortcuts.qml; do
        kind="$(ambxst_path_kind "${root}/${relative}")"
        [[ "${kind}" == file ]] || {
            ambxst_target_error "Archivo compartido no regular (${kind}): ${root}/${relative}"; return 1;
        }
    done
    for relative in modules/widgets/shortcuts .ambxst-shortcuts-recovery; do
        kind="$(ambxst_path_kind "${root}/${relative}")"
        [[ "${kind}" == absent || "${kind}" == directory ]] || {
            ambxst_target_error "Directorio de despliegue no regular (${kind}): ${root}/${relative}"; return 1;
        }
    done
}

classify_overlay_files() {
    local root="$1" source="$2" name kind count=0
    validate_ambxst_paths "${root}" || return 1
    for name in ShortcutsOverlay.qml ShortcutData.js; do
        kind="$(ambxst_path_kind "${root}/modules/widgets/shortcuts/${name}")"
        case "${kind}" in
            absent) ;;
            file)
                cmp -s "${source}/${name}" "${root}/modules/widgets/shortcuts/${name}" || {
                    ambxst_target_error "${name} instalado difiere de la fuente canónica"; return 1;
                }
                count=$((count + 1)) ;;
            *) ambxst_target_error "Archivo del overlay no regular (${kind}): ${root}/modules/widgets/shortcuts/${name}"; return 1 ;;
        esac
    done
    case "${count}" in
        0) printf 'absent\n' ;;
        2) printf 'matching\n' ;;
        *) ambxst_target_error "Instalación parcial: falta uno de los archivos del overlay"; return 1 ;;
    esac
}

# Linux directory descriptors pin the directory actually validated. All leaf
# mutations use these paths, not a fresh traversal of mutable ancestor names.
# See docs/qa/v0.1.1/DESIGN.md for the same-user directory-relocation limit.
pin_directory() {
    local path="$1" expected="$2" result_name="$3" descriptor access
    [[ "$(ambxst_path_kind "${path}")" == directory ]] || {
        ambxst_target_error "No se puede anclar el directorio: ${expected}"; return 1;
    }
    exec {descriptor}< "${path}" || return 1
    access="/proc/${BASHPID}/fd/${descriptor}"
    [[ "$(readlink -e -- "${access}")" == "${expected}" && ! -L "${expected}" && "${expected}" -ef "${access}" ]] || {
        ambxst_target_error "El directorio cambió al abrirlo: ${expected}"; return 1;
    }
    PIN_PATHS+=("${access}")
    PIN_EXPECTED+=("${expected}")
    printf -v "${result_name}" '%s' "${access}"
}

check_pinned_paths() {
    local i actual
    for i in "${!PIN_PATHS[@]}"; do
        actual="$(readlink -e -- "${PIN_PATHS[i]}")" || actual="<desaparecido>"
        if [[ "${actual}" != "${PIN_EXPECTED[i]}" || -L "${PIN_EXPECTED[i]}" \
                || ! "${PIN_EXPECTED[i]}" -ef "${PIN_PATHS[i]}" ]]; then
            ambxst_target_error "Cambió el directorio ${PIN_EXPECTED[i]}; ubicación anclada: ${actual}. Recuperación manual requerida."
            return 1
        fi
    done
}

begin_deployment() {
    PIN_PATHS=(); PIN_EXPECTED=()
    validate_ambxst_paths "${TARGET_ROOT}" || return 1
    pin_directory "${TARGET_ROOT}" "${TARGET_ROOT}" ROOT_ACCESS || return 1
    # Locks only cooperating deployments, not editors. No persistent lock file.
    command -v flock >/dev/null || { ambxst_target_error "Falta flock (util-linux) para serializar el despliegue"; return 1; }
    flock -n "${ROOT_ACCESS##*/}" || { ambxst_target_error "Hay otro despliegue en ${TARGET_ROOT}"; return 1; }
    pin_directory "${ROOT_ACCESS}/modules" "${TARGET_ROOT}/modules" MODULES_ACCESS || return 1
    pin_directory "${MODULES_ACCESS}/services" "${TARGET_ROOT}/modules/services" SERVICES_ACCESS || return 1
    pin_directory "${MODULES_ACCESS}/widgets" "${TARGET_ROOT}/modules/widgets" WIDGETS_ACCESS || return 1
    check_pinned_paths
}

open_overlay_directory() {
    check_pinned_paths || return 1
    if [[ "$(ambxst_path_kind "${WIDGETS_ACCESS}/shortcuts")" == absent ]]; then
        mkdir -- "${WIDGETS_ACCESS}/shortcuts" || return 1
    fi
    pin_directory "${WIDGETS_ACCESS}/shortcuts" "${TARGET_ROOT}/modules/widgets/shortcuts" OVERLAY_ACCESS
}

create_recovery() {
    local operation="$1" candidate base="${TARGET_ROOT}/.ambxst-shortcuts-recovery"
    check_pinned_paths || return 1
    if [[ "$(ambxst_path_kind "${ROOT_ACCESS}/.ambxst-shortcuts-recovery")" == absent ]]; then
        mkdir -m 0700 -- "${ROOT_ACCESS}/.ambxst-shortcuts-recovery" || return 1
    fi
    pin_directory "${ROOT_ACCESS}/.ambxst-shortcuts-recovery" "${base}" RECOVERY_ACCESS || return 1
    candidate="$(mktemp -d -- "${RECOVERY_ACCESS}/${operation}.XXXXXX")" || return 1
    [[ "${candidate}" == "${RECOVERY_ACCESS}/${operation}."* \
        && "${candidate#"${RECOVERY_ACCESS}/"}" != */* ]] || {
        ambxst_target_error "mktemp devolvió una recuperación insegura: ${candidate}"; return 1;
    }
    RECOVERY_PATH="${base}/${candidate##*/}"
    pin_directory "${candidate}" "${RECOVERY_PATH}" RECOVERY_TX_ACCESS || return 1
    printf 'RECUPERACIÓN: %s (se conserva; limpieza manual tras detener escritores).\n' "${RECOVERY_PATH}"
}

report_recovery() {
    [[ -n "${RECOVERY_PATH:-}" ]] || return 0
    printf 'RECUPERACIÓN conservada: %s\n' "${RECOVERY_PATH}" >&2
    if [[ -n "${RECOVERY_TX_ACCESS:-}" ]]; then
        printf 'Ubicación actual de recuperación: %s\n' "$(readlink -e -- "${RECOVERY_TX_ACCESS}" || printf '<no accesible>')" >&2
    fi
}

link_exact() {
    local source="$1" target="$2"
    check_pinned_paths || return 1
    [[ "$(ambxst_path_kind "${source}")" == file && "$(ambxst_path_kind "${target}")" == absent ]] || return 1
    ln -PT -- "${source}" "${target}" || return 1
    check_pinned_paths || return 1
    [[ "$(ambxst_path_kind "${target}")" == file && "${source}" -ef "${target}" ]] \
        && cmp -s "${source}" "${target}"
}

restore_exact() {
    local quarantine="$1" target="$2" display="$3"
    if ! link_exact "${quarantine}" "${target}"; then
        ambxst_target_error "No se pudo restaurar ${display} sin sobrescribir; se conservó ${RECOVERY_PATH}/${quarantine##*/}. Recuperación manual requerida."
        return 1
    fi
    # Deliberately retain the link even after restoring: an open writer can
    # still change the inode after the final cmp or remove the restored name.
}

move_exact() {
    check_pinned_paths || return 1
    mv --no-copy -T --update=none-fail -- "$1" "$2"
}

# Exact-destination staging with an exclusively-created, already-open descriptor.
# The candidate name is generated WITHOUT creating (gen_candidate); `set -o
# noclobber` makes the following `exec {fd}> "$candidate"` a single atomic
# O_CREAT|O_EXCL|O_WRONLY open that never follows a symlink, never blocks on a
# FIFO and never clobbers whatever already owns the name (EEXIST -> abandon the
# name and retry, up to STAGE_RETRIES). Content and mode form one verified
# preparation performed only through the descriptor; any failure closes it and
# aborts before any partial staging can be published. device+inode is verified
# after the create as an extra identity check, not as the identity mechanism.
stage_file() {
    local name="$1" source_dir="$2" gen_candidate_path="" candidate=""
    local -r retries=8
    [[ -n "${RECOVERY_TX_ACCESS:-}" && -n "${RECOVERY_PATH:-}" ]] || {
        ambxst_target_error "No hay recuperación preparada para etapificar ${name}"; return 1; }
    check_pinned_paths || return 1
    gen_candidate_path="$(command -v gen_candidate 2>/dev/null || true)"
    [[ -n "${gen_candidate_path}" ]] || gen_candidate_path="${SCRIPT_DIR}/gen_candidate"
    [[ -r "${gen_candidate_path}" && -x "${gen_candidate_path}" ]] || {
        ambxst_target_error "Falta el generador del nombre de staging: ${gen_candidate_path}"; return 1; }
    # Run the create and verified preparation in a scoped subshell so `set -C`
    # cannot leak noclobber past this stage. On success it prints the candidate.
    candidate="$(
        set -C
        umask 077 # exclusive create lands 0600; chmod sets 0644 after the check
        attempt="" leaf="" fd="" fd_path="" a_dev="" a_ino="" s_dev="" s_ino="" stats=""
        for ((attempt = 0; attempt < retries; attempt++)); do
            leaf="$("${gen_candidate_path}" "${RECOVERY_TX_ACCESS}" "${name}")" || { printf 'E:generador\n'; exit 0; }
            [[ -n "${leaf}" \
                && "${leaf}" == "${RECOVERY_TX_ACCESS}/.${name}.install."* \
                && "${leaf#"${RECOVERY_TX_ACCESS}/"}" != */* ]] || { printf 'E:forma del temporal\n'; exit 0; }
            # If something already owns the name, abandon it without opening:
            # noclobber's guarded open never clobbers a regular file or follows a
            # symlink here (both fail outright), but opening a pre-existing FIFO
            # or device node would block. Existence pre-check (lstat) avoids that;
            # the atomic O_EXCL open still guards the create->open window.
            if [[ -e "${leaf}" || -L "${leaf}" ]]; then
                fd=""
                continue
            fi
            # A group-scoped silencing: `exec REDIR` installs redirections into
            # the shell permanently, so 2>/dev/null on exec would silence every
            # later diagnostic in this subshell. Scoping it to the compound keeps
            # the noclobber refusal quiet without leaking fd 2 to /dev/null.
            if { exec {fd}>"${leaf}"; } 2>/dev/null; then
                # Exclusive open succeeded: fd now names our brand-new inode.
                fd_path="/proc/${BASHPID}/fd/${fd}"
                if ! cat -- "${source_dir}/${name}" >&"${fd}"; then
                    exec {fd}>&-; printf 'E:escritura\n'; exit 0; fi
                if ! cmp -s -- "${source_dir}/${name}" "${fd_path}"; then
                    exec {fd}>&-; printf 'E:integridad de la preparación\n'; exit 0; fi
                if ! chmod 0644 -- "${fd_path}"; then
                    exec {fd}>&-; printf 'E:modo\n'; exit 0; fi
                # Extra post-create identity check: the name must still resolve
                # to the object we opened. This guards an accidental late swap.
                stats="$(LC_ALL=C stat -Lc '%d %i' -- "${fd_path}")" || { exec {fd}>&-; printf 'E:identidad\n'; exit 0; }
                s_dev="${stats%% *}"; s_ino="${stats##* }"
                stats="$(LC_ALL=C stat -Lc '%d %i' -- "${leaf}")" || { exec {fd}>&-; printf 'E:identidad\n'; exit 0; }
                a_dev="${stats%% *}"; a_ino="${stats##* }"
                if [[ "${s_dev}" != "${a_dev}" || "${s_ino}" != "${a_ino}" ]]; then
                    exec {fd}>&-; printf 'E:el temporal cambió tras crearlo\n'; exit 0; fi
                exec {fd}>&-
                printf '%s\n' "${leaf}"
                exit 0
            fi
            fd="" # a name collision (or an occupied node): abandon and retry
        done
        printf 'E:colisiones agotadas\n'
        exit 0
    )" || return 1
    case "${candidate}" in
        E:*) ambxst_target_error "No se pudo preparar el staging de ${name}: ${candidate#E:}"; return 1 ;;
    esac
    printf '%s\n' "${candidate}"
}
