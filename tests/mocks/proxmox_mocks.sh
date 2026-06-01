#!/usr/bin/env bash
# =============================================================================
# tests/mocks/proxmox_mocks.sh — Simulation des commandes Proxmox
# =============================================================================
# Surcharge qm, pct, pvesh, vzdump, ping avec des implémentations de test.
# Charge ce fichier AVANT les modules à tester.
#
# État simulé :
#   VMID 100 : VM "web-prod" — running
#   VMID 101 : VM "db-server" — stopped
#   VMID 200 : LXC "monitoring" — running
#   VMID 201 : LXC "cache-redis" — stopped
#   VMID 9000: VM "template-debian" — stopped (template)
#
# Snapshots existants :
#   VMID 100 : snap-initial, snap-v1
#   VMID 200 : snap-clean

# --- État global des machines (modifiable par les tests) ---
declare -A _VM_STATUS=(
    [100]="running"
    [101]="stopped"
    [9000]="stopped"
)
declare -A _VM_NAMES=(
    [100]="web-prod"
    [101]="db-server"
    [9000]="template-debian"
)
declare -A _LXC_STATUS=(
    [200]="running"
    [201]="stopped"
)
declare -A _LXC_NAMES=(
    [200]="monitoring"
    [201]="cache-redis"
)
declare -A _SNAPSHOTS=(
    [100]="snap-initial snap-v1"
    [200]="snap-clean"
)

# Compteurs d'appels (pour vérifier qu'une commande a bien été appelée)
declare -A _MOCK_CALL_COUNT=(
    [qm_start]=0 [qm_stop]=0 [qm_shutdown]=0 [qm_reboot]=0
    [qm_suspend]=0 [qm_resume]=0 [qm_clone]=0 [qm_create]=0
    [qm_destroy]=0 [qm_snapshot]=0 [qm_rollback]=0 [qm_delsnapshot]=0
    [pct_start]=0 [pct_stop]=0 [pct_shutdown]=0 [pct_create]=0
    [pct_destroy]=0 [pct_snapshot]=0 [pct_rollback]=0 [pct_delsnapshot]=0
    [vzdump]=0
)

# Journal des appels mock
_MOCK_LOG=()
_mock_log() { _MOCK_LOG+=("$*"); }

# Récupère le nombre d'appels d'une commande mock
mock_call_count() { echo "${_MOCK_CALL_COUNT[$1]:-0}"; }

# Reset l'état mock pour un test propre
mock_reset() {
    _VM_STATUS=([100]="running" [101]="stopped" [9000]="stopped")
    _VM_NAMES=([100]="web-prod" [101]="db-server" [9000]="template-debian")
    _LXC_STATUS=([200]="running" [201]="stopped")
    _LXC_NAMES=([200]="monitoring" [201]="cache-redis")
    _SNAPSHOTS=([100]="snap-initial snap-v1" [200]="snap-clean")
    _MOCK_CALL_COUNT=(
        [qm_start]=0 [qm_stop]=0 [qm_shutdown]=0 [qm_reboot]=0
        [qm_suspend]=0 [qm_resume]=0 [qm_clone]=0 [qm_create]=0
        [qm_destroy]=0 [qm_snapshot]=0 [qm_rollback]=0 [qm_delsnapshot]=0
        [pct_start]=0 [pct_stop]=0 [pct_shutdown]=0 [pct_create]=0
        [pct_destroy]=0 [pct_snapshot]=0 [pct_rollback]=0 [pct_delsnapshot]=0
        [vzdump]=0
    )
    _MOCK_LOG=()
}

# =============================================================================
# MOCK : qm
# =============================================================================
qm() {
    local subcmd="$1"
    local vmid="${2:-}"
    _mock_log "qm $*"

    case "$subcmd" in
        # --- status ---
        status)
            if [[ -n "${_VM_STATUS[$vmid]:-}" ]]; then
                echo "status: ${_VM_STATUS[$vmid]}"
                return 0
            fi
            echo "Configuration file 'nodes/pve/qemu-server/${vmid}.conf' does not exist" >&2
            return 1
            ;;

        # --- list ---
        list)
            echo "      VMID NAME                 STATUS     MEM(MB)    BOOTDISK(GB) PID"
            for id in "${!_VM_NAMES[@]}"; do
                local s="${_VM_STATUS[$id]:-stopped}"
                local pid=0; [[ "$s" == "running" ]] && pid=12345
                printf "%10d %-20s %-10s %10d %12d %d\n" \
                    "$id" "${_VM_NAMES[$id]}" "$s" 2048 20 "$pid"
            done
            ;;

        # --- config ---
        config)
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && return 1
            cat <<EOF
