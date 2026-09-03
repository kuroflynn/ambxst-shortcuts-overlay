#!/usr/bin/env bash

set -euo pipefail

apply=false
reverse=false
check=false
for argument in "$@"; do
    case "${argument}" in
        apply) apply=true ;;
        --reverse) reverse=true ;;
        --check) check=true ;;
    esac
done

if [[ "${apply}" == true && "${check}" == false ]]; then
    if [[ "${TRANSACTION_TEST_GIT_FAILURE:-}" == reverse-apply && "${reverse}" == true ]]; then
        printf 'Fallo simulado al ejecutar el parche inverso.\n' >&2
        exit 98
    fi
    if [[ "${TRANSACTION_TEST_GIT_FAILURE:-}" == direct-apply && "${reverse}" == false ]]; then
        printf 'Fallo simulado al ejecutar el parche directo.\n' >&2
        exit 99
    fi
fi

exec "${TRANSACTION_TEST_REAL_GIT:?}" "$@"
