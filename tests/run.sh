#!/usr/bin/env bash
set -euo pipefail
readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
node "${TEST_DIR}/shortcut-data.test.js"
node "${TEST_DIR}/hardening.test.js"
bash "${TEST_DIR}/verify.test.sh"
bash "${TEST_DIR}/transactional-scripts.test.sh"
python3 "${TEST_DIR}/deployment.test.py"
python3 "${TEST_DIR}/qml.test.py"
