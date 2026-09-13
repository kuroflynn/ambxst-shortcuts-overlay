#!/usr/bin/env bash

set -euo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly TEST_ROOT="$(mktemp -d /tmp/ambxst-verify-test.XXXXXX)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
readonly PROJECT_COPY="${TEST_ROOT}/project"

materialize_target() {
    local target_root="$1"
    python3 - "${PROJECT_ROOT}/patches/ambxst-integration.patch" "${PROJECT_ROOT}/docs/mods/manifest.schema.json" "${target_root}" <<'PY'
import pathlib
import sys

patch, schema, target = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
target.mkdir(parents=True)
(target / "modules/services").mkdir(parents=True)
(target / "modules/widgets").mkdir()
(target / "docs/mods").mkdir(parents=True)
(target / "version").write_text("1.3.3\n")
(target / "docs/mods/manifest.schema.json").write_bytes(pathlib.Path(schema).read_bytes())
files = {}
current = None
for line in pathlib.Path(patch).read_text(encoding="utf-8").splitlines():
    if line.startswith("diff --git "):
        current = line.split(" ")[2][2:]
        files[current] = []
    elif line.startswith("@@ "):
        start = int(line.split(" ")[1][1:].split(",")[0])
        while len(files[current]) < start - 1:
            files[current].append("// fixture padding")
    elif line[:1] in (" ", "-") and current:
        files[current].append(line[1:])
for name, lines in files.items():
    out = target / name
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
PY
    git -C "${target_root}" init -q
    git -C "${target_root}" config user.email test@ambxst.invalid
    git -C "${target_root}" config user.name "Verify test"
    git -C "${target_root}" add -A -f .
    git -C "${target_root}" commit -q --allow-empty -m base
}

copy_project() {
    mkdir -p "${PROJECT_COPY}"
    while IFS= read -r -d '' file; do
        relative="${file#"${PROJECT_ROOT}/"}"
        mkdir -p -- "${PROJECT_COPY}/$(dirname -- "${relative}")"
        cp -a -- "${file}" "${PROJECT_COPY}/${relative}"
    done < <(git -C "${PROJECT_ROOT}" ls-files -z --cached --others --exclude-standard)
}

copy_project
materialize_target "${TEST_ROOT}/target"
mkdir "${TEST_ROOT}/pristine"
cp "${PROJECT_COPY}/ambxst.mod.json" "${TEST_ROOT}/pristine/"
cp "${PROJECT_COPY}/patches/ambxst-integration.patch" "${TEST_ROOT}/pristine/"
cp "${PROJECT_COPY}/docs/mods/manifest.schema.json" "${TEST_ROOT}/pristine/"
cp "${PROJECT_COPY}/payload/modules/widgets/shortcuts/ShortcutData.js" "${TEST_ROOT}/pristine/"
cp "${PROJECT_COPY}/scripts/verify.sh" "${TEST_ROOT}/pristine/"

restore() {
    cp "${TEST_ROOT}/pristine/$(basename -- "$1")" "$1"
}

count=0
fail() {
    printf 'FALLO: %s\n' "$*" >&2
    exit 1
}

expect_success() {
    local label="$1" root="$2" log
    shift 2
    if ! log="$("${root}/scripts/verify.sh" "$@" 2>&1)"; then
        printf '%s\n' "${log}" >&2
        fail "${label} debía pasar"
    fi
    count=$((count + 1))
    printf 'ok %d - %s\n' "${count}" "${label}"
}

expect_failure() {
    local label="$1" root="$2"
    shift 2
    if "${root}/scripts/verify.sh" "$@" > "${TEST_ROOT}/verify.log" 2>&1; then
        fail "${label} debía fallar"
    fi
    count=$((count + 1))
    printf 'ok %d - %s\n' "${count}" "${label}"
}

# --- CLI contract (finding 4): explicit target or --package-only, no magic ---
expect_failure "sin argumentos se falla con uso (sin resolución automática)" "${PROJECT_COPY}"
expect_failure "argumento vacío se rechaza (uso, solo --package-only omite el destino)" "${PROJECT_COPY}" ""
expect_success "ayuda -h termina en 0" "${PROJECT_COPY}" -h
expect_failure "bandera desconocida termina en fallo" "${PROJECT_COPY}" --bogus
expect_failure "dos argumentos termina en fallo (uso)" "${PROJECT_COPY}" "${TEST_ROOT}/target" extra

