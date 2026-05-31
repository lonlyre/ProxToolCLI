#!/usr/bin/env bash
# =============================================================================
# lib/snapshot.sh — Gestion des snapshots et sauvegardes
# =============================================================================
# Fonctions :
#   snapshot_create   — Créer un snapshot
#   snapshot_list     — Lister les snapshots d'une machine
#   snapshot_restore  — Restaurer depuis un snapshot
#   snapshot_delete   — Supprimer un snapshot
#   backup_create     — Créer une sauvegarde vzdump
#   backup_list       — Lister les sauvegardes disponibles

[[ -n "${_SNAPSHOT_LOADED:-}" ]] && return 0
_SNAPSHOT_LOADED=1

# =============================================================================
# CRÉER UN SNAPSHOT
# =============================================================================
# Usage : snapshot_create --vmid VMID --name NOM [--desc DESCRIPTION]
#                         [--with-memory 1|0]
# =============================================================================
snapshot_create() {
    local vmid="" snapname="" desc="" with_memory=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid)        vmid="$2";        shift 2 ;;
            --name)        snapname="$2";    shift 2 ;;
            --desc)        desc="$2";        shift 2 ;;
            --with-memory) with_memory="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid"     ]] && die "Option --vmid requise."
    [[ -z "$snapname" ]] && snapname=$(prompt_value "Nom du snapshot" \
        "snap_$(date '+%Y%m%d_%H%M%S')")
    [[ -z "$snapname" ]] && die "Nom du snapshot obligatoire."

    vmid_exists "$vmid" || die "VMID $vmid introuvable."
    local type name status
    type=$(vmid_type "$vmid")
    name=$(vmid_name "$vmid")
    status=$(vmid_status "$vmid")

    # Validation : nom du snapshot (alphanumérique + tirets/underscores uniquement)
    if ! [[ "$snapname" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        die "Nom de snapshot invalide : '$snapname'. Utilisez uniquement [a-zA-Z0-9_-]."
    fi

    log_section "Création snapshot — VMID $vmid ($name)"
    echo -e "  ${C_BOLD}Snapshot  :${C_RESET} $snapname"
    echo -e "  ${C_BOLD}Type      :${C_RESET} ${type^^}"
    echo -e "  ${C_BOLD}Statut    :${C_RESET} $status"
    [[ -n "$desc" ]] && echo -e "  ${C_BOLD}Desc      :${C_RESET} $desc"
    echo ""

    # Avertissement snapshot avec mémoire sur VM running
    if [[ "$type" == "qemu" && "$status" == "running" && "$with_memory" == "1" ]]; then
        log_warn "Snapshot avec sauvegarde de la RAM (plus lent mais état complet)."
    fi

    # Vérification unicité du nom
    if _snapshot_exists "$vmid" "$type" "$snapname"; then
        die "Un snapshot '$snapname' existe déjà pour VMID $vmid."
    fi

    log_info "Création du snapshot '$snapname'..."
    local snap_args=()

    case "$type" in
        qemu)
            snap_args=(qm snapshot "$vmid" "$snapname")
            [[ -n "$desc" ]] && snap_args+=(--description "$desc")
            [[ "$with_memory" == "1" ]] && snap_args+=(--vmstate 1)
            ;;
        lxc)
            snap_args=(pct snapshot "$vmid" "$snapname")
            [[ -n "$desc" ]] && snap_args+=(--description "$desc")
            ;;
    esac

    if ! "${snap_args[@]}"; then
        die "Échec de la création du snapshot '$snapname' pour VMID $vmid."
    fi

    log_success "Snapshot '$snapname' créé avec succès pour VMID $vmid ($name)."

    # Affiche la liste mise à jour
    echo ""
    snapshot_list --vmid "$vmid"
}