name: ${_VM_NAMES[$vmid]:-vm-$vmid}
cores: 2
memory: 2048
scsi0: local-lvm:vm-${vmid}-disk-0,size=20G
net0: virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0
ipconfig0: ip=192.168.1.${vmid}/24,gw=192.168.1.1
ciuser: debian
ostype: l26
bios: seabios
machine: q35
EOF
            ;;

        # --- start ---
        start)
            (( _MOCK_CALL_COUNT[qm_start]++ ))
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && { echo "VM $vmid not found" >&2; return 1; }
            _VM_STATUS[$vmid]="running"
            return 0
            ;;

        # --- stop ---
        stop)
            (( _MOCK_CALL_COUNT[qm_stop]++ ))
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && return 1
            _VM_STATUS[$vmid]="stopped"
            return 0
            ;;

        # --- shutdown ---
        shutdown)
            (( _MOCK_CALL_COUNT[qm_shutdown]++ ))
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && return 1
            _VM_STATUS[$vmid]="stopped"
            return 0
            ;;

        # --- reboot ---
        reboot)
            (( _MOCK_CALL_COUNT[qm_reboot]++ ))
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && return 1
            return 0
            ;;

        # --- suspend ---
        suspend)
            (( _MOCK_CALL_COUNT[qm_suspend]++ ))
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && return 1
            _VM_STATUS[$vmid]="suspended"
            return 0
            ;;

        # --- resume ---
        resume)
            (( _MOCK_CALL_COUNT[qm_resume]++ ))
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && return 1
            _VM_STATUS[$vmid]="running"
            return 0
            ;;

        # --- reset ---
        reset)
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && return 1
            return 0
            ;;

        # --- clone ---
        clone)
            (( _MOCK_CALL_COUNT[qm_clone]++ ))
            local src="$vmid"
            local dst="$3"
            [[ -z "${_VM_STATUS[$src]:-}" ]] && { echo "source $src not found" >&2; return 1; }
            # Récupère le --name
            local new_name="vm-$dst"
            local i=4
            while [[ $i -le $# ]]; do
                if [[ "${!i}" == "--name" ]]; then
                    (( i++ ))
                    new_name="${!i}"
                fi
                (( i++ ))
            done
            _VM_STATUS[$dst]="stopped"
            _VM_NAMES[$dst]="$new_name"
            return 0
            ;;

        # --- create ---
        create)
            (( _MOCK_CALL_COUNT[qm_create]++ ))
            _VM_STATUS[$vmid]="stopped"
            _VM_NAMES[$vmid]="vm-$vmid"
            return 0
            ;;

        # --- set ---
        set)
            return 0
            ;;

        # --- resize ---
        resize)
            return 0
            ;;

        # --- destroy ---
        destroy)
            (( _MOCK_CALL_COUNT[qm_destroy]++ ))
            [[ -z "${_VM_STATUS[$vmid]:-}" ]] && return 1
            unset "_VM_STATUS[$vmid]"
            unset "_VM_NAMES[$vmid]"
            unset "_SNAPSHOTS[$vmid]"
            return 0
            ;;

        # --- snapshot ---
        snapshot)
            (( _MOCK_CALL_COUNT[qm_snapshot]++ ))
            local snapname="$3"
            # Vérifie unicité
            if echo "${_SNAPSHOTS[$vmid]:-}" | grep -qw "$snapname"; then
                echo "Snapshot '$snapname' already exists" >&2; return 1
            fi
            _SNAPSHOTS[$vmid]="${_SNAPSHOTS[$vmid]:-} $snapname"
            return 0
            ;;

        # --- listsnapshot ---
        listsnapshot)
            echo "current (current)"
            for snap in ${_SNAPSHOTS[$vmid]:-}; do
                [[ -z "$snap" ]] && continue
                echo "   -> $snap  2024-01-15 10:00:00  Test snapshot"
            done
            ;;

        # --- delsnapshot ---
        delsnapshot)
            (( _MOCK_CALL_COUNT[qm_delsnapshot]++ ))
            local snapname="$3"
            local snaps="${_SNAPSHOTS[$vmid]:-}"
            snaps=$(echo "$snaps" | tr ' ' '\n' | grep -v "^${snapname}$" | tr '\n' ' ')
            _SNAPSHOTS[$vmid]="$snaps"
            return 0
            ;;

        # --- rollback ---
        rollback)
            (( _MOCK_CALL_COUNT[qm_rollback]++ ))
            local snapname="$3"
            if ! echo "${_SNAPSHOTS[$vmid]:-}" | grep -qw "$snapname"; then
                echo "Snapshot '$snapname' not found" >&2; return 1
            fi
            _VM_STATUS[$vmid]="stopped"
            return 0
            ;;

        *)
            echo "qm: unknown subcommand '$subcmd'" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# MOCK : pct
