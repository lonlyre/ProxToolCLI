#!/usr/bin/env bash
# =============================================================================
# tests/test_deploy_snap_delete.sh — Tests : deploy, snapshot, delete
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TESTS_DIR}/framework.sh"
source "${TESTS_DIR}/mocks/proxmox_mocks.sh"

PVE_NODE="pve-test"
LOG_FILE="/tmp/proxmox-dsd-test-$$.log"
CONFIRM_DESTRUCTIVE=0
FORCE_COLOR=1
TIMEOUT_START=5
TIMEOUT_STOP=5
VM_DEFAULT_CPU=2
VM_DEFAULT_RAM=2048
VM_DEFAULT_DISK=20
DEFAULT_STORAGE="local-lvm"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_GATEWAY="192.168.1.1"
DEFAULT_DNS="8.8.8.8"
DEFAULT_SEARCH_DOMAIN="local.lan"
CI_DEFAULT_USER="debian"
LXC_DEFAULT_CPU=1
LXC_DEFAULT_RAM=512
LXC_DEFAULT_SWAP=512
LXC_DEFAULT_DISK=8
LXC_DEFAULT_UNPRIVILEGED=1
VMID_MIN=100
VMID_MAX=9999
CI_UPGRADE=1
BACKUP_STORAGE="local"

source "${TESTS_DIR}/../lib/common.sh"
source "${TESTS_DIR}/../lib/lifecycle.sh"
source "${TESTS_DIR}/../lib/deploy.sh"
source "${TESTS_DIR}/../lib/snapshot.sh"
source "${TESTS_DIR}/../lib/delete.sh"

# =============================================================================
describe "deploy_vm_from_template — validation"
# =============================================================================

mock_reset

# Sans --name et --template → die()
result=0
(deploy_vm_from_template --vmid 150) 2>/dev/null || result=$?
assert_eq "Manque --name et --template → die()" "1" "$result"

# VMID déjà utilisé → die()
result=0
(deploy_vm_from_template --vmid 100 --name test --template 9000) 2>/dev/null || result=$?
assert_eq "VMID existant → die()" "1" "$result"

# Template introuvable → die()
result=0
(deploy_vm_from_template --vmid 150 --name test --template 8888) 2>/dev/null || result=$?
assert_eq "Template inexistant → die()" "1" "$result"

# =============================================================================
describe "deploy_vm_from_template — déploiement réussi"
# =============================================================================

mock_reset
deploy_vm_from_template \
    --vmid 150 --name "new-vm" --template 9000 \
    --cpu 4 --ram 4096 --disk 40 \
    --ip "192.168.1.150/24" --gw "192.168.1.1" 2>/dev/null

assert_eq "qm clone appelé" "1" "$(mock_call_count qm_clone)"
assert_eq "VM 150 créée avec statut stopped" "stopped" "${_VM_STATUS[150]:-}"
assert_eq "VM 150 nommée new-vm" "new-vm" "${_VM_NAMES[150]:-}"

# =============================================================================
describe "deploy_vm_from_template — VMID auto"
# =============================================================================

mock_reset
# Avec VMIDs 100, 101, 9000 utilisés, le prochain = 102
deploy_vm_from_template \
    --name "auto-vmid-vm" --template 9000 \
    --cpu 1 --ram 512 --disk 5 2>/dev/null

assert_eq "VM créée avec VMID auto 102" "stopped" "${_VM_STATUS[102]:-}"
assert_eq "qm clone appelé pour VMID auto" "1" "$(mock_call_count qm_clone)"

# =============================================================================
describe "deploy_vm_from_iso — création VM vierge"
# =============================================================================

mock_reset
deploy_vm_from_iso \
    --vmid 160 --name "iso-vm" \
    --iso "local:iso/debian-12.iso" \
    --cpu 2 --ram 2048 --disk 20 2>/dev/null

assert_eq "qm create appelé" "1" "$(mock_call_count qm_create)"
assert_eq "VM 160 créée" "stopped" "${_VM_STATUS[160]:-}"

# VMID dupliqué → die()
mock_reset
result=0
(deploy_vm_from_iso --vmid 100 --name test --iso "local:iso/test.iso") 2>/dev/null || result=$?
assert_eq "VM ISO VMID dupliqué → die()" "1" "$result"

# =============================================================================
describe "deploy_lxc — création conteneur"
# =============================================================================

mock_reset
deploy_lxc \
    --vmid 250 --name "new-lxc" \
    --template "local:vztmpl/debian-12.tar.zst" \
    --cpu 1 --ram 1024 --disk 10 \
    --ip "192.168.1.250/24" --password "TestP4ss!" 2>/dev/null

assert_eq "pct create appelé" "1" "$(mock_call_count pct_create)"
assert_eq "LXC 250 créé" "stopped" "${_LXC_STATUS[250]:-}"
assert_eq "LXC 250 nommé new-lxc" "new-lxc" "${_LXC_NAMES[250]:-}"

# VMID dupliqué → die()
mock_reset
result=0
(deploy_lxc --vmid 200 --name test --template "local:vztmpl/test.tar.zst") 2>/dev/null || result=$?
assert_eq "LXC VMID dupliqué → die()" "1" "$result"

# =============================================================================
describe "snapshot_create — création"
# =============================================================================

