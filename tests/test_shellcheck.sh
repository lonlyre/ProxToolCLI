#!/usr/bin/env bash
# =============================================================================
# tests/test_shellcheck.sh — Analyse statique ShellCheck sur tous les scripts
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
source "${TESTS_DIR}/framework.sh"

# =============================================================================
describe "ShellCheck — disponibilité"
# =============================================================================

if ! command -v shellcheck &>/dev/null; then
    echo -e "  \033[1;33m⚠ shellcheck non installé — tests statiques ignorés\033[0m"
    test_summary
    exit 0
fi

sc_version=$(shellcheck --version | grep version | head -1)
assert_not_empty "shellcheck disponible ($sc_version)" "$sc_version"

# =============================================================================
describe "ShellCheck — scripts principaux"
# =============================================================================

# Options shellcheck communes
SC_OPTS=(
    --shell=bash
    --severity=warning
    # SC2034: variable unused (faux positifs sur variables d'env utilisées ailleurs)
    --exclude=SC2034
    # SC1091: source non-résolvable statiquement (expected pour les modules)
    --exclude=SC1091
    # SC2154: variable référencée mais non assignée (variables d'env)
    --exclude=SC2154
)

run_shellcheck() {
    local file="$1"
    local desc="$2"
    local errors
    errors=$(shellcheck "${SC_OPTS[@]}" "$file" 2>&1)
    local code=$?
    if [[ $code -eq 0 ]]; then
        (( TESTS_RUN++ ))
        echo -e "  \033[1;32m✔\033[0m $desc"
        (( TESTS_PASSED++ ))
    else
        (( TESTS_RUN++ ))
        echo -e "  \033[1;31m✘\033[0m $desc"
        # Affiche uniquement les erreurs/warnings
        echo "$errors" | grep -E '^\s*(In |[0-9]+:[0-9]+)' | head -20 | while read -r line; do
            echo "      $line"
        done
        (( TESTS_FAILED++ ))
        _FAILURES+=("ShellCheck: $desc")
    fi
}

run_shellcheck "${ROOT_DIR}/proxmox-admin.sh"        "proxmox-admin.sh"
run_shellcheck "${ROOT_DIR}/lib/common.sh"           "lib/common.sh"
run_shellcheck "${ROOT_DIR}/lib/deploy.sh"           "lib/deploy.sh"
run_shellcheck "${ROOT_DIR}/lib/lifecycle.sh"        "lib/lifecycle.sh"
run_shellcheck "${ROOT_DIR}/lib/supervision.sh"      "lib/supervision.sh"
run_shellcheck "${ROOT_DIR}/lib/snapshot.sh"         "lib/snapshot.sh"
run_shellcheck "${ROOT_DIR}/lib/delete.sh"           "lib/delete.sh"
run_shellcheck "${ROOT_DIR}/examples/full-deployment.sh" "examples/full-deployment.sh"

# =============================================================================
describe "ShellCheck — scripts de test"
# =============================================================================

run_shellcheck "${ROOT_DIR}/tests/framework.sh"               "tests/framework.sh"
run_shellcheck "${ROOT_DIR}/tests/mocks/proxmox_mocks.sh"     "tests/mocks/proxmox_mocks.sh"
run_shellcheck "${ROOT_DIR}/tests/test_common.sh"             "tests/test_common.sh"
run_shellcheck "${ROOT_DIR}/tests/test_lifecycle.sh"          "tests/test_lifecycle.sh"
run_shellcheck "${ROOT_DIR}/tests/test_deploy_snap_delete.sh" "tests/test_deploy_snap_delete.sh"
run_shellcheck "${ROOT_DIR}/tests/test_supervision.sh"        "tests/test_supervision.sh"

# =============================================================================
describe "Vérifications de structure"
# =============================================================================

# Fichiers obligatoires
for f in \
    "${ROOT_DIR}/proxmox-admin.sh" \
    "${ROOT_DIR}/config.conf" \
    "${ROOT_DIR}/README.md" \
    "${ROOT_DIR}/lib/common.sh" \
    "${ROOT_DIR}/lib/deploy.sh" \
    "${ROOT_DIR}/lib/lifecycle.sh" \
    "${ROOT_DIR}/lib/supervision.sh" \
    "${ROOT_DIR}/lib/snapshot.sh" \
    "${ROOT_DIR}/lib/delete.sh" \
    "${ROOT_DIR}/examples/full-deployment.sh"; do
    assert_file_exists "Fichier présent : $(basename "$f")" "$f"
done

# Permissions exécutables
for f in \
    "${ROOT_DIR}/proxmox-admin.sh" \
    "${ROOT_DIR}/examples/full-deployment.sh"; do
    assert_executable "Exécutable : $(basename "$f")" "$f"
done

# Pas de tabs mélangés avec des espaces pour l'indentation (style cohérent)
for f in "${ROOT_DIR}"/lib/*.sh "${ROOT_DIR}/proxmox-admin.sh"; do
    mixed=$(grep -Pn '^\t+ ' "$f" | wc -l)
    assert_eq "Pas de mix tab+espace dans $(basename "$f")" "0" "$mixed"
done

# Vérification que chaque lib a sa protection double-chargement
for module in common deploy lifecycle supervision snapshot delete; do
    has_guard=$(grep -c "_${module^^}_LOADED" "${ROOT_DIR}/lib/${module}.sh" || true)
    assert_eq "lib/${module}.sh a une garde double-chargement" "2" "$has_guard"
done

# =============================================================================
test_summary
