#!/usr/bin/env bash
set -euo pipefail
readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly TEST_ROOT="$(mktemp -d /tmp/ambxst-verify-test.XXXXXX)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
mkdir -- "${TEST_ROOT}/project" "${TEST_ROOT}/target"
cp -a -- "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/tests" "${PROJECT_ROOT}/src" \
    "${PROJECT_ROOT}/patches" "${TEST_ROOT}/project/"
cp -- "${PROJECT_ROOT}/AGENTS.md" "${PROJECT_ROOT}/REQUIREMENTS.md" \
    "${PROJECT_ROOT}/README.md" "${PROJECT_ROOT}/CHANGELOG.md" \
    "${PROJECT_ROOT}/ambxst-shortcuts-overlay.code-workspace" "${TEST_ROOT}/project/"
# Materialize only patch preimages, as in the transactional fixtures.
node - "${PROJECT_ROOT}/patches/ambxst-integration.patch" "${TEST_ROOT}/target" <<'JS'
const fs = require('fs'), path = require('path');
const target = process.argv[3], files = {}; let current, active = false;
for (const line of fs.readFileSync(process.argv[2], 'utf8').split('\n')) {
    if (line.startsWith('diff --git ')) { current = line.split(' ')[2].slice(2); files[current] = []; active = false; }
    else if (line.startsWith('@@ ')) {
        const start = Number(line.split(' ')[1].slice(1).split(',')[0]);
        while (files[current].length < start - 1) files[current].push('// fixture padding');
        active = true;
    } else if (active && [' ', '-'].includes(line[0])) files[current].push(line.slice(1));
}
for (const [name, lines] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(target, name)), {recursive:true});
    fs.writeFileSync(path.join(target, name), lines.join('\n')+'\n');
}
fs.mkdirSync(path.join(target, 'modules/widgets'), {recursive:true});
JS
git -C "${TEST_ROOT}/target" init -q
"${TEST_ROOT}/project/scripts/verify.sh" "${TEST_ROOT}/target" > "${TEST_ROOT}/verify.log" 2>&1
count=1
for relative in scripts/uninstall.sh tests/fixtures/fs-wrapper.sh; do
    printf '\nif then\n' >> "${TEST_ROOT}/project/${relative}"
    if "${TEST_ROOT}/project/scripts/verify.sh" "${TEST_ROOT}/target" > "${TEST_ROOT}/verify.log" 2>&1; then
        printf 'FALLO: verify aceptó sintaxis inválida en %s\n' "${relative}" >&2
        exit 1
    fi
    grep -Fq "${relative}" "${TEST_ROOT}/verify.log"
    cp -- "${PROJECT_ROOT}/${relative}" "${TEST_ROOT}/project/${relative}"
    count=$((count + 1))
done
printf 'OK: %d regresiones de verify (baseline y mutaciones aisladas).\n' "${count}"