mock_reset
snapshot_create --vmid 100 --name "snap-test" --desc "Test snapshot" 2>/dev/null
assert_eq "qm snapshot appelé" "1" "$(mock_call_count qm_snapshot)"
assert_contains "Snap ajouté dans _SNAPSHOTS[100]" "snap-test" "${_SNAPSHOTS[100]:-}"

# Snapshot sur LXC
mock_reset
snapshot_create --vmid 200 --name "lxc-snap" 2>/dev/null
assert_eq "pct snapshot appelé" "1" "$(mock_call_count pct_snapshot)"
assert_contains "Snap ajouté dans _SNAPSHOTS[200]" "lxc-snap" "${_SNAPSHOTS[200]:-}"

# Snapshot dupliqué → die()
mock_reset
result=0
(snapshot_create --vmid 100 --name "snap-initial") 2>/dev/null || result=$?
assert_eq "Snapshot dupliqué → die()" "1" "$result"

# Nom invalide (espaces) → die()
mock_reset
result=0
(snapshot_create --vmid 100 --name "snap avec espaces") 2>/dev/null || result=$?
assert_eq "Nom snapshot invalide → die()" "1" "$result"

# VMID inexistant → die()
result=0
(snapshot_create --vmid 9999 --name "snap") 2>/dev/null || result=$?
assert_eq "Snapshot VMID inexistant → die()" "1" "$result"

# =============================================================================
describe "snapshot_restore — restauration"
# =============================================================================

mock_reset
snapshot_restore --vmid 100 --name "snap-initial" 2>/dev/null
assert_eq "qm rollback appelé" "1" "$(mock_call_count qm_rollback)"
assert_eq "VM 100 en stopped après rollback" "stopped" "${_VM_STATUS[100]}"

# Snapshot inexistant → die()
result=0
(snapshot_restore --vmid 100 --name "nexiste-pas") 2>/dev/null || result=$?
assert_eq "Restore snapshot inexistant → die()" "1" "$result"

# Restore LXC
mock_reset
snapshot_restore --vmid 200 --name "snap-clean" 2>/dev/null
assert_eq "pct rollback appelé" "1" "$(mock_call_count pct_rollback)"

# =============================================================================
describe "snapshot_delete — suppression"
# =============================================================================

mock_reset
snapshot_delete --vmid 100 --name "snap-v1" 2>/dev/null
assert_eq "qm delsnapshot appelé" "1" "$(mock_call_count qm_delsnapshot)"
# snap-v1 doit avoir disparu de la liste
result=$(echo "${_SNAPSHOTS[100]:-}" | grep -c "snap-v1" || true)
assert_eq "snap-v1 retiré de _SNAPSHOTS[100]" "0" "$result"

# Suppr snapshot inexistant → die()
result=0
(snapshot_delete --vmid 100 --name "nexiste-pas") 2>/dev/null || result=$?
assert_eq "Delete snapshot inexistant → die()" "1" "$result"

# =============================================================================
describe "backup_create — sauvegarde vzdump"
# =============================================================================

mock_reset
backup_create --vmid 100 --storage "local" --mode "snapshot" 2>/dev/null
assert_eq "vzdump appelé" "1" "$(mock_call_count vzdump)"

backup_create --vmid 200 --mode "stop" 2>/dev/null
assert_eq "vzdump appelé pour LXC" "2" "$(mock_call_count vzdump)"

# VMID inexistant → die()
result=0
(backup_create --vmid 9999) 2>/dev/null || result=$?
assert_eq "Backup VMID inexistant → die()" "1" "$result"

# =============================================================================
describe "delete_machine — suppression VM"
# =============================================================================

mock_reset
# Simule un readname correct : la fonction demande à retaper le nom
# En mode CONFIRM_DESTRUCTIVE=0 + --force on contourne
delete_machine --vmid 101 --force 2>/dev/null
assert_eq "qm destroy appelé" "1" "$(mock_call_count qm_destroy)"
result=$(vmid_exists 101 2>/dev/null; echo $?)
assert_eq "VMID 101 supprimé" "1" "$result"

# Suppression LXC
mock_reset
delete_machine --vmid 201 --force 2>/dev/null
assert_eq "pct destroy appelé" "1" "$(mock_call_count pct_destroy)"
result=$(vmid_exists 201 2>/dev/null; echo $?)
assert_eq "VMID 201 (LXC) supprimé" "1" "$result"

# Suppression machine running → arrêt automatique puis destroy
mock_reset
delete_machine --vmid 100 --force 2>/dev/null
assert_eq "qm shutdown appelé avant destroy" "1" "$(mock_call_count qm_shutdown)"
assert_eq "qm destroy appelé" "1" "$(mock_call_count qm_destroy)"
result=$(vmid_exists 100 2>/dev/null; echo $?)
assert_eq "VMID 100 supprimé après arrêt auto" "1" "$result"

# Suppression avec snapshots → snapshots supprimés d'abord
mock_reset
delete_machine --vmid 100 --force 2>/dev/null
# delsnapshot appelé au moins 2 fois (snap-initial + snap-v1)
_ds_count=$(mock_call_count qm_delsnapshot)
(( _ds_count >= 2 )) && _ds_ok=0 || _ds_ok=1
assert_eq "delsnapshots appelés (≥2 pour snap-initial+snap-v1)" "0" "$_ds_ok"

# VMID inexistant → die()
mock_reset
result=0
(delete_machine --vmid 9999 --force) 2>/dev/null || result=$?
assert_eq "Delete VMID inexistant → die()" "1" "$result"

# =============================================================================
rm -f "$LOG_FILE"
test_summary
