#!/usr/bin/env bash
set -euo pipefail
readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export PYTHONDONTWRITEBYTECODE=1
node "${TEST_DIR}/shortcut-data.test.js"
node "${TEST_DIR}/hardening.test.js"
python3 "${TEST_DIR}/manifest.test.py"
python3 "${TEST_DIR}/composition.test.py"
bash "${TEST_DIR}/verify.test.sh"
python3 "${TEST_DIR}/qml.test.py"