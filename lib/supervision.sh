#!/usr/bin/env bash
# =============================================================================
# lib/supervision.sh — Supervision : liste, ressources, connectivité
# =============================================================================
# Fonctions :
#   supervision_list       — Lister toutes les VMs/LXC avec statut
#   supervision_resources  — Afficher l'utilisation CPU/RAM/disque
#   supervision_check      — Vérifier la connectivité (ping / SSH)
#   supervision_info       — Infos détaillées d'une machine

[[ -n "${_SUPERVISION_LOADED:-}" ]] && return 0
_SUPERVISION_LOADED=1

# =============================================================================
# LISTE TOUTES LES VMs ET LXC
# =============================================================================
# Usage : supervision_list [--type vm|lxc|all] [--status running|stopped|all]
#         [--node NODE]
# =============================================================================
supervision_list() {
    local filter_type="all"
    local filter_status="all"
    local node="${PVE_NODE:-pve}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)   filter_type="$2";   shift 2 ;;
            --status) filter_status="$2"; shift 2 ;;
            --node)   node="$2";          shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    log_section "Liste des machines — nœud : $node"

    # Largeur des colonnes
    local COL_ID=6 COL_TYPE=6 COL_NAME=25 COL_STATUS=10 COL_CPU=5 \
          COL_RAM=12 COL_DISK=10 COL_IP=18

    # En-tête
    printf "${C_BOLD}%-${COL_ID}s %-${COL_TYPE}s %-${COL_NAME}s %-${COL_STATUS}s %${COL_CPU}s %${COL_RAM}s %${COL_DISK}s %-${COL_IP}s${C_RESET}\n" \
        "VMID" "TYPE" "NOM" "STATUT" "CPU" "RAM" "DISQUE" "IP"
    log_separator "-" 100

    local count_vm=0 count_lxc=0 count_running=0

    # --- VMs QEMU ---
    if [[ "$filter_type" == "all" || "$filter_type" == "vm" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local vmid name status cpu ram maxmem maxdisk ip
            vmid=$(echo "$line"   | awk '{print $1}')
            name=$(echo "$line"   | awk '{print $2}')
            status=$(echo "$line" | awk '{print $3}')
            cpu=$(echo "$line"    | awk '{print $4}')
            ram=$(echo "$line"    | awk '{print $5}')     # mem utilisée (bytes)
            maxmem=$(echo "$line" | awk '{print $6}')     # mem max (bytes)
            maxdisk=$(echo "$line"| awk '{print $7}')     # disque max (bytes)

            [[ "$filter_status" != "all" && "$status" != "$filter_status" ]] && continue

            # Formatage mémoire
            local ram_str="" maxmem_str=""
            if [[ "$status" == "running" && -n "$ram" && "$ram" -gt 0 ]]; then
                ram_str="$(( ram / 1024 / 1024 )) Mo"
                maxmem_str="$(( maxmem / 1024 / 1024 )) Mo"
                ram_str="${ram_str}/${maxmem_str}"
            else
                maxmem_str="$(( maxmem / 1024 / 1024 )) Mo"
                ram_str="-/${maxmem_str}"
            fi

            # Formatage disque
            local disk_str="$(( maxdisk / 1024 / 1024 / 1024 ))G"

            # CPU
            local cpu_str
            if [[ "$status" == "running" ]]; then
                cpu_str=$(printf "%.0f%%" "$(echo "$cpu * 100" | bc 2>/dev/null || echo 0)")
            else
                cpu_str="-"
            fi

            # IP (depuis config cloud-init ou agent)
            ip=$(_get_vm_ip "$vmid" 2>/dev/null || echo "-")

            # Couleur du statut
            local status_col
            case "$status" in
                running)   status_col="${C_BGREEN}${status}${C_RESET}" ; (( count_running++ )) ;;
                stopped)   status_col="${C_RED}${status}${C_RESET}" ;;
                suspended) status_col="${C_YELLOW}${status}${C_RESET}" ;;
                *)         status_col="${status}" ;;
            esac

            printf "%-${COL_ID}s ${C_CYAN}%-${COL_TYPE}s${C_RESET} %-${COL_NAME}s %-$((COL_STATUS+10))b %${COL_CPU}s %${COL_RAM}s %${COL_DISK}s %-${COL_IP}s\n" \
                "$vmid" "VM" "$name" "$status_col" "$cpu_str" "$ram_str" "$disk_str" "$ip"
            (( count_vm++ ))
        done < <(qm list 2>/dev/null | tail -n +2)
    fi

    # --- Conteneurs LXC ---
    if [[ "$filter_type" == "all" || "$filter_type" == "lxc" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local vmid name status cpu ram maxmem maxdisk ip
            vmid=$(echo "$line"   | awk '{print $1}')
            name=$(echo "$line"   | awk '{print $2}')
            status=$(echo "$line" | awk '{print $3}')
            cpu=$(echo "$line"    | awk '{print $4}')
            ram=$(echo "$line"    | awk '{print $5}')
            maxmem=$(echo "$line" | awk '{print $6}')
            maxdisk=$(echo "$line"| awk '{print $7}')

            [[ "$filter_status" != "all" && "$status" != "$filter_status" ]] && continue

            local ram_str disk_str cpu_str ip
            if [[ "$status" == "running" && -n "$ram" && "$ram" -gt 0 ]]; then
                ram_str="$(( ram / 1024 / 1024 )) Mo/$(( maxmem / 1024 / 1024 )) Mo"
            else
                ram_str="-/$(( maxmem / 1024 / 1024 )) Mo"
            fi
            disk_str="$(( maxdisk / 1024 / 1024 / 1024 ))G"
            if [[ "$status" == "running" ]]; then
                cpu_str=$(printf "%.0f%%" "$(echo "$cpu * 100" | bc 2>/dev/null || echo 0)")
            else
                cpu_str="-"
            fi
            ip=$(_get_lxc_ip "$vmid" 2>/dev/null || echo "-")

            local status_col
            case "$status" in
                running) status_col="${C_BGREEN}${status}${C_RESET}"; (( count_running++ )) ;;
                stopped) status_col="${C_RED}${status}${C_RESET}" ;;
                *)       status_col="${status}" ;;
            esac

            printf "%-${COL_ID}s ${C_MAGENTA}%-${COL_TYPE}s${C_RESET} %-${COL_NAME}s %-$((COL_STATUS+10))b %${COL_CPU}s %${COL_RAM}s %${COL_DISK}s %-${COL_IP}s\n" \
                "$vmid" "LXC" "$name" "$status_col" "$cpu_str" "$ram_str" "$disk_str" "$ip"
            (( count_lxc++ ))
        done < <(pct list 2>/dev/null | tail -n +2)
    fi

    log_separator "-" 100
    echo -e "  ${C_BOLD}Total :${C_RESET} $count_vm VM(s), $count_lxc LXC(s) — ${C_BGREEN}$count_running en cours d'exécution${C_RESET}"
    echo ""
}

