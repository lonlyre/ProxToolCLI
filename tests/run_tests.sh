#!/usr/bin/env bash
# =============================================================================
# tests/run_tests.sh — Lanceur de tous les tests
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' Z='\033[0m'

START_TIME=$(date +%s)
TOTAL_RUN=0 TOTAL_PASSED=0 TOTAL_FAILED=0
SUITE_RESULTS=()

echo ""
echo -e "${B}╔══════════════════════════════════════════════════════════════╗${Z}"
echo -e "${B}║         PROXMOX ADMIN — Suite de tests complète             ║${Z}"
echo -e "${B}║         $(date '+%Y-%m-%d %H:%M:%S')                              ║${Z}"
echo -e "${B}╚══════════════════════════════════════════════════════════════╝${Z}"

# Ordre des suites
SUITES=(
    "test_shellcheck.sh:Analyse statique ShellCheck + structure"
    "test_common.sh:Module common.sh (logs, helpers, VMID)"
    "test_lifecycle.sh:Module lifecycle.sh (start/stop/reboot/suspend)"
    "test_deploy_snap_delete.sh:Modules deploy, snapshot, delete"
    "test_supervision.sh:Module supervision.sh (list, resources, check)"
)

for suite_entry in "${SUITES[@]}"; do
    suite_file="${suite_entry%%:*}"
    suite_desc="${suite_entry##*:}"
    suite_path="${TESTS_DIR}/${suite_file}"

    echo ""
    echo -e "${C}┌──────────────────────────────────────────────────────────${Z}"
    echo -e "${C}│ Suite : ${B}${suite_desc}${Z}"
    echo -e "${C}└──────────────────────────────────────────────────────────${Z}"

    if [[ ! -f "$suite_path" ]]; then
        echo -e "  ${R}✘ Fichier de test introuvable : $suite_path${Z}"
        SUITE_RESULTS+=("SKIP:$suite_desc")
        continue
    fi

    # Exécute la suite dans un sous-shell isolé
    suite_output=$(bash "$suite_path" 2>&1)
    suite_code=$?

    echo "$suite_output"

    # Extrait les compteurs du résumé
    run=$(echo "$suite_output"    | grep 'Tests exécutés'  | grep -oE '[0-9]+' | tail -1)
    passed=$(echo "$suite_output" | grep 'Réussis'         | grep -oE '[0-9]+' | tail -1)
    failed=$(echo "$suite_output" | grep 'Échoués'         | grep -oE '[0-9]+' | tail -1)

    run="${run:-0}" passed="${passed:-0}" failed="${failed:-0}"
    TOTAL_RUN=$(( TOTAL_RUN + run ))
    TOTAL_PASSED=$(( TOTAL_PASSED + passed ))
    TOTAL_FAILED=$(( TOTAL_FAILED + failed ))

    if [[ "$failed" -eq 0 && "$suite_code" -eq 0 ]]; then
        SUITE_RESULTS+=("PASS:$suite_desc ($run tests)")
    else
        SUITE_RESULTS+=("FAIL:$suite_desc ($failed échec(s) sur $run)")
    fi
done

# =============================================================================
# RAPPORT FINAL
# =============================================================================
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

echo ""
echo -e "${B}╔══════════════════════════════════════════════════════════════╗${Z}"
echo -e "${B}║                   RAPPORT FINAL                             ║${Z}"
echo -e "${B}╠══════════════════════════════════════════════════════════════╣${Z}"

for result in "${SUITE_RESULTS[@]}"; do
    status="${result%%:*}"
    desc="${result##*:}"
    if [[ "$status" == "PASS" ]]; then
        echo -e "${B}║${Z}  ${G}✔ PASS${Z}  $desc"
    elif [[ "$status" == "FAIL" ]]; then
        echo -e "${B}║${Z}  ${R}✘ FAIL${Z}  $desc"
    else
        echo -e "${B}║${Z}  ${Y}⚠ SKIP${Z}  $desc"
    fi
done

echo -e "${B}╠══════════════════════════════════════════════════════════════╣${Z}"
printf "${B}║${Z}  %-20s : %d\n"                   "Tests exécutés" "$TOTAL_RUN"
printf "${B}║${Z}  ${G}%-20s${Z} : ${G}%d${Z}\n"  "Réussis"        "$TOTAL_PASSED"
printf "${B}║${Z}  ${R}%-20s${Z} : ${R}%d${Z}\n"  "Échoués"        "$TOTAL_FAILED"
printf "${B}║${Z}  %-20s : %ds\n"                  "Durée totale"   "$DURATION"
echo -e "${B}╚══════════════════════════════════════════════════════════════╝${Z}"
echo ""

if [[ "$TOTAL_FAILED" -eq 0 ]]; then
    echo -e "  ${G}${B}✔ Tous les tests sont verts — code prêt pour production !${Z}"
    echo ""
    exit 0
else
    echo -e "  ${R}${B}✘ $TOTAL_FAILED test(s) en échec — voir les détails ci-dessus.${Z}"
    echo ""
    exit 1
fi