# =============================================================================
pct() {
    local subcmd="$1"
    local vmid="${2:-}"
    _mock_log "pct $*"

    case "$subcmd" in
        status)
            if [[ -n "${_LXC_STATUS[$vmid]:-}" ]]; then
                echo "status: ${_LXC_STATUS[$vmid]}"
                return 0
            fi
            echo "Configuration file 'nodes/pve/lxc/${vmid}.conf' does not exist" >&2
            return 1
            ;;

        list)
            echo "VMID       Status     Lock         Name"
            for id in "${!_LXC_NAMES[@]}"; do
                printf "%-10d %-10s %-12s %s\n" \
                    "$id" "${_LXC_STATUS[$id]:-stopped}" "" "${_LXC_NAMES[$id]}"
            done
            ;;

        config)
            [[ -z "${_LXC_STATUS[$vmid]:-}" ]] && return 1
            cat <<EOF
hostname: ${_LXC_NAMES[$vmid]:-lxc-$vmid}
cores: 1
memory: 512
swap: 512
rootfs: local-lvm:vm-${vmid}-disk-0,size=8G
net0: name=eth0,bridge=vmbr0,ip=192.168.1.${vmid}/24,gw=192.168.1.1
unprivileged: 1
EOF
            ;;

        start)
            (( _MOCK_CALL_COUNT[pct_start]++ ))
            [[ -z "${_LXC_STATUS[$vmid]:-}" ]] && return 1
            _LXC_STATUS[$vmid]="running"
            return 0
            ;;

        stop)
            (( _MOCK_CALL_COUNT[pct_stop]++ ))
            [[ -z "${_LXC_STATUS[$vmid]:-}" ]] && return 1
            _LXC_STATUS[$vmid]="stopped"
            return 0
            ;;

        shutdown)
            (( _MOCK_CALL_COUNT[pct_shutdown]++ ))
            [[ -z "${_LXC_STATUS[$vmid]:-}" ]] && return 1
            _LXC_STATUS[$vmid]="stopped"
            return 0
            ;;

        reboot)
            [[ -z "${_LXC_STATUS[$vmid]:-}" ]] && return 1
            return 0
            ;;

        create)
            (( _MOCK_CALL_COUNT[pct_create]++ ))
            # Récupère --hostname
            local new_name="lxc-$vmid"
            local i=3
            while [[ $i -le $# ]]; do
                if [[ "${!i}" == "--hostname" ]]; then
                    (( i++ ))
                    new_name="${!i}"
                fi
                (( i++ ))
            done
            _LXC_STATUS[$vmid]="stopped"
            _LXC_NAMES[$vmid]="$new_name"
            return 0
            ;;

        set)
            return 0
            ;;

        exec)
            # Simule hostname -I
            if echo "$*" | grep -q "hostname -I"; then
                echo "192.168.1.$vmid"
            fi
            return 0
            ;;

        destroy)
            (( _MOCK_CALL_COUNT[pct_destroy]++ ))
            [[ -z "${_LXC_STATUS[$vmid]:-}" ]] && return 1
            unset "_LXC_STATUS[$vmid]"
            unset "_LXC_NAMES[$vmid]"
            unset "_SNAPSHOTS[$vmid]"
            return 0
            ;;

        snapshot)
            (( _MOCK_CALL_COUNT[pct_snapshot]++ ))
            local snapname="$3"
            if echo "${_SNAPSHOTS[$vmid]:-}" | grep -qw "$snapname"; then
                return 1
            fi
            _SNAPSHOTS[$vmid]="${_SNAPSHOTS[$vmid]:-} $snapname"
            return 0
            ;;

        listsnapshot)
            echo "current (current)"
            for snap in ${_SNAPSHOTS[$vmid]:-}; do
                [[ -z "$snap" ]] && continue
                echo "   -> $snap  2024-01-15 10:00:00  Test snapshot"
            done
            ;;

        delsnapshot)
            (( _MOCK_CALL_COUNT[pct_delsnapshot]++ ))
            local snapname="$3"
            local snaps="${_SNAPSHOTS[$vmid]:-}"
            snaps=$(echo "$snaps" | tr ' ' '\n' | grep -v "^${snapname}$" | tr '\n' ' ')
            _SNAPSHOTS[$vmid]="$snaps"
            return 0
            ;;

        rollback)
            (( _MOCK_CALL_COUNT[pct_rollback]++ ))
            local snapname="$3"
            if ! echo "${_SNAPSHOTS[$vmid]:-}" | grep -qw "$snapname"; then
                return 1
            fi
            _LXC_STATUS[$vmid]="stopped"
            return 0
            ;;

        *)
            echo "pct: unknown subcommand '$subcmd'" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# MOCK : pvesh