# =============================================================================
# RESSOURCES DÉTAILLÉES D'UNE MACHINE
# =============================================================================
# Usage : supervision_resources --vmid VMID
# =============================================================================
supervision_resources() {
    local vmid=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid) vmid="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid" ]] && die "Option --vmid requise."
    vmid_exists "$vmid" || die "VMID $vmid introuvable."

    local type name status
    type=$(vmid_type "$vmid")
    name=$(vmid_name "$vmid")
    status=$(vmid_status "$vmid")

    log_section "Ressources — VMID $vmid ($name)"

    echo -e "  ${C_BOLD}Type    :${C_RESET} ${type^^}"
    echo -e "  ${C_BOLD}Statut  :${C_RESET} $(_colorize_status "$status")"
    echo ""

    case "$type" in
        qemu)
            # Configuration
            echo -e "${C_BOLD}  ── Configuration ──────────────────────────${C_RESET}"
            local config
            config=$(qm config "$vmid" 2>/dev/null)
            echo "$config" | grep -E '^(cores|sockets|memory|name|bios|machine|ostype|net|scsi|ide|virtio|sata|tags)' \
                | while IFS=: read -r key val; do
                    printf "  %-15s: %s\n" "$key" "$(echo "$val" | sed 's/^ //')"
                done

            # Ressources temps réel si running
            if [[ "$status" == "running" ]]; then
                echo ""
                echo -e "${C_BOLD}  ── Métriques temps réel ────────────────────${C_RESET}"
                local stats
                stats=$(pvesh get /nodes/"${PVE_NODE}"/qemu/"$vmid"/status/current \
                    --output-format json 2>/dev/null)
                if [[ -n "$stats" ]]; then
                    local cpu_pct mem_bytes maxmem_bytes disk_read disk_write net_in net_out
                    cpu_pct=$(echo "$stats"       | grep -o '"cpu":[0-9.]*'       | cut -d: -f2)
                    mem_bytes=$(echo "$stats"     | grep -o '"mem":[0-9]*'        | cut -d: -f2)
                    maxmem_bytes=$(echo "$stats"  | grep -o '"maxmem":[0-9]*'     | cut -d: -f2)
                    disk_read=$(echo "$stats"     | grep -o '"diskread":[0-9]*'   | cut -d: -f2)
                    disk_write=$(echo "$stats"    | grep -o '"diskwrite":[0-9]*'  | cut -d: -f2)
                    net_in=$(echo "$stats"        | grep -o '"netin":[0-9]*'      | cut -d: -f2)
                    net_out=$(echo "$stats"       | grep -o '"netout":[0-9]*'     | cut -d: -f2)

                    local cpu_display=""
                    [[ -n "$cpu_pct" ]] && cpu_display=$(printf "%.1f%%" "$(echo "$cpu_pct * 100" | bc)")

                    local mem_display=""
                    if [[ -n "$mem_bytes" && -n "$maxmem_bytes" && "$maxmem_bytes" -gt 0 ]]; then
                        local mem_mo=$(( mem_bytes / 1024 / 1024 ))
                        local max_mo=$(( maxmem_bytes / 1024 / 1024 ))
                        local pct=$(( mem_mo * 100 / max_mo ))
                        mem_display="${mem_mo} Mo / ${max_mo} Mo (${pct}%)"
                        mem_display+=" $(_usage_bar "$pct")"
                    fi

                    printf "  %-15s: %s\n" "CPU utilisé"   "${cpu_display:--}"
                    printf "  %-15s: %s\n" "RAM utilisée"  "${mem_display:--}"
                    [[ -n "$disk_read"  ]] && printf "  %-15s: %s Mo lus\n"   "Disque I/O read"  "$(( disk_read  / 1024 / 1024 ))"
                    [[ -n "$disk_write" ]] && printf "  %-15s: %s Mo écrits\n" "Disque I/O write" "$(( disk_write / 1024 / 1024 ))"
                    [[ -n "$net_in"     ]] && printf "  %-15s: ↓ %s Ko\n"     "Réseau"          "$(( net_in / 1024 ))"
                    [[ -n "$net_out"    ]] && printf "  %-15s: ↑ %s Ko\n"     ""               "$(( net_out / 1024 ))"
                fi
            fi
            ;;

        lxc)
            echo -e "${C_BOLD}  ── Configuration ──────────────────────────${C_RESET}"
            pct config "$vmid" 2>/dev/null \
                | grep -E '^(cores|memory|swap|hostname|rootfs|net|unprivileged|features|tags)' \
                | while IFS=: read -r key val; do
                    printf "  %-15s: %s\n" "$key" "$(echo "$val" | sed 's/^ //')"
                done

            if [[ "$status" == "running" ]]; then
                echo ""
                echo -e "${C_BOLD}  ── Métriques temps réel ────────────────────${C_RESET}"
                local stats
                stats=$(pvesh get /nodes/"${PVE_NODE}"/lxc/"$vmid"/status/current \
                    --output-format json 2>/dev/null)
                if [[ -n "$stats" ]]; then
                    local cpu_pct mem_bytes maxmem_bytes
                    cpu_pct=$(echo "$stats"      | grep -o '"cpu":[0-9.]*'   | cut -d: -f2)
                    mem_bytes=$(echo "$stats"    | grep -o '"mem":[0-9]*'    | cut -d: -f2)
                    maxmem_bytes=$(echo "$stats" | grep -o '"maxmem":[0-9]*' | cut -d: -f2)
                    local cpu_display mem_display
                    [[ -n "$cpu_pct" ]] && cpu_display=$(printf "%.1f%%" "$(echo "$cpu_pct * 100" | bc)")
                    if [[ -n "$mem_bytes" && -n "$maxmem_bytes" && "$maxmem_bytes" -gt 0 ]]; then
                        local mem_mo=$(( mem_bytes / 1024 / 1024 ))
                        local max_mo=$(( maxmem_bytes / 1024 / 1024 ))
                        local pct=$(( mem_mo * 100 / max_mo ))
                        mem_display="${mem_mo} Mo / ${max_mo} Mo (${pct}%) $(_usage_bar "$pct")"
                    fi
                    printf "  %-15s: %s\n" "CPU utilisé"  "${cpu_display:--}"
                    printf "  %-15s: %s\n" "RAM utilisée" "${mem_display:--}"
                fi
            fi
            ;;
    esac
    echo ""
}

