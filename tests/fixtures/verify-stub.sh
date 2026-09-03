#!/usr/bin/env bash

set -euo pipefail

readonly target_root="$1"
readonly state_file="${TRANSACTION_TEST_STATE_FILE:?}"
readonly mode="${TRANSACTION_TEST_MODE:-pass}"
count=0
if [[ -f "${state_file}" ]]; then
    read -r count < "${state_file}"
fi
count=$((count + 1))
printf '%s\n' "${count}" > "${state_file}"

if (( count == 2 )); then
    case "${mode}" in
        fail-final)
            printf 'Fallo final simulado.\n' >&2
            exit 97
            ;;
        modify-overlay)
            printf 'modificación concurrente\n' > "${target_root}/modules/widgets/shortcuts/ShortcutsOverlay.qml"
            printf 'Fallo final tras modificación concurrente.\n' >&2
            exit 97
            ;;
    esac
fi
