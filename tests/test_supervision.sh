#!/usr/bin/env bash
# =============================================================================
# tests/test_supervision.sh — Tests : lib/supervision.sh
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TESTS_DIR}/framework.sh"
source "${TESTS_DIR}/mocks/proxmox_mocks.sh"

PVE_NODE="pve-test"
LOG_FILE="/tmp/proxmox-sup-test-$$.log"
CONFIRM_DESTRUCTIVE=0
FORCE_COLOR=0   # Désactive les couleurs pour faciliter les assertions texte
VM_DEFAULT_CPU=2
VM_DEFAULT_RAM=2048
DEFAULT_STORAGE="local-lvm"

source "${TESTS_DIR}/../lib/common.sh"
source "${TESTS_DIR}/../lib/supervision.sh"

# =============================================================================
describe "supervision_list — listing complet"
# =============================================================================

output=$(supervision_list 2>/dev/null)

assert_contains "Liste contient VMID 100" "100" "$output"
assert_contains "Liste contient VMID 101" "101" "$output"
assert_contains "Liste contient VMID 200" "200" "$output"
assert_contains "Liste contient VMID 201" "201" "$output"
assert_contains "Liste contient web-prod" "web-prod" "$output"
assert_contains "Liste contient monitoring" "monitoring" "$output"
assert_contains "Liste contient le type VM" "VM" "$output"
assert_contains "Liste contient le type LXC" "LXC" "$output"
assert_contains "Liste contient statut running" "running" "$output"
assert_contains "Liste contient statut stopped" "stopped" "$output"

# =============================================================================
describe "supervision_list — filtrage par type"
# =============================================================================

output=$(supervision_list --type vm 2>/dev/null)
assert_contains "Filtre VM : contient web-prod" "web-prod" "$output"

# Vérifie l'absence de lignes d'entrée LXC (type affiché = "LXC" en colonne type)
# Note: la ligne "Total:" contient "LXC(s)" → on exclut en cherchant " LXC " avec espaces
vm_only_lxc=$(echo "$output" | grep -cE "^[0-9]+ +LXC " || true)
assert_eq "Filtre VM : pas de ligne entrée LXC" "0" "$vm_only_lxc"

output=$(supervision_list --type lxc 2>/dev/null)
assert_contains "Filtre LXC : contient monitoring" "monitoring" "$output"
no_vm=$(echo "$output" | grep -c "web-prod" || true)
assert_eq "Filtre LXC : pas de VM" "0" "$no_vm"

# =============================================================================
describe "supervision_list — filtrage par statut"
# =============================================================================

output=$(supervision_list --status running 2>/dev/null)
assert_contains "Filtre running : contient web-prod (running)" "web-prod" "$output"
no_stopped=$(echo "$output" | grep -c "db-server" || true)
assert_eq "Filtre running : pas de db-server (stopped)" "0" "$no_stopped"

output=$(supervision_list --status stopped 2>/dev/null)
assert_contains "Filtre stopped : contient db-server" "db-server" "$output"
no_running=$(echo "$output" | grep -c "web-prod" || true)
assert_eq "Filtre stopped : pas de web-prod" "0" "$no_running"

# =============================================================================
describe "supervision_resources — infos machine"
# =============================================================================

# Manque --vmid → die()
result=0
(supervision_resources) 2>/dev/null || result=$?
assert_eq "Manque --vmid → die()" "1" "$result"

# VMID inexistant → die()
result=0
(supervision_resources --vmid 9999) 2>/dev/null || result=$?
assert_eq "VMID inexistant → die()" "1" "$result"

# VM valide
output=$(supervision_resources --vmid 100 2>/dev/null)
assert_contains "Resources VMID 100 : type qemu" "QEMU" "$output"
assert_contains "Resources VMID 100 : running" "running" "$output"
assert_contains "Resources VMID 100 : nom web-prod" "web-prod" "$output"

# LXC valide
output=$(supervision_resources --vmid 200 2>/dev/null)
assert_contains "Resources VMID 200 : type LXC" "LXC" "$output"
assert_contains "Resources VMID 200 : monitoring" "monitoring" "$output"

# =============================================================================
describe "supervision_check — vérification connectivité"
# =============================================================================

# Manque --vmid → die()
result=0
(supervision_check) 2>/dev/null || result=$?
assert_eq "Manque --vmid → die()" "1" "$result"

# Machine stopped → retour 1 (pas de test réseau)
result=0
supervision_check --vmid 101 2>/dev/null || result=$?
assert_eq "Machine stopped → check retourne 1 (skip réseau)" "1" "$result"

# Machine running avec IP fournie
output=$(supervision_check --vmid 100 --ip "192.168.1.100" 2>/dev/null || true)
assert_contains "Check inclut test Ping" "Ping" "$output"

# =============================================================================
describe "Helpers internes — _colorize_status"
# =============================================================================

FORCE_COLOR=1
source "${TESTS_DIR}/../lib/common.sh"  # Recharge les couleurs

output=$(_colorize_status "running")
assert_contains "_colorize_status running contient 'running'" "running" "$output"

output=$(_colorize_status "stopped")
assert_contains "_colorize_status stopped contient 'stopped'" "stopped" "$output"

output=$(_colorize_status "unknown_state")
assert_contains "_colorize_status unknown contient la valeur" "unknown_state" "$output"

# =============================================================================
describe "Helpers internes — _usage_bar"
# =============================================================================

FORCE_COLOR=0
bar=$(_usage_bar 0)
assert_contains "_usage_bar 0% contient crochets" "[" "$bar"

bar=$(_usage_bar 50)
assert_contains "_usage_bar 50% contient ░" "░" "$bar"

bar=$(_usage_bar 100)
assert_contains "_usage_bar 100% contient █" "█" "$bar"

# =============================================================================
describe "Helpers internes — _get_vm_ip / _get_lxc_ip"
# =============================================================================

ip=$(_get_vm_ip 100 2>/dev/null)
assert_not_empty "IP VM 100 non vide" "$ip"

ip=$(_get_lxc_ip 200 2>/dev/null)
assert_not_empty "IP LXC 200 non vide" "$ip"

# =============================================================================
rm -f "$LOG_FILE"
test_summary