# =============================================================================
# VÉRIFICATION CONNECTIVITÉ (PING + SSH)
# =============================================================================
# Usage : supervision_check --vmid VMID [--ip IP] [--user USER]
# =============================================================================
supervision_check() {
    local vmid="" ip="" user="root" ssh_port=22

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid) vmid="$2"; shift 2 ;;
            --ip)   ip="$2";   shift 2 ;;
            --user) user="$2"; shift 2 ;;
            --port) ssh_port="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid" ]] && die "Option --vmid requise."
    vmid_exists "$vmid" || die "VMID $vmid introuvable."

    local name type status
    name=$(vmid_name "$vmid")
    type=$(vmid_type "$vmid")
    status=$(vmid_status "$vmid")

    log_section "Vérification connectivité — VMID $vmid ($name)"
    echo -e "  Statut machine : $(_colorize_status "$status")"

    if [[ "$status" != "running" ]]; then
        log_warn "La machine n'est pas en cours d'exécution. Vérification ignorée."
        return 1
    fi

    # Auto-détection IP si non fournie
    if [[ -z "$ip" ]]; then
        case "$type" in
            qemu) ip=$(_get_vm_ip "$vmid")  ;;
            lxc)  ip=$(_get_lxc_ip "$vmid") ;;
        esac
        if [[ -z "$ip" || "$ip" == "-" ]]; then
            log_warn "Impossible de détecter l'IP automatiquement. Utilisez --ip."
            return 1
        fi
        log_info "IP détectée automatiquement : $ip"
    fi

    echo ""

    # --- Test PING ---
    echo -en "  ${C_BOLD}Ping${C_RESET} ($ip)... "
    if ping -c 3 -W 2 "$ip" &>/dev/null; then
        local rtt
        rtt=$(ping -c 3 -W 2 "$ip" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        echo -e "${C_BGREEN}✔ Répond${C_RESET} (RTT moy: ${rtt:-?} ms)"
    else
        echo -e "${C_BRED}✘ Aucune réponse${C_RESET}"
    fi

    # --- Test SSH ---
    echo -en "  ${C_BOLD}SSH${C_RESET}  ($user@$ip:$ssh_port)... "
    if command -v ssh &>/dev/null; then
        local ssh_result
        if ssh -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no \
               -o BatchMode=yes \
               -o LogLevel=ERROR \
               -p "$ssh_port" \
               "${user}@${ip}" \
               "echo proxmox_admin_check_ok" 2>/dev/null | grep -q "proxmox_admin_check_ok"; then
            echo -e "${C_BGREEN}✔ SSH accessible${C_RESET}"
        else
            # Test port TCP uniquement (sans auth)
            if timeout 5 bash -c ">/dev/tcp/$ip/$ssh_port" 2>/dev/null; then
                echo -e "${C_YELLOW}⚠ Port ouvert mais authentification refusée${C_RESET}"
            else
                echo -e "${C_BRED}✘ Port $ssh_port fermé ou inaccessible${C_RESET}"
            fi
        fi
    else
        echo -e "${C_DIM}(commande ssh non disponible)${C_RESET}"
    fi

    # --- Test port HTTP/HTTPS optionnel ---
    for port in 80 443; do
        echo -en "  ${C_BOLD}Port $port${C_RESET} ($ip)... "
        if timeout 3 bash -c ">/dev/tcp/$ip/$port" 2>/dev/null; then
            echo -e "${C_BGREEN}✔ Ouvert${C_RESET}"
        else
            echo -e "${C_DIM}✘ Fermé${C_RESET}"
        fi
    done
    echo ""
}