# =============================================================================
# LISTER LES SNAPSHOTS
# =============================================================================
# Usage : snapshot_list --vmid VMID
# =============================================================================
snapshot_list() {
    local vmid=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid) vmid="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid" ]] && die "Option --vmid requise."
    vmid_exists "$vmid" || die "VMID $vmid introuvable."

    local type name
    type=$(vmid_type "$vmid")
    name=$(vmid_name "$vmid")

    log_section "Snapshots — VMID $vmid ($name)"

    printf "${C_BOLD}%-25s %-10s %-30s %s${C_RESET}\n" \
        "NOM" "PARENT" "DESCRIPTION" "DATE"
    log_separator "-" 90

    local count=0
    case "$type" in
        qemu)
            # qm listsnapshot affiche une arborescence textuelle
            qm listsnapshot "$vmid" 2>/dev/null | while IFS= read -r line; do
                # Ligne typique : `     ->  snapname  YYYY-MM-DD HH:MM:SS  description`
                local snap_name snap_date snap_desc
                snap_name=$(echo "$line" | awk '{print $2}' | tr -d '->' )
                snap_date=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')
                snap_desc=$(echo "$line" | sed 's/.*[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}//' | sed 's/^ *//')

                [[ -z "$snap_name" || "$snap_name" == "current" ]] && continue
                printf "  ${C_CYAN}%-23s${C_RESET} %-10s %-30s %s\n" \
                    "$snap_name" "-" "${snap_desc:-(aucune)}" "${snap_date:-?}"
                (( count++ )) || true
            done
            ;;
        lxc)
            pct listsnapshot "$vmid" 2>/dev/null | tail -n +1 | while IFS= read -r line; do
                local snap_name snap_desc snap_date
                snap_name=$(echo "$line" | awk '{print $2}' | tr -d '->')
                snap_date=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')
                snap_desc=$(echo "$line" | sed 's/.*[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}//' | sed 's/^ *//')

                [[ -z "$snap_name" || "$snap_name" == "current" ]] && continue
                printf "  ${C_MAGENTA}%-23s${C_RESET} %-10s %-30s %s\n" \
                    "$snap_name" "-" "${snap_desc:-(aucune)}" "${snap_date:-?}"
                (( count++ )) || true
            done
            ;;
    esac

    log_separator "-" 90
    # On recompte car les sous-shells ne remontent pas les variables
    local snap_count
    snap_count=$(_list_snapshots "$vmid" "$type" | wc -l)
    echo -e "  ${C_BOLD}Total :${C_RESET} $snap_count snapshot(s)"
    echo ""
}

# =============================================================================
# RESTAURER DEPUIS UN SNAPSHOT
# =============================================================================
# Usage : snapshot_restore --vmid VMID --name NOM_SNAPSHOT
# =============================================================================
snapshot_restore() {
    local vmid="" snapname=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid) vmid="$2";     shift 2 ;;
            --name) snapname="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid"     ]] && die "Option --vmid requise."
    [[ -z "$snapname" ]] && {
        snapshot_list --vmid "$vmid"
        snapname=$(prompt_value "Nom du snapshot à restaurer")
    }
    [[ -z "$snapname" ]] && die "Nom du snapshot obligatoire."

    vmid_exists "$vmid" || die "VMID $vmid introuvable."
    local type name status
    type=$(vmid_type "$vmid")
    name=$(vmid_name "$vmid")
    status=$(vmid_status "$vmid")

    # Vérifie que le snapshot existe
    _snapshot_exists "$vmid" "$type" "$snapname" \
        || die "Snapshot '$snapname' introuvable pour VMID $vmid."

    log_section "Restauration snapshot — VMID $vmid ($name)"
    echo -e "  ${C_BOLD}Snapshot  :${C_RESET} $snapname"
    echo -e "  ${C_BOLD}Statut    :${C_RESET} $status"
    echo ""
    log_warn "ATTENTION : La restauration remplace l'état actuel de la machine !"
    log_warn "Toutes les données modifiées depuis ce snapshot seront PERDUES."
    echo ""

    confirm "Confirmer la restauration du snapshot '$snapname' sur VMID $vmid ?" "n" \
        || { log_info "Restauration annulée."; return 0; }

    # Arrêt de la machine si elle tourne
    if [[ "$status" == "running" ]]; then
        log_info "Arrêt de la machine avant restauration..."
        vm_shutdown "$vmid" "$type" 1 \
            || die "Impossible d'arrêter VMID $vmid avant la restauration."
        sleep 2
    fi

    log_info "Restauration du snapshot '$snapname'..."
    case "$type" in
        qemu) qm rollback "$vmid" "$snapname" \
                || die "Échec de la restauration du snapshot '$snapname'." ;;
        lxc)  pct rollback "$vmid" "$snapname" \
                || die "Échec de la restauration du snapshot '$snapname'." ;;
    esac

    log_success "Snapshot '$snapname' restauré avec succès pour VMID $vmid."
    echo -e "  → Redémarrez avec : ${C_CYAN}proxmox-admin.sh lifecycle --action start --vmid $vmid${C_RESET}"
}