expect_success "baseline de paquete (--package-only)" "${PROJECT_COPY}" --package-only

snapshot_target() {
    find "${TEST_ROOT}/target" -type f ! -path '*/.git/*' -print0 \
        | LC_ALL=C sort -z | xargs -0 sha256sum
}

tree_before="$(snapshot_target)"
expect_success "baseline con destino temporal" "${PROJECT_COPY}" "${TEST_ROOT}/target"
expect_success "verify no escribe en el destino (repetición)" "${PROJECT_COPY}" "${TEST_ROOT}/target"
tree_after="$(snapshot_target)"
[[ "${tree_before}" == "${tree_after}" ]] || fail "verify.sh modificó el árbol entregado"

# Finding 7: a linked Git worktree (no .git directory) is a valid target.
git -C "${TEST_ROOT}/target" worktree add -q --detach "${TEST_ROOT}/target-wt" HEAD
[[ -f "${TEST_ROOT}/target-wt/.git" && ! -d "${TEST_ROOT}/target-wt/.git" ]] \
    || fail "el worktree debe ser vinculado (.git como archivo apuntador)"
expect_success "baseline con worktree Git vinculado" "${PROJECT_COPY}" "${TEST_ROOT}/target-wt"

# --- Mutations --------------------------------------------------------------

printf '{\n' > "${PROJECT_COPY}/ambxst.mod.json"
expect_failure "manifiesto JSON inválido" "${PROJECT_COPY}" --package-only
restore "${PROJECT_COPY}/ambxst.mod.json"

python3 - "${PROJECT_COPY}/ambxst.mod.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["operations"][0]["replace"] = True
data["operations"][0]["expectedSha256"] = "0" * 64
path.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY
expect_failure "manifiesto con replace:true y expectedSha256 (no permitido)" "${PROJECT_COPY}" --package-only
restore "${PROJECT_COPY}/ambxst.mod.json"

python3 - "${PROJECT_COPY}/ambxst.mod.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["operations"].append({"type": "patch", "source": "patches/ambxst-integration.patch"})
path.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY
expect_failure "manifiesto con 4 operaciones (diseño fijo de 3)" "${PROJECT_COPY}" --package-only
restore "${PROJECT_COPY}/ambxst.mod.json"

python3 - "${PROJECT_COPY}/ambxst.mod.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["name"] = 42
path.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY
expect_failure "manifiesto con name de tipo inválido (name: 42)" "${PROJECT_COPY}" --package-only
restore "${PROJECT_COPY}/ambxst.mod.json"

python3 - "${PROJECT_COPY}/ambxst.mod.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["operations"][0]["target"] = "../escapar"
path.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY
expect_failure "manifiesto con target de escape de paquete" "${PROJECT_COPY}" --package-only
restore "${PROJECT_COPY}/ambxst.mod.json"

cat >> "${PROJECT_COPY}/patches/ambxst-integration.patch" <<'PATCH'
diff --git a/modules/services/Extra.qml b/modules/services/Extra.qml
new file mode 100644
index 0000000..e69de29
--- /dev/null
+++ b/modules/services/Extra.qml
@@ -0,0 +1 @@
+
PATCH
expect_failure "parche con alcance ampliado" "${PROJECT_COPY}" --package-only
restore "${PROJECT_COPY}/patches/ambxst-integration.patch"

printf '\n''syntax error(!!\n' >> "${PROJECT_COPY}/payload/modules/widgets/shortcuts/ShortcutData.js"
expect_failure "JS roto en payload" "${PROJECT_COPY}" --package-only
restore "${PROJECT_COPY}/payload/modules/widgets/shortcuts/ShortcutData.js"

printf '\nif then\n' >> "${PROJECT_COPY}/scripts/verify.sh"
expect_failure "sintaxis bash inválida" "${PROJECT_COPY}" --package-only
restore "${PROJECT_COPY}/scripts/verify.sh"

rm -- "${PROJECT_COPY}/payload/modules/widgets/shortcuts/ShortcutData.js"
expect_failure "payload faltante" "${PROJECT_COPY}" --package-only

printf 'OK: %d regresiones de verify (CLI, baseline y mutaciones aisladas).\n' "${count}"