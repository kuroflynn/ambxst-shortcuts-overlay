#!/usr/bin/env bash

set -euo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -- "${TEST_DIR}/.." && pwd -P)"
readonly REAL_GIT="$(command -v git)"
readonly REAL_LN="$(command -v ln)"
readonly REAL_MV="$(command -v mv)"
readonly REAL_RM="$(command -v rm)"
TEMP_ROOT=""
if ! TEMP_ROOT="$(mktemp -d)"; then
    printf 'FALLO: mktemp no pudo crear el directorio temporal de pruebas.\n' >&2
    exit 1
fi
if [[ -z "${TEMP_ROOT}" || "${TEMP_ROOT}" != /* || "${TEMP_ROOT}" == / || ! -d "${TEMP_ROOT}" ]]; then
    printf 'FALLO: directorio temporal inseguro: %s\n' "${TEMP_ROOT:-<vacío>}" >&2
    exit 1
fi
readonly TEMP_ROOT
test_count=0

# shellcheck source=scripts/common.sh
source "${PROJECT_ROOT}/scripts/common.sh"

cleanup() {
    if [[ -z "${TEMP_ROOT}" || "${TEMP_ROOT}" != /* || "${TEMP_ROOT}" == / ]]; then
        printf 'FALLO: se rechazó una ruta de limpieza insegura: %s\n' "${TEMP_ROOT:-<vacía>}" >&2
        return 1
    fi
    [[ ! -e "${TEMP_ROOT}" ]] || "${REAL_RM}" -rf -- "${TEMP_ROOT}"
}
trap cleanup EXIT

fail() {
    printf 'FALLO: %s\n' "$*" >&2
    exit 1
}

pass() {
    test_count=$((test_count + 1))
    printf 'ok %d - %s\n' "${test_count}" "$1"
}

materialize_patch_preimage() {
    local target_root="$1"
    local patch_file="$2"

    mkdir -p -- "${target_root}/modules/services" "${target_root}/modules/widgets"
    awk -v root="${target_root}" '
        /^diff --git / {
            active = 0
            path = substr($3, 3)
            next
        }
        /^@@ / {
            split($2, range, ",")
            old_start = substr(range[1], 2) + 0
            output = root "/" path
            while (written[path] < old_start - 1) {
                print "// fixture padding" >> output
                written[path]++
            }
            active = 1
            next
        }
        active && /^ / {
            print substr($0, 2) >> output
            written[path]++
            next
        }
        active && /^-/ {
            print substr($0, 2) >> output
            written[path]++
            next
        }
        active && /^\+/ { next }
    ' "${patch_file}"
}

new_case() {
    local name="$1"
    CASE_ROOT="${TEMP_ROOT}/${name}"
    CASE_PROJECT="${CASE_ROOT}/project"
    CASE_TARGET="${CASE_ROOT}/ambxst"
    CASE_STATE="${CASE_ROOT}/verify-count"
    CASE_LOG="${CASE_ROOT}/command.log"
    CASE_BIN="${CASE_ROOT}/bin"
    CASE_EXPECTED_BASE="${CASE_ROOT}/expected-base"
    CASE_EXPECTED_INSTALLED="${CASE_ROOT}/expected-installed"

    [[ "${CASE_ROOT}" == "${TEMP_ROOT}/"* ]] || fail "caso fuera del temporal: ${CASE_ROOT}"

    mkdir -p -- \
        "${CASE_PROJECT}/scripts" \
        "${CASE_PROJECT}/patches" \
        "${CASE_PROJECT}/src/modules/widgets/shortcuts" \
        "${CASE_BIN}"
    cp -- "${PROJECT_ROOT}/scripts/install.sh" "${CASE_PROJECT}/scripts/install.sh"
    cp -- "${PROJECT_ROOT}/scripts/uninstall.sh" "${CASE_PROJECT}/scripts/uninstall.sh"
    cp -- "${PROJECT_ROOT}/scripts/common.sh" "${CASE_PROJECT}/scripts/common.sh"
    cp -- "${PROJECT_ROOT}/tests/fixtures/verify-stub.sh" "${CASE_PROJECT}/scripts/verify.sh"
    cp -- "${PROJECT_ROOT}/tests/fixtures/git-wrapper.sh" "${CASE_BIN}/git"
    cp -- "${PROJECT_ROOT}/tests/fixtures/fs-wrapper.sh" "${CASE_BIN}/ln"
    cp -- "${PROJECT_ROOT}/tests/fixtures/fs-wrapper.sh" "${CASE_BIN}/mv"
    cp -- "${PROJECT_ROOT}/patches/ambxst-integration.patch" "${CASE_PROJECT}/patches/ambxst-integration.patch"
    cp -- "${PROJECT_ROOT}/src/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
        "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutsOverlay.qml"
    cp -- "${PROJECT_ROOT}/src/modules/widgets/shortcuts/ShortcutData.js" \
        "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutData.js"
    chmod +x -- "${CASE_PROJECT}/scripts/"*.sh "${CASE_BIN}/git" "${CASE_BIN}/ln" "${CASE_BIN}/mv"

    materialize_patch_preimage "${CASE_TARGET}" "${CASE_PROJECT}/patches/ambxst-integration.patch"
    cp -a -- "${CASE_TARGET}/." "${CASE_EXPECTED_BASE}"
    cp -a -- "${CASE_TARGET}/." "${CASE_EXPECTED_INSTALLED}"
    "${REAL_GIT}" -C "${CASE_EXPECTED_INSTALLED}" apply "${CASE_PROJECT}/patches/ambxst-integration.patch"
    "${REAL_GIT}" -C "${CASE_TARGET}" init -q
    "${REAL_GIT}" -C "${CASE_TARGET}" apply --check "${CASE_PROJECT}/patches/ambxst-integration.patch" \
        || fail "el fixture temporal no acepta el parche canónico"
}

run_command() {
    local mode="$1"
    local git_failure="$2"
    local fs_failure="$3"
    local script="$4"
    shift 4
    printf '0\n' > "${CASE_STATE}"
    (
        cd -- "${CASE_ROOT}"
        TRANSACTION_TEST_MODE="${mode}" \
        TRANSACTION_TEST_STATE_FILE="${CASE_STATE}" \
        TRANSACTION_TEST_GIT_FAILURE="${git_failure}" \
        TRANSACTION_TEST_FS_FAILURE="${fs_failure}" \
        TRANSACTION_TEST_REAL_GIT="${REAL_GIT}" \
        TRANSACTION_TEST_REAL_LN="${REAL_LN}" \
        TRANSACTION_TEST_REAL_MV="${REAL_MV}" \
        TRANSACTION_TEST_REAL_RM="${REAL_RM}" \
        TRANSACTION_TEST_TARGET="${CASE_TARGET}" \
        PATH="${CASE_BIN}:${PATH}" \
            "${CASE_PROJECT}/scripts/${script}" "$@"
    ) > "${CASE_LOG}" 2>&1
}

expect_command_failure() {
    if run_command "$@"; then
        fail "el comando debía fallar: $*"
    else
        LAST_STATUS=$?
    fi
    (( LAST_STATUS != 0 )) || fail "el fallo devolvió código cero: $*"
}

assert_patch_state() {
    local expected_root="$1"
    local relative=""
    for relative in \
        modules/services/GlobalShortcuts.qml \
        modules/services/Visibilities.qml \
        shell.qml; do
        cmp -s "${expected_root}/${relative}" "${CASE_TARGET}/${relative}" \
            || fail "estado inesperado del parche en ${relative}"
    done
}

assert_base_state() {
    assert_patch_state "${CASE_EXPECTED_BASE}"
    "${REAL_GIT}" -C "${CASE_TARGET}" apply --check "${CASE_PROJECT}/patches/ambxst-integration.patch" >/dev/null 2>&1 \
        || fail "el parche directo dejó de aplicar en ${CASE_TARGET}"
    ! "${REAL_GIT}" -C "${CASE_TARGET}" apply --reverse --check "${CASE_PROJECT}/patches/ambxst-integration.patch" >/dev/null 2>&1 \
        || fail "el parche sigue aplicado en ${CASE_TARGET}"
    [[ ! -e "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" ]] \
        || fail "ShortcutsOverlay.qml quedó instalado"
    [[ ! -e "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" ]] \
        || fail "ShortcutData.js quedó instalado"
}

assert_installed_state() {
    assert_patch_state "${CASE_EXPECTED_INSTALLED}"
    "${REAL_GIT}" -C "${CASE_TARGET}" apply --reverse --check "${CASE_PROJECT}/patches/ambxst-integration.patch" >/dev/null 2>&1 \
        || fail "el parche no está aplicado en ${CASE_TARGET}"
    ! "${REAL_GIT}" -C "${CASE_TARGET}" apply --check "${CASE_PROJECT}/patches/ambxst-integration.patch" >/dev/null 2>&1 \
        || fail "el parche directo aún aplica en ${CASE_TARGET}"
    cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
        "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
        || fail "ShortcutsOverlay.qml no coincide con la fuente canónica"
    cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutData.js" \
        "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" \
        || fail "ShortcutData.js no coincide con la fuente canónica"
}

assert_no_auxiliary_paths() {
    local target_dir="${CASE_TARGET}/modules/widgets/shortcuts"
    local found=""
    [[ -d "${target_dir}" ]] || return 0
    found="$(find "${target_dir}" -mindepth 1 \
        \( -name '.ambxst-shortcuts-*' -o -name '.*.install.*' \) -print -quit)"
    [[ -z "${found}" ]] || fail "quedó un temporal o cuarentena inesperado: ${found}"
}

find_quarantined_file() {
    local basename="$1"
    find "${CASE_TARGET}/modules/widgets/shortcuts" -mindepth 2 -maxdepth 2 \
        -path '*/.ambxst-shortcuts-uninstall.*/*' -name "${basename}" -print -quit
}

make_valid_target() {
    local target_root="$1"
    materialize_patch_preimage "${target_root}" "${PROJECT_ROOT}/patches/ambxst-integration.patch"
    "${REAL_GIT}" -C "${target_root}" init -q
}

new_case install_verify_failure
if run_command fail-final none none install.sh "${CASE_TARGET}"; then
    fail "install.sh aceptó una verificación final fallida"
fi
assert_base_state
pass "un fallo de verificación al instalar restaura el estado previo"

new_case uninstall_verify_failure
run_command pass none none install.sh "${CASE_TARGET}" || fail "falló la preparación instalada"
assert_installed_state
if run_command fail-final none none uninstall.sh "${CASE_TARGET}"; then
    fail "uninstall.sh aceptó una verificación final fallida"
fi
assert_installed_state
pass "un fallo de verificación al desinstalar restaura la instalación"

new_case concurrent_overlay
if run_command modify-overlay none none install.sh "${CASE_TARGET}"; then
    fail "install.sh aceptó una modificación concurrente"
fi
[[ -f "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" ]] \
    || fail "el rollback borró el archivo modificado concurrentemente"
grep -Fq 'modificación concurrente' "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    || fail "el rollback sobrescribió el archivo modificado concurrentemente"
grep -Fq "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" "${CASE_LOG}" \
    || fail "el diagnóstico no identificó el archivo concurrente"
pass "el rollback conserva e identifica un archivo modificado concurrentemente"

new_case inverse_patch_failure
if run_command fail-final reverse-apply none install.sh "${CASE_TARGET}"; then
    fail "install.sh ocultó el fallo del parche inverso"
fi
grep -Fq 'falló la reversión del parche' "${CASE_LOG}" \
    || fail "el fallo del parche inverso no quedó diagnosticado"
assert_installed_state
pass "un fallo del parche inverso queda visible y conserva archivos"

new_case direct_patch_failure
run_command pass none none install.sh "${CASE_TARGET}" || fail "falló la preparación instalada"
if run_command fail-final direct-apply none uninstall.sh "${CASE_TARGET}"; then
    fail "uninstall.sh ocultó el fallo del parche directo"
fi
grep -Fq 'falló la reaplicación del parche' "${CASE_LOG}" \
    || fail "el fallo del parche directo no quedó diagnosticado"
cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    || fail "el rollback no restauró ShortcutsOverlay.qml"
cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutData.js" \
    "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" \
    || fail "el rollback no restauró ShortcutData.js"
pass "un fallo del parche directo queda visible y restaura archivos propios"

new_case publish_second_failure
expect_command_failure pass none publish-second install.sh "${CASE_TARGET}"
assert_patch_state "${CASE_EXPECTED_BASE}"
[[ ! -e "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" ]] \
    || fail "quedó publicado el primer archivo tras fallar el segundo"
grep -Fq 'contenido concurrente durante publicación' \
    "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" \
    || fail "se sobrescribió o eliminó el segundo destino concurrente"
grep -Fq 'no se publicó' "${CASE_LOG}" || fail "faltó el diagnóstico de publicación fallida"
assert_no_auxiliary_paths
pass "fallar la segunda publicación revierte solo lo propio y conserva lo concurrente"

new_case move_first_failure
run_command pass none none install.sh "${CASE_TARGET}" || fail "falló la preparación instalada"
expect_command_failure pass none move-first uninstall.sh "${CASE_TARGET}"
assert_patch_state "${CASE_EXPECTED_INSTALLED}"
[[ ! -e "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" ]] \
    || fail "se recreó el primer archivo eliminado concurrentemente"
cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutData.js" \
    "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" \
    || fail "el segundo archivo cambió tras fallar el primer movimiento"
grep -Fq 'desapareció concurrentemente' "${CASE_LOG}" || fail "faltó el diagnóstico del primer movimiento"
assert_no_auxiliary_paths
pass "fallar el primer movimiento no recrea una eliminación concurrente"

new_case move_second_failure
run_command pass none none install.sh "${CASE_TARGET}" || fail "falló la preparación instalada"
expect_command_failure pass none move-second uninstall.sh "${CASE_TARGET}"
assert_patch_state "${CASE_EXPECTED_INSTALLED}"
cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    || fail "el primer archivo movido no fue restaurado"
[[ ! -e "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" ]] \
    || fail "se recreó el segundo archivo eliminado concurrentemente"
grep -Fq 'desapareció concurrentemente' "${CASE_LOG}" || fail "faltó el diagnóstico del segundo movimiento"
assert_no_auxiliary_paths
pass "fallar el segundo movimiento restaura solo el archivo que movió el script"

new_case restore_first_failure
run_command pass none none install.sh "${CASE_TARGET}" || fail "falló la preparación instalada"
expect_command_failure fail-final none restore-first uninstall.sh "${CASE_TARGET}"
assert_patch_state "${CASE_EXPECTED_INSTALLED}"
grep -Fq 'contenido concurrente durante restauración' "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    || fail "se sobrescribió el primer destino reaparecido"
cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutData.js" \
    "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" \
    || fail "el segundo archivo no fue restaurado"
overlay_quarantine_path="$(find_quarantined_file ShortcutsOverlay.qml)"
[[ -n "${overlay_quarantine_path}" ]] || fail "no se conservó la primera cuarentena"
cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutsOverlay.qml" "${overlay_quarantine_path}" \
    || fail "la primera cuarentena no conserva el archivo canónico"
grep -Fq "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" "${CASE_LOG}" \
    || fail "el diagnóstico no identificó el primer destino"
grep -Fq "${overlay_quarantine_path}" "${CASE_LOG}" \
    || fail "el diagnóstico no identificó la primera cuarentena"
pass "fallar la primera restauración conserva destino y cuarentena sin sobrescribir"

new_case restore_second_failure
run_command pass none none install.sh "${CASE_TARGET}" || fail "falló la preparación instalada"
expect_command_failure fail-final none restore-second uninstall.sh "${CASE_TARGET}"
assert_patch_state "${CASE_EXPECTED_INSTALLED}"
cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutsOverlay.qml" \
    || fail "el primer archivo no fue restaurado"
grep -Fq 'contenido concurrente durante restauración' "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" \
    || fail "se sobrescribió el segundo destino reaparecido"
data_quarantine_path="$(find_quarantined_file ShortcutData.js)"
[[ -n "${data_quarantine_path}" ]] || fail "no se conservó la segunda cuarentena"
cmp -s "${CASE_PROJECT}/src/modules/widgets/shortcuts/ShortcutData.js" "${data_quarantine_path}" \
    || fail "la segunda cuarentena no conserva el archivo canónico"
grep -Fq "${CASE_TARGET}/modules/widgets/shortcuts/ShortcutData.js" "${CASE_LOG}" \
    || fail "el diagnóstico no identificó el segundo destino"
grep -Fq "${data_quarantine_path}" "${CASE_LOG}" \
    || fail "el diagnóstico no identificó la segunda cuarentena"
pass "fallar la segunda restauración conserva destino y cuarentena sin sobrescribir"

new_case idempotence
run_command pass none none install.sh "${CASE_TARGET}" || fail "falló la instalación normal"
run_command pass none none install.sh "${CASE_TARGET}" || fail "la reinstalación idéntica no fue idempotente"
assert_installed_state
run_command pass none none uninstall.sh "${CASE_TARGET}" || fail "falló la desinstalación normal"
run_command pass none none uninstall.sh "${CASE_TARGET}" || fail "la segunda desinstalación no fue idempotente"
assert_base_state
assert_no_auxiliary_paths
pass "instalación y desinstalación normales son idempotentes"

resolver_root="${TEMP_ROOT}/resolver"
explicit_target="${resolver_root}/explicit"
environment_target="${resolver_root}/environment"
registry_target="${resolver_root}/registry"
fallback_home="${resolver_root}/home"
fallback_target="${fallback_home}/.local/src/ambxst"
data_home="${resolver_root}/data"
mkdir -p -- "${data_home}/ambxst" "${fallback_home}"
make_valid_target "${explicit_target}"
make_valid_target "${environment_target}"
make_valid_target "${registry_target}"
make_valid_target "${fallback_target}"
printf '%s\n' "${registry_target}" > "${data_home}/ambxst/shell_repo"

resolved="$(HOME="${fallback_home}" XDG_DATA_HOME="${data_home}" \
    AMBXST_SOURCE_DIR="${environment_target}" resolve_ambxst_target "${explicit_target}")"
[[ "${resolved}" == "${explicit_target}" ]] || fail "el argumento explícito no tuvo prioridad"
resolved="$(HOME="${fallback_home}" XDG_DATA_HOME="${data_home}" \
    AMBXST_SOURCE_DIR="${environment_target}" resolve_ambxst_target)"
[[ "${resolved}" == "${environment_target}" ]] || fail "AMBXST_SOURCE_DIR no tuvo prioridad sobre el registro"
unset AMBXST_SOURCE_DIR
resolved="$(HOME="${fallback_home}" XDG_DATA_HOME="${data_home}" resolve_ambxst_target)"
[[ "${resolved}" == "${registry_target}" ]] || fail "no se usó el registro shell_repo"
resolved="$(HOME="${fallback_home}" XDG_DATA_HOME="${resolver_root}/missing-data" resolve_ambxst_target)"
[[ "${resolved}" == "${fallback_target}" ]] || fail "no se usó el fallback portable bajo HOME"
pass "la resolución portable respeta argumento, entorno, registro y fallback"

resolver_snapshot() {
    find "${resolver_root}" -type f ! -path '*/.git/*' -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum
}

run_resolver_mode() {
    local mode="$1"
    case "${mode}" in
        registry)
            (unset AMBXST_SOURCE_DIR; HOME="${fallback_home}" XDG_DATA_HOME="${data_home}" resolve_ambxst_target)
            ;;
        empty-env)
            HOME="${fallback_home}" XDG_DATA_HOME="${data_home}" AMBXST_SOURCE_DIR="" resolve_ambxst_target
            ;;
        empty-argument)
            resolve_ambxst_target ""
            ;;
        too-many)
            resolve_ambxst_target "${explicit_target}" "${environment_target}"
            ;;
        inner)
            resolve_ambxst_target "${inner_target}"
            ;;
        no-fallback)
            (unset AMBXST_SOURCE_DIR; HOME="${missing_fallback_home}" XDG_DATA_HOME="${missing_data_home}" resolve_ambxst_target)
            ;;
        root)
            resolve_ambxst_target /
            ;;
        home)
            HOME="${fallback_home}" resolve_ambxst_target "${fallback_home}"
            ;;
        relative-argument)
            resolve_ambxst_target relative/path
            ;;
        missing-argument)
            resolve_ambxst_target "${resolver_root}/missing"
            ;;
        *) fail "modo de resolver desconocido: ${mode}" ;;
    esac
}

expect_resolver_failure() {
    local label="$1"
    local expected="$2"
    local mode="$3"
    local before=""
    local after=""
    local output=""

    before="$(resolver_snapshot)"
    if output="$(run_resolver_mode "${mode}" 2>&1)"; then
        fail "el resolver aceptó ${label}"
    else
        LAST_STATUS=$?
    fi
    (( LAST_STATUS != 0 )) || fail "${label} devolvió código cero"
    [[ "${output}" == *ERROR:* && "${output}" == *"${expected}"* ]] \
        || fail "diagnóstico inesperado para ${label}: ${output}"
    after="$(resolver_snapshot)"
    [[ "${before}" == "${after}" ]] || fail "el resolver modificó archivos para ${label}"
    pass "el resolver rechaza ${label} sin modificar el árbol"
}

printf '' > "${data_home}/ambxst/shell_repo"
expect_resolver_failure "shell_repo vacío" "única ruta" registry

printf '%s\n%s\n' "${registry_target}" "${explicit_target}" > "${data_home}/ambxst/shell_repo"
expect_resolver_failure "shell_repo multilínea" "única ruta" registry

printf 'relative/path\n' > "${data_home}/ambxst/shell_repo"
expect_resolver_failure "shell_repo relativo" "ruta absoluta" registry

invalid_registry_target="${resolver_root}/invalid-registry-target"
mkdir -p -- "${invalid_registry_target}"
printf '%s\n' "${invalid_registry_target}" > "${data_home}/ambxst/shell_repo"
expect_resolver_failure "shell_repo hacia un árbol inválido" "estructura esperada" registry

printf '%s\n' "${registry_target}" > "${data_home}/ambxst/shell_repo"
expect_resolver_failure "AMBXST_SOURCE_DIR vacío" "AMBXST_SOURCE_DIR" empty-env
expect_resolver_failure "un argumento vacío" "explícito" empty-argument
expect_resolver_failure "más de un argumento" "Uso:" too-many

inner_target="${explicit_target}/nested"
materialize_patch_preimage "${inner_target}" "${PROJECT_ROOT}/patches/ambxst-integration.patch"
expect_resolver_failure "una ruta interna que no es raíz del worktree" "raíz del árbol" inner

missing_fallback_home="${resolver_root}/home-without-fallback"
missing_data_home="${resolver_root}/data-without-registry"
mkdir -p -- "${missing_fallback_home}" "${missing_data_home}"
expect_resolver_failure "la ausencia de argumento, variable, registro y fallback" "no existe" no-fallback

expect_resolver_failure "la raíz del sistema" "raíz del sistema" root
expect_resolver_failure "el HOME completo" "HOME completo" home
expect_resolver_failure "un argumento relativo" "ruta absoluta" relative-argument
expect_resolver_failure "un argumento inexistente" "no existe" missing-argument

printf 'OK: %d pruebas transaccionales superadas; todos los destinos fueron temporales.\n' "${test_count}"