# =============================================================================
pvesh() {
    local method="$1" path="$2"
    _mock_log "pvesh $*"

    case "$path" in
        */qemu)
            echo '[{"vmid":100},{"vmid":101},{"vmid":9000}]'
            ;;
        */lxc)
            echo '[{"vmid":200},{"vmid":201}]'
            ;;
        */qemu/*/status/current)
            local id
            id=$(echo "$path" | grep -oE '[0-9]+' | head -1)
            local s="${_VM_STATUS[$id]:-stopped}"
            local mem=0; [[ "$s" == "running" ]] && mem=536870912
            echo "{\"status\":\"$s\",\"cpu\":0.05,\"mem\":$mem,\"maxmem\":2147483648,\"maxdisk\":21474836480,\"diskread\":1048576,\"diskwrite\":524288,\"netin\":65536,\"netout\":32768}"
            ;;
        */lxc/*/status/current)
            local id
            id=$(echo "$path" | grep -oE '[0-9]+' | head -1)
            local s="${_LXC_STATUS[$id]:-stopped}"
            local mem=0; [[ "$s" == "running" ]] && mem=134217728
            echo "{\"status\":\"$s\",\"cpu\":0.02,\"mem\":$mem,\"maxmem\":536870912}"
            ;;
        */agent/network-get-interfaces)
            echo '[{"name":"eth0","ip-addresses":[{"ip-address":"192.168.1.100","ip-address-type":"ipv4"}]}]'
            ;;
        */storage/*/content)
            echo '[{"volid":"local:backup/vzdump-qemu-100-2024_01_15-10_00_00.vma.zst"},{"volid":"local:backup/vzdump-lxc-200-2024_01_15-11_00_00.tar.zst"}]'
            ;;
        *)
            echo '{}' ;;
    esac
    return 0
}

# =============================================================================
# MOCK : vzdump
# =============================================================================
vzdump() {
    (( _MOCK_CALL_COUNT[vzdump]++ ))
    _mock_log "vzdump $*"
    local vmid="${1:-}"
    echo "INFO: starting new backup job: vzdump $*"
    echo "INFO: Finished Backup of VM $vmid (00:00:05)"
    return 0
}

# =============================================================================
# MOCK : ping (si absent)
# =============================================================================
if ! command -v ping &>/dev/null; then
    ping() {
        _mock_log "ping $*"
        # Simule succès pour IPs connues
        local ip=""
        for arg in "$@"; do
            if [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ip="$arg"
            fi
        done
        case "${ip:-}" in
            192.168.1.100|192.168.1.200) return 0 ;;
            *) return 1 ;;
        esac
    }
fi
