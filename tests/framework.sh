#!/usr/bin/env bash
# =============================================================================
# tests/framework.sh — Framework de tests minimaliste
# =============================================================================
# Fournit : assert_eq, assert_contains, assert_exit_code, assert_file_exists
# Variables globales : TESTS_RUN, TESTS_PASSED, TESTS_FAILED

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
_CURRENT_SUITE=""
_FAILURES=()

# Couleurs
R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' Z='\033[0m'

# --- Déclare une suite de tests ---
describe() {
    _CURRENT_SUITE="$*"
    echo -e "\n${C}▶ ${_CURRENT_SUITE}${Z}"
}

# --- Vérifie égalité stricte ---
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    (( TESTS_RUN++ ))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${G}✔${Z} $desc"
        (( TESTS_PASSED++ ))
    else
        echo -e "  ${R}✘${Z} $desc"
        echo -e "      attendu : ${Y}'${expected}'${Z}"
        echo -e "      obtenu  : ${R}'${actual}'${Z}"
        (( TESTS_FAILED++ ))
        _FAILURES+=("[$_CURRENT_SUITE] $desc")
    fi
}

# --- Vérifie que la valeur contient un sous-string ---
assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    (( TESTS_RUN++ ))
    if echo "$haystack" | grep -qF "$needle"; then
        echo -e "  ${G}✔${Z} $desc"
        (( TESTS_PASSED++ ))
    else
        echo -e "  ${R}✘${Z} $desc"
        echo -e "      cherché   : ${Y}'${needle}'${Z}"
        echo -e "      dans      : ${R}'${haystack}'${Z}"
        (( TESTS_FAILED++ ))
        _FAILURES+=("[$_CURRENT_SUITE] $desc")
    fi
}

# --- Vérifie qu'un pattern regex correspond ---
assert_matches() {
    local desc="$1" pattern="$2" actual="$3"
    (( TESTS_RUN++ ))
    if echo "$actual" | grep -qE "$pattern"; then
        echo -e "  ${G}✔${Z} $desc"
        (( TESTS_PASSED++ ))
    else
        echo -e "  ${R}✘${Z} $desc"
        echo -e "      pattern : ${Y}'${pattern}'${Z}"
        echo -e "      obtenu  : ${R}'${actual}'${Z}"
        (( TESTS_FAILED++ ))
        _FAILURES+=("[$_CURRENT_SUITE] $desc")
    fi
}

# --- Vérifie le code de retour d'une commande ---
assert_exit_code() {
    local desc="$1" expected_code="$2"
    shift 2
    (( TESTS_RUN++ ))
    local actual_code=0
    "$@" &>/dev/null || actual_code=$?
    if [[ "$actual_code" == "$expected_code" ]]; then
        echo -e "  ${G}✔${Z} $desc (code=$actual_code)"
        (( TESTS_PASSED++ ))
    else
        echo -e "  ${R}✘${Z} $desc"
        echo -e "      code attendu : ${Y}$expected_code${Z}"
        echo -e "      code obtenu  : ${R}$actual_code${Z}"
        (( TESTS_FAILED++ ))
        _FAILURES+=("[$_CURRENT_SUITE] $desc")
    fi
}

# --- Vérifie qu'une commande réussit (code 0) ---
assert_success() {
    local desc="$1"
    shift
    assert_exit_code "$desc" 0 "$@"
}

# --- Vérifie qu'une commande échoue (code != 0) ---
assert_failure() {
    local desc="$1"
    shift
    (( TESTS_RUN++ ))
    local code=0
    "$@" &>/dev/null || code=$?
    if [[ "$code" -ne 0 ]]; then
        echo -e "  ${G}✔${Z} $desc (code=$code, attendu ≠0)"
        (( TESTS_PASSED++ ))
    else
        echo -e "  ${R}✘${Z} $desc (attendu echec, obtenu code=0)"
        (( TESTS_FAILED++ ))
        _FAILURES+=("[$_CURRENT_SUITE] $desc")
    fi
}

# --- Vérifie qu'un fichier existe ---
assert_file_exists() {
    local desc="$1" filepath="$2"
    (( TESTS_RUN++ ))
    if [[ -f "$filepath" ]]; then
        echo -e "  ${G}✔${Z} $desc"
        (( TESTS_PASSED++ ))
    else
        echo -e "  ${R}✘${Z} $desc — fichier absent : $filepath"
        (( TESTS_FAILED++ ))
        _FAILURES+=("[$_CURRENT_SUITE] $desc")
    fi
}

# --- Vérifie qu'un fichier est exécutable ---
assert_executable() {
    local desc="$1" filepath="$2"
    (( TESTS_RUN++ ))
    if [[ -x "$filepath" ]]; then
        echo -e "  ${G}✔${Z} $desc"
        (( TESTS_PASSED++ ))
    else
        echo -e "  ${R}✘${Z} $desc — non exécutable : $filepath"
        (( TESTS_FAILED++ ))
        _FAILURES+=("[$_CURRENT_SUITE] $desc")
    fi
}

# --- Vérifie qu'une variable est non vide ---
assert_not_empty() {
    local desc="$1" value="$2"
    (( TESTS_RUN++ ))
    if [[ -n "$value" ]]; then
        echo -e "  ${G}✔${Z} $desc"
        (( TESTS_PASSED++ ))
    else
        echo -e "  ${R}✘${Z} $desc — valeur vide"
        (( TESTS_FAILED++ ))
        _FAILURES+=("[$_CURRENT_SUITE] $desc")
    fi
}

# --- Rapport final ---
test_summary() {
    local duration="${1:-?}"
    echo ""
    echo -e "${B}════════════════════════════════════════════════════════${Z}"
    echo -e "${B}  RÉSULTATS DES TESTS${Z}"
    echo -e "${B}════════════════════════════════════════════════════════${Z}"
    printf "  Tests exécutés  : %d\n" "$TESTS_RUN"
    printf "  ${G}Réussis${Z}         : %d\n" "$TESTS_PASSED"
    printf "  ${R}Échoués${Z}         : %d\n" "$TESTS_FAILED"
    printf "  Durée           : %ss\n" "$duration"
    echo ""

    if [[ ${#_FAILURES[@]} -gt 0 ]]; then
        echo -e "  ${R}Tests échoués :${Z}"
        for f in "${_FAILURES[@]}"; do
            echo -e "    ${R}•${Z} $f"
        done
        echo ""
    fi

    if [[ "$TESTS_FAILED" -eq 0 ]]; then
        echo -e "  ${G}✔ Tous les tests sont passés !${Z}"
        echo -e "${B}════════════════════════════════════════════════════════${Z}"
        return 0
    else
        echo -e "  ${R}✘ $TESTS_FAILED test(s) en échec${Z}"
        echo -e "${B}════════════════════════════════════════════════════════${Z}"
        return 1
    fi
}
