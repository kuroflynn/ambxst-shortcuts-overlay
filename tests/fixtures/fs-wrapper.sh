#!/usr/bin/env bash

set -euo pipefail

readonly command_name="$(basename -- "$0")"
readonly failure="${TRANSACTION_TEST_FS_FAILURE:-none}"
readonly overlay_target="${TRANSACTION_TEST_TARGET:?}/modules/widgets/shortcuts/ShortcutsOverlay.qml"
readonly data_target="${TRANSACTION_TEST_TARGET:?}/modules/widgets/shortcuts/ShortcutData.js"
readonly source_argument="${@: -2:1}"
readonly last_argument="${!#}"

case "${command_name}:${failure}" in
    ln:publish-second)
        if [[ "${last_argument}" == "${data_target}" ]]; then
            printf 'contenido concurrente durante publicación\n' > "${data_target}"
            printf 'Fallo simulado al publicar el segundo archivo.\n' >&2
            exit 81
        fi
        ;;
    mv:move-first)
        if [[ "${source_argument}" == "${overlay_target}" ]]; then
            "${TRANSACTION_TEST_REAL_RM:?}" -- "${overlay_target}"
            printf 'Fallo simulado al mover el primer archivo.\n' >&2
            exit 82
        fi
        ;;
    mv:move-second)
        if [[ "${source_argument}" == "${data_target}" ]]; then
            "${TRANSACTION_TEST_REAL_RM:?}" -- "${data_target}"
            printf 'Fallo simulado al mover el segundo archivo.\n' >&2
            exit 83
        fi
        ;;
    ln:restore-first)
        if [[ "${last_argument}" == "${overlay_target}" ]]; then
            printf 'contenido concurrente durante restauración\n' > "${overlay_target}"
            printf 'Fallo simulado al restaurar el primer archivo.\n' >&2
            exit 84
        fi
        ;;
    ln:restore-second)
        if [[ "${last_argument}" == "${data_target}" ]]; then
            printf 'contenido concurrente durante restauración\n' > "${data_target}"
            printf 'Fallo simulado al restaurar el segundo archivo.\n' >&2
            exit 85
        fi
        ;;
esac

case "${command_name}" in
    ln) exec "${TRANSACTION_TEST_REAL_LN:?}" "$@" ;;
    mv) exec "${TRANSACTION_TEST_REAL_MV:?}" "$@" ;;
    *)
        printf 'Wrapper invocado con nombre inesperado: %s\n' "${command_name}" >&2
        exit 86
        ;;
esac
