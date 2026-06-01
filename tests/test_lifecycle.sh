#!/usr/bin/env bash
# =============================================================================
# tests/test_lifecycle.sh — Tests unitaires : lib/lifecycle.sh
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TESTS_DIR}/framework.sh"
source "${TESTS_DIR}/mocks/proxmox_mocks.sh"

PVE_NODE="pve-test"
LOG_FILE="/tmp/proxmox-lifecycle-test-$$.log"
CONFIRM_DESTRUCTIVE=0
FORCE_COLOR=1
TIMEOUT_START=5   # Réduit pour les tests
TIMEOUT_STOP=5

source "${TESTS_DIR}/../lib/common.sh"
source "${TESTS_DIR}/../lib/lifecycle.sh"

# =============================================================================
describe "lifecycle_action — validation des arguments"
# =============================================================================

result=0
(lifecycle_action --action start) 2>/dev/null || result=$?
assert_eq "Manque --vmid → die()" "1" "$result"

result=0
(lifecycle_action --vmid 100) 2>/dev/null || result=$?
assert_eq "Manque --action → die()" "1" "$result"

result=0
(lifecycle_action --action start --vmid 9999) 2>/dev/null || result=$?
assert_eq "VMID inexistant → die()" "1" "$result"

result=0
(lifecycle_action --action badaction --vmid 100) 2>/dev/null || result=$?
assert_eq "Action inconnue → die()" "1" "$result"

# =============================================================================
describe "vm_start — démarrage VM"
# =============================================================================

mock_reset
# VMID 101 est stopped → start doit le passer running
vm_start 101 "qemu" 2>/dev/null
assert_eq "vm_start VMID 101 → running" "running" "${_VM_STATUS[101]}"
assert_eq "qm start appelé 1 fois" "1" "$(mock_call_count qm_start)"

# Démarrage d'une machine déjà running → idempotent
mock_reset
output=$(vm_start 100 "qemu" 2>&1)
assert_eq "vm_start sur machine running → pas de double start" "0" "$(mock_call_count qm_start)"
assert_contains "Message 'déjà en cours'" "déjà" "$output"

# =============================================================================
describe "vm_stop — arrêt forcé"
# =============================================================================

mock_reset
vm_stop 100 "qemu" 2>/dev/null
assert_eq "vm_stop VMID 100 → stopped" "stopped" "${_VM_STATUS[100]}"
assert_eq "qm stop appelé 1 fois" "1" "$(mock_call_count qm_stop)"

# Stop d'une machine déjà stopped → idempotent
mock_reset
output=$(vm_stop 101 "qemu" 2>&1)
assert_eq "vm_stop sur machine stopped → pas de double stop" "0" "$(mock_call_count qm_stop)"

# =============================================================================
describe "vm_shutdown — arrêt propre ACPI"
# =============================================================================

mock_reset
vm_shutdown 100 "qemu" 0 2>/dev/null
assert_eq "vm_shutdown VMID 100 → stopped" "stopped" "${_VM_STATUS[100]}"
assert_eq "qm shutdown appelé" "1" "$(mock_call_count qm_shutdown)"

# Shutdown d'une machine déjà stopped
mock_reset
output=$(vm_shutdown 101 "qemu" 0 2>&1)
assert_contains "Déjà arrêté → message approprié" "déjà" "$output"
assert_eq "Pas d'appel shutdown si déjà stopped" "0" "$(mock_call_count qm_shutdown)"

# =============================================================================
describe "vm_reboot — redémarrage"
# =============================================================================

mock_reset
vm_reboot 100 "qemu" 2>/dev/null
assert_eq "qm reboot appelé sur VM running" "1" "$(mock_call_count qm_reboot)"

# Reboot sur machine stopped → déclenche start
mock_reset
vm_reboot 101 "qemu" 2>/dev/null
assert_eq "Reboot sur stopped → start déclenché" "1" "$(mock_call_count qm_start)"
assert_eq "Pas de reboot sur stopped" "0" "$(mock_call_count qm_reboot)"

# =============================================================================
describe "vm_suspend — suspension"
# =============================================================================

mock_reset
vm_suspend 100 "qemu" 2>/dev/null
assert_eq "vm_suspend VMID 100 → suspended" "suspended" "${_VM_STATUS[100]}"
assert_eq "qm suspend appelé" "1" "$(mock_call_count qm_suspend)"

# Suspend sur LXC → refus
mock_reset
result=0
(vm_suspend 200 "lxc") 2>/dev/null || result=$?
assert_eq "Suspend LXC → retour 1" "1" "$result"

# Suspend sur machine stopped → refus
mock_reset
result=0
(vm_suspend 101 "qemu") 2>/dev/null || result=$?
assert_eq "Suspend machine stopped → die()" "1" "$result"

# =============================================================================
describe "vm_resume — reprise"
# =============================================================================

mock_reset
_VM_STATUS[100]="suspended"
vm_resume 100 "qemu" 2>/dev/null
assert_eq "vm_resume VMID 100 → running" "running" "${_VM_STATUS[100]}"
assert_eq "qm resume appelé" "1" "$(mock_call_count qm_resume)"

# Resume sur LXC → start
mock_reset
vm_resume 201 "lxc" 2>/dev/null
assert_eq "Resume LXC stopped → pct start appelé" "1" "$(mock_call_count pct_start)"

# =============================================================================
describe "Lifecycle LXC — start/stop/shutdown"
# =============================================================================

mock_reset
vm_start 201 "lxc" 2>/dev/null
assert_eq "pct start VMID 201" "running" "${_LXC_STATUS[201]}"
assert_eq "pct start appelé 1 fois" "1" "$(mock_call_count pct_start)"

mock_reset
vm_stop 200 "lxc" 2>/dev/null
assert_eq "pct stop VMID 200 → stopped" "stopped" "${_LXC_STATUS[200]}"
assert_eq "pct stop appelé 1 fois" "1" "$(mock_call_count pct_stop)"

mock_reset
vm_shutdown 200 "lxc" 0 2>/dev/null
assert_eq "pct shutdown VMID 200 → stopped" "stopped" "${_LXC_STATUS[200]}"

# =============================================================================
describe "lifecycle_action — dispatcher complet"
# =============================================================================

mock_reset
lifecycle_action --action start --vmid 101 2>/dev/null
assert_eq "dispatcher start VM 101" "running" "${_VM_STATUS[101]}"

mock_reset
lifecycle_action --action stop --vmid 100 2>/dev/null
assert_eq "dispatcher stop VM 100" "stopped" "${_VM_STATUS[100]}"

mock_reset
lifecycle_action --action start --vmid 201 2>/dev/null
assert_eq "dispatcher start LXC 201" "running" "${_LXC_STATUS[201]}"

mock_reset
lifecycle_action --action shutdown --vmid 200 2>/dev/null
assert_eq "dispatcher shutdown LXC 200" "stopped" "${_LXC_STATUS[200]}"

# =============================================================================
rm -f "$LOG_FILE"
test_summary