# =============================================================================
# INFORMATIONS COMPLÈTES D'UNE MACHINE
# =============================================================================
supervision_info() {
    local vmid=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid) vmid="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done
    [[ -z "$vmid" ]] && die "Option --vmid requise."

    supervision_resources --vmid "$vmid"
    supervision_check     --vmid "$vmid"
}

# =============================================================================
# HELPERS PRIVÉS
# =============================================================================

# Retourne une barre ASCII de charge
_usage_bar() {
    local pct="$1"
    local width=20
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local color
    (( pct < 60 )) && color="$C_BGREEN"
    (( pct >= 60 && pct < 85 )) && color="$C_BYELLOW"
    (( pct >= 85 )) && color="$C_BRED"
    printf "%b[%s%s]%b" "$color" \
        "$(printf '█%.0s' $(seq 1 "$filled"))" \
        "$(printf '░%.0s' $(seq 1 "$empty"))" \
        "$C_RESET"
}

# Colorise un statut
_colorize_status() {
    case "$1" in
        running)   echo -e "${C_BGREEN}running${C_RESET}" ;;
        stopped)   echo -e "${C_RED}stopped${C_RESET}" ;;
        suspended) echo -e "${C_YELLOW}suspended${C_RESET}" ;;
        *)         echo -e "${C_DIM}${1:-unknown}${C_RESET}" ;;
    esac
}

