#!/usr/bin/env bash
# =============================================================================
# lib/delete.sh — Suppression sécurisée de VMs et conteneurs LXC
# =============================================================================
# Fonctions :
#   delete_machine  — Supprime proprement une VM ou un LXC (avec confirmations)

[[ -n "${_DELETE_LOADED:-}" ]] && return 0
_DELETE_LOADED=1

# =============================================================================
# SUPPRESSION D'UNE VM OU LXC
# =============================================================================
# Usage : delete_machine --vmid VMID [--force] [--purge-disk]
#
# Options :
#   --vmid        VMID de la machine à supprimer (obligatoire)
#   --force       Ne pas demander confirmation (dangereux !)
#   --purge-disk  Supprimer aussi les disques sur le stockage
# =============================================================================
delete_machine() {
    local vmid="" force=0 purge_disk=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid)       vmid="$2"; shift 2 ;;
            --force)      force=1;   shift   ;;
            --purge-disk) purge_disk=1; shift ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid" ]] && die "Option --vmid requise."
    vmid_exists "$vmid" || die "Aucune VM ou LXC avec le VMID $vmid."

    local type name status
    type=$(vmid_type "$vmid")
    name=$(vmid_name "$vmid")
    status=$(vmid_status "$vmid")

    log_section "Suppression — VMID $vmid"

    # --- Affichage des infos de la machine ---
    echo -e "  ${C_BOLD}VMID      :${C_RESET} $vmid"
    echo -e "  ${C_BOLD}Nom       :${C_RESET} ${C_BRED}$name${C_RESET}"
    echo -e "  ${C_BOLD}Type      :${C_RESET} ${type^^}"
    echo -e "  ${C_BOLD}Statut    :${C_RESET} $status"
    echo ""

    # --- Lister les snapshots existants (avertissement) ---
    local snap_list
    snap_list=$(_list_snapshots_delete "$vmid" "$type")
    if [[ -n "$snap_list" ]]; then
        log_warn "Cette machine possède des snapshots qui seront aussi supprimés :"
        echo "$snap_list" | while read -r snap; do
            [[ -z "$snap" ]] && continue
            echo -e "    ${C_YELLOW}• $snap${C_RESET}"
        done
        echo ""
    fi

    # --- Double confirmation pour les opérations destructives ---
    if [[ "$force" == "0" ]]; then
        log_warn "╔══════════════════════════════════════════════════════╗"
        log_warn "║  ATTENTION : CETTE OPÉRATION EST IRRÉVERSIBLE !     ║"
        log_warn "╚══════════════════════════════════════════════════════╝"
        echo ""

        # Première confirmation
        confirm "Supprimer définitivement VMID $vmid ($name) ?" "n" \
            || { log_info "Suppression annulée."; return 0; }

        # Seconde confirmation : demande de retaper le nom
        echo -en "${C_BRED}  Tapez le nom de la machine pour confirmer ('${name}') : ${C_RESET}"
        local typed_name
        read -r typed_name
        if [[ "$typed_name" != "$name" ]]; then
            log_warn "Nom incorrect. Suppression annulée par sécurité."
            return 0
        fi
    else
        log_warn "Mode --force : suppression sans confirmation."
    fi

    # --- Étape 1 : Arrêt de la machine si elle tourne ---
    if [[ "$status" == "running" ]]; then
        log_info "[1/3] Arrêt de la machine avant suppression..."
        case "$type" in
            qemu)
                if ! qm shutdown "$vmid" --timeout "${TIMEOUT_STOP:-60}"; then
                    log_warn "Arrêt propre échoué, arrêt forcé..."
                    qm stop "$vmid" || log_warn "Impossible d'arrêter la VM (on continue)."
                fi
                ;;
            lxc)
                if ! pct shutdown "$vmid" --timeout "${TIMEOUT_STOP:-60}"; then
                    log_warn "Arrêt propre échoué, arrêt forcé..."
                    pct stop "$vmid" || log_warn "Impossible d'arrêter le LXC (on continue)."
                fi
                ;;
        esac

        # Attente arrêt effectif
        local elapsed=0
        while [[ "$(vmid_status "$vmid")" != "stopped" ]]; do
            sleep 1
            (( elapsed++ ))
            if (( elapsed >= 30 )); then
                log_warn "Timeout arrêt. On force la suppression quand même."
                break
            fi
        done
        log_success "Machine arrêtée."
    else
        log_info "[1/3] Machine déjà arrêtée."
    fi

    # --- Étape 2 : Suppression des snapshots ---
    if [[ -n "$snap_list" ]]; then
        log_info "[2/3] Suppression des snapshots..."
        echo "$snap_list" | while read -r snap; do
            [[ -z "$snap" ]] && continue
            log_debug "  Suppression snapshot : $snap"
            case "$type" in
                qemu) qm delsnapshot "$vmid" "$snap" 2>/dev/null || true ;;
                lxc)  pct delsnapshot "$vmid" "$snap" 2>/dev/null || true ;;
            esac
        done
        log_success "Snapshots supprimés."
    else
        log_info "[2/3] Aucun snapshot à supprimer."
    fi

    # --- Étape 3 : Suppression de la machine ---
    log_info "[3/3] Suppression de la machine VMID $vmid ($name)..."
    local destroy_args=()

    case "$type" in
        qemu)
            destroy_args=(qm destroy "$vmid")
            [[ "$purge_disk" == "1" ]] && destroy_args+=(--destroy-unreferenced-disks 1 --purge 1)
            ;;
        lxc)
            destroy_args=(pct destroy "$vmid")
            [[ "$purge_disk" == "1" ]] && destroy_args+=(--purge 1)
            ;;
    esac

    if ! "${destroy_args[@]}"; then
        die "Échec de la suppression de VMID $vmid."
    fi

    # --- Vérification ---
    if vmid_exists "$vmid"; then
        log_error "La machine VMID $vmid semble toujours exister après suppression."
        return 1
    fi

    log_separator
    log_success "VMID $vmid ($name) supprimé avec succès."
    _write_log "INFO" "SUPPRESSION: VMID=$vmid NAME=$name TYPE=$type par $(whoami) le $(date)"
}

# =============================================================================
# HELPER PRIVÉ
# =============================================================================
_list_snapshots_delete() {
    local vmid="$1"
    local type="$2"
    case "$type" in
        qemu) qm listsnapshot "$vmid" 2>/dev/null \
            | awk '{print $2}' \
            | grep -v -E '^(current|-+>|)$' \
            | grep -v '^$' ;;
        lxc)  pct listsnapshot "$vmid" 2>/dev/null \
            | awk '{print $2}' \
            | grep -v -E '^(current|-+>|)$' \
            | grep -v '^$' ;;
    esac
}
