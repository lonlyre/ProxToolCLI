#!/usr/bin/env bash
# =============================================================================
# tests/test_common.sh — Tests unitaires : lib/common.sh
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TESTS_DIR}/framework.sh"
source "${TESTS_DIR}/mocks/proxmox_mocks.sh"

# Charge common.sh avec des variables factices
PVE_NODE="pve-test"
VMID_MIN=100
VMID_MAX=9999
LOG_FILE="/tmp/proxmox-admin-test-$$.log"
FORCE_COLOR=1
CONFIRM_DESTRUCTIVE=0  # Pas de prompt en mode test

source "${TESTS_DIR}/../lib/common.sh"

# =============================================================================
describe "Chargement du module common.sh"
# =============================================================================

assert_eq "Variable _COMMON_LOADED définie" "1" "${_COMMON_LOADED:-}"
assert_not_empty "Variable C_RESET définie" "${C_RESET}"
assert_not_empty "Variable C_BGREEN définie" "${C_BGREEN}"

# =============================================================================
describe "Fonctions de logging"
# =============================================================================

# Capture la sortie des fonctions de log
output=$(log_info "message info test" 2>&1)
assert_contains "log_info contient le message" "message info test" "$output"

output=$(log_warn "message warn test" 2>&1)
assert_contains "log_warn contient le message" "message warn test" "$output"

output=$(log_error "message error test" 2>&1)
assert_contains "log_error contient le message" "message error test" "$output"

output=$(log_success "message succès test" 2>&1)
assert_contains "log_success contient le message" "message succès test" "$output"

# Test que le log est bien écrit dans le fichier
log_info "écriture fichier log" >/dev/null 2>&1
assert_file_exists "Fichier de log créé" "$LOG_FILE"
content=$(cat "$LOG_FILE")
assert_contains "Contenu écrit dans le fichier log" "écriture fichier log" "$content"

# =============================================================================
describe "Gestion des niveaux de log"
# =============================================================================

LOG_LEVEL=ERROR
output=$(log_info "ne doit pas apparaître" 2>&1)
assert_eq "log_info silencieux si LOG_LEVEL=ERROR" "" "$output"

output=$(log_error "doit apparaître" 2>&1)
assert_contains "log_error visible si LOG_LEVEL=ERROR" "doit apparaître" "$output"

LOG_LEVEL=INFO  # Reset

# =============================================================================
describe "Fonction die()"
# =============================================================================

# die() doit quitter avec le bon code
result=0
(die "erreur test" 42) 2>/dev/null || result=$?
assert_eq "die() retourne le bon code" "42" "$result"

result=0
(die "erreur par défaut") 2>/dev/null || result=$?
assert_eq "die() code par défaut = 1" "1" "$result"

# =============================================================================
describe "Utilitaires VMID — vmid_type()"
# =============================================================================

type_vm=$(vmid_type 100)
assert_eq "VMID 100 est une qemu VM" "qemu" "$type_vm"

type_lxc=$(vmid_type 200)
assert_eq "VMID 200 est un LXC" "lxc" "$type_lxc"

type_unknown=$(vmid_type 9999)
assert_eq "VMID 9999 est inconnu" "" "$type_unknown"

# =============================================================================
describe "Utilitaires VMID — vmid_exists()"
# =============================================================================

vmid_exists 100
assert_eq "VMID 100 existe (VM)" "0" "$?"

vmid_exists 200
assert_eq "VMID 200 existe (LXC)" "0" "$?"

vmid_exists 9999 2>/dev/null
assert_eq "VMID 9999 n'existe pas" "1" "$?"

# =============================================================================
describe "Utilitaires VMID — vmid_status()"
# =============================================================================

status=$(vmid_status 100)
assert_eq "VMID 100 status = running" "running" "$status"

status=$(vmid_status 101)
assert_eq "VMID 101 status = stopped" "stopped" "$status"

status=$(vmid_status 200)
assert_eq "VMID 200 (LXC) status = running" "running" "$status"

status=$(vmid_status 201)
assert_eq "VMID 201 (LXC) status = stopped" "stopped" "$status"

# =============================================================================
describe "Utilitaires VMID — vmid_name()"
# =============================================================================

name=$(vmid_name 100)
assert_eq "VMID 100 nom = web-prod" "web-prod" "$name"

name=$(vmid_name 200)
assert_eq "VMID 200 (LXC) nom = monitoring" "monitoring" "$name"

# =============================================================================
describe "Utilitaires VMID — next_vmid()"
# =============================================================================

# Avec l'état mock (100, 101, 200, 201, 9000 utilisés), le prochain libre est 102
VMID_MIN=100
next=$(next_vmid)
# 100, 101 utilisés (VM), 102 doit être libre
assert_eq "next_vmid() retourne 102 (premier libre)" "102" "$next"

# Test avec plage différente
VMID_MIN=300
next=$(next_vmid)
assert_eq "next_vmid() avec VMID_MIN=300 retourne 300" "300" "$next"
VMID_MIN=100  # reset

# =============================================================================
describe "Fonctions de formatage"
# =============================================================================

result=$(format_mem 512)
assert_eq "format_mem 512 Mo" "512 Mo" "$result"

result=$(format_mem 1024)
assert_eq "format_mem 1024 Mo = 1.0 Go" "1.0 Go" "$result"

result=$(format_mem 2048)
assert_eq "format_mem 2048 Mo = 2.0 Go" "2.0 Go" "$result"

# =============================================================================
describe "Fonction confirm() — mode non-interactif"
# =============================================================================

CONFIRM_DESTRUCTIVE=0  # Mode auto-oui
confirm "Test confirm auto-oui ?"
assert_eq "confirm() retourne 0 si CONFIRM_DESTRUCTIVE=0" "0" "$?"

# =============================================================================
describe "Chargement de la configuration"
# =============================================================================

# Crée un fichier config temporaire
tmp_conf=$(mktemp /tmp/test-config-XXXX.conf)
echo 'PVE_NODE="test-node-from-config"' > "$tmp_conf"
echo 'VM_DEFAULT_CPU=8' >> "$tmp_conf"

load_config "$tmp_conf"
assert_eq "load_config charge PVE_NODE" "test-node-from-config" "$PVE_NODE"
assert_eq "load_config charge VM_DEFAULT_CPU" "8" "$VM_DEFAULT_CPU"

rm -f "$tmp_conf"
PVE_NODE="pve-test"  # Reset

# =============================================================================
# Nettoyage
rm -f "$LOG_FILE"

test_summary