# Récupère l'IP d'une VM QEMU (via agent ou config cloud-init)
_get_vm_ip() {
    local vmid="$1"
    local ip=""

    # Méthode 1 : QEMU guest agent
    ip=$(pvesh get /nodes/"${PVE_NODE}"/qemu/"$vmid"/agent/network-get-interfaces \
        --output-format json 2>/dev/null \
        | grep -o '"ip-address":"[^"]*"' \
        | grep -v '127.0.0.1\|::1\|fe80' \
        | head -1 \
        | cut -d'"' -f4)

    # Méthode 2 : config cloud-init
    if [[ -z "$ip" ]]; then
        ip=$(qm config "$vmid" 2>/dev/null \
            | grep '^ipconfig0:' \
            | grep -o 'ip=[0-9.]*' \
            | cut -d= -f2)
    fi

    echo "${ip:--}"
}

# Récupère l'IP d'un LXC
_get_lxc_ip() {
    local vmid="$1"
    local ip=""

    # Méthode 1 : interface réseau LXC
    ip=$(pct exec "$vmid" -- hostname -I 2>/dev/null \
        | tr ' ' '\n' \
        | grep -v '127.0.0.1\|::1\|fe80' \
        | head -1)

    # Méthode 2 : depuis la config réseau
    if [[ -z "$ip" ]]; then
        ip=$(pct config "$vmid" 2>/dev/null \
            | grep '^net0:' \
            | grep -o 'ip=[0-9.]*' \
            | cut -d= -f2)
    fi

    echo "${ip:--}"
}