# =============================================================================
# SUPPRIMER UN SNAPSHOT
# =============================================================================
# Usage : snapshot_delete --vmid VMID --name NOM_SNAPSHOT
# =============================================================================
snapshot_delete() {
    local vmid="" snapname=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid) vmid="$2";     shift 2 ;;
            --name) snapname="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid"     ]] && die "Option --vmid requise."
    [[ -z "$snapname" ]] && {
        snapshot_list --vmid "$vmid"
        snapname=$(prompt_value "Nom du snapshot à supprimer")
    }
    [[ -z "$snapname" ]] && die "Nom du snapshot obligatoire."

    vmid_exists "$vmid" || die "VMID $vmid introuvable."
    local type name
    type=$(vmid_type "$vmid")
    name=$(vmid_name "$vmid")

    _snapshot_exists "$vmid" "$type" "$snapname" \
        || die "Snapshot '$snapname' introuvable pour VMID $vmid."

    confirm "Supprimer définitivement le snapshot '$snapname' de VMID $vmid ($name) ?" "n" \
        || { log_info "Suppression annulée."; return 0; }

    log_info "Suppression du snapshot '$snapname'..."
    case "$type" in
        qemu) qm delsnapshot "$vmid" "$snapname" \
                || die "Échec de la suppression du snapshot." ;;
        lxc)  pct delsnapshot "$vmid" "$snapname" \
                || die "Échec de la suppression du snapshot." ;;
    esac
    log_success "Snapshot '$snapname' supprimé."
}

# =============================================================================
# CRÉER UNE SAUVEGARDE VZDUMP
# =============================================================================
# Usage : backup_create --vmid VMID [--storage STORAGE] [--mode MODE]
#         MODE : snapshot (défaut) | suspend | stop
# =============================================================================
backup_create() {
    local vmid="" storage="" mode="snapshot" compress="zstd"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid)     vmid="$2";     shift 2 ;;
            --storage)  storage="$2";  shift 2 ;;
            --mode)     mode="$2";     shift 2 ;;
            --compress) compress="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid"    ]] && die "Option --vmid requise."
    vmid_exists "$vmid" || die "VMID $vmid introuvable."

    storage="${storage:-${BACKUP_STORAGE:-local}}"
    local name type
    name=$(vmid_name "$vmid")
    type=$(vmid_type "$vmid")

    log_section "Sauvegarde vzdump — VMID $vmid ($name)"
    echo -e "  ${C_BOLD}Stockage  :${C_RESET} $storage"
    echo -e "  ${C_BOLD}Mode      :${C_RESET} $mode"
    echo -e "  ${C_BOLD}Compression:${C_RESET} $compress"

    confirm "Lancer la sauvegarde de VMID $vmid ?" "y" \
        || { log_info "Annulé."; return 0; }

    log_info "Sauvegarde en cours (peut prendre quelques minutes)..."
    if ! vzdump "$vmid" \
            --storage "$storage" \
            --mode "$mode" \
            --compress "$compress" \
            --notes-template "Backup auto $(date '+%Y-%m-%d %H:%M:%S')" \
            --remove 0; then
        die "Échec de la sauvegarde vzdump pour VMID $vmid."
    fi
    log_success "Sauvegarde de VMID $vmid terminée."
}

# =============================================================================
# LISTER LES SAUVEGARDES
# =============================================================================
# Usage : backup_list [--vmid VMID] [--storage STORAGE]
# =============================================================================
backup_list() {
    local vmid="" storage=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid)    vmid="$2";    shift 2 ;;
            --storage) storage="$2"; shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    storage="${storage:-${BACKUP_STORAGE:-local}}"
    log_section "Sauvegardes disponibles — stockage : $storage"

    if [[ -n "$vmid" ]]; then
        log_info "Filtrage sur VMID $vmid"
        pvesh get /nodes/"${PVE_NODE}"/storage/"$storage"/content \
            --output-format json 2>/dev/null \
            | grep -o '"volid":"[^"]*"' \
            | grep "vzdump-.*-${vmid}-" \
            | while read -r line; do
                echo "  $line"
              done
    else
        pvesh get /nodes/"${PVE_NODE}"/storage/"$storage"/content \
            --output-format json 2>/dev/null \
            | grep -o '"volid":"[^"]*"' \
            | grep 'vzdump-' \
            | while read -r line; do
                echo "  $line"
              done
    fi
}

# =============================================================================
# HELPERS PRIVÉS
# =============================================================================

# Vérifie qu'un snapshot existe pour une machine
_snapshot_exists() {
    local vmid="$1"
    local type="$2"
    local snapname="$3"
    case "$type" in
        qemu) qm listsnapshot "$vmid" 2>/dev/null | grep -qw "$snapname" ;;
        lxc)  pct listsnapshot "$vmid" 2>/dev/null | grep -qw "$snapname" ;;
        *)    return 1 ;;
    esac
}

# Retourne la liste des snapshots d'une machine
_list_snapshots() {
    local vmid="$1"
    local type="$2"
    case "$type" in
        qemu) qm listsnapshot "$vmid" 2>/dev/null \
            | awk '{print $2}' | grep -v '^current$' | grep -v '^$' | grep -v '^->' ;;
        lxc)  pct listsnapshot "$vmid" 2>/dev/null \
            | awk '{print $2}' | grep -v '^current$' | grep -v '^$' | grep -v '^->' ;;
    esac
}
