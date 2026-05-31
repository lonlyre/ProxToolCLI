#!/usr/bin/env bash
# =============================================================================
# lib/lifecycle.sh — Gestion du cycle de vie des VMs et LXC
# =============================================================================
# Fonctions :
#   lifecycle_action   — Dispatcher principal (start/stop/shutdown/reboot/...)
#   vm_start           — Démarrer une VM/LXC
#   vm_shutdown        — Arrêt propre (ACPI)
#   vm_stop            — Arrêt forcé (kill)
#   vm_reboot          — Redémarrer
#   vm_suspend         — Suspendre (VMs uniquement)
#   vm_resume          — Reprendre depuis suspension
#   vm_reset           — Reset matériel (équivalent bouton reset)

[[ -n "${_LIFECYCLE_LOADED:-}" ]] && return 0
_LIFECYCLE_LOADED=1

# =============================================================================
# DISPATCHER
# =============================================================================
# Usage : lifecycle_action --action ACTION --vmid VMID [--force]
# =============================================================================
lifecycle_action() {
    local action="" vmid="" force=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action) action="$2"; shift 2 ;;
            --vmid)   vmid="$2";   shift 2 ;;
            --force)  force=1;     shift   ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    [[ -z "$vmid"   ]] && die "Option --vmid requise."
    [[ -z "$action" ]] && die "Option --action requise."

    # Vérifie que la VM/LXC existe
    if ! vmid_exists "$vmid"; then
        die "Aucune VM ou LXC avec le VMID $vmid."
    fi

    local name type
    name=$(vmid_name "$vmid")
    type=$(vmid_type "$vmid")
    log_info "Action '${action}' sur ${type^^} $vmid ($name)"

    case "$action" in
        start)    vm_start    "$vmid" "$type" ;;
        shutdown) vm_shutdown "$vmid" "$type" "$force" ;;
        stop)     vm_stop     "$vmid" "$type" ;;
        reboot)   vm_reboot   "$vmid" "$type" ;;
        suspend)  vm_suspend  "$vmid" "$type" ;;
        resume)   vm_resume   "$vmid" "$type" ;;
        reset)    vm_reset    "$vmid" "$type" ;;
        *) die "Action inconnue : '$action'. Valeurs valides : start, shutdown, stop, reboot, suspend, resume, reset" ;;
    esac
}

# =============================================================================
# START
# =============================================================================
vm_start() {
    local vmid="$1"
    local type="${2:-$(vmid_type "$vmid")}"
    local current_status
    current_status=$(vmid_status "$vmid")

    if [[ "$current_status" == "running" ]]; then
        log_warn "VMID $vmid est déjà en cours d'exécution (running)."
        return 0
    fi

    if [[ "$current_status" == "suspended" ]]; then
        log_info "La machine est suspendue, utilisez 'resume' à la place."
        vm_resume "$vmid" "$type"
        return $?
    fi

    log_info "Démarrage de VMID $vmid ($type)..."
    case "$type" in
        qemu) qm start "$vmid"  || die "Échec du démarrage de la VM $vmid." ;;
        lxc)  pct start "$vmid" || die "Échec du démarrage du LXC $vmid." ;;
    esac

    # Attente que la machine soit réellement running
    local timeout="${TIMEOUT_START:-120}"
    if wait_for "démarrage VMID $vmid" \
        "_check_status_is $vmid running" "$timeout"; then
        log_success "VMID $vmid démarré avec succès."
    else
        log_warn "Timeout : la machine ne répond pas encore mais le démarrage a été lancé."
    fi
}

# =============================================================================
# SHUTDOWN (arrêt propre via signal ACPI)
# =============================================================================
vm_shutdown() {
    local vmid="$1"
    local type="${2:-$(vmid_type "$vmid")}"
    local force="${3:-0}"
    local current_status
    current_status=$(vmid_status "$vmid")

    if [[ "$current_status" == "stopped" ]]; then
        log_warn "VMID $vmid est déjà arrêté."
        return 0
    fi

    local timeout="${TIMEOUT_STOP:-60}"

    log_info "Arrêt propre (ACPI) de VMID $vmid..."
    case "$type" in
        qemu) qm shutdown "$vmid" --timeout "$timeout" \
                || { [[ "$force" == "1" ]] && vm_stop "$vmid" "$type"; return $?; } ;;
        lxc)  pct shutdown "$vmid" --timeout "$timeout" \
                || { [[ "$force" == "1" ]] && vm_stop "$vmid" "$type"; return $?; } ;;
    esac

    # Attente arrêt
    if wait_for "arrêt VMID $vmid" \
        "_check_status_is $vmid stopped" "$timeout"; then
        log_success "VMID $vmid arrêté proprement."
    else
        if [[ "$force" == "1" ]]; then
            log_warn "Timeout atteint, arrêt forcé..."
            vm_stop "$vmid" "$type"
        else
            log_warn "Timeout. Utilisez --force ou 'stop' pour un arrêt forcé."
            return 1
        fi
    fi
}

# =============================================================================
# STOP (arrêt forcé — comme couper le courant)
# =============================================================================
vm_stop() {
    local vmid="$1"
    local type="${2:-$(vmid_type "$vmid")}"
    local current_status
    current_status=$(vmid_status "$vmid")

    if [[ "$current_status" == "stopped" ]]; then
        log_warn "VMID $vmid est déjà arrêté."
        return 0
    fi

    log_warn "Arrêt FORCÉ de VMID $vmid (perte de données possible)..."
    case "$type" in
        qemu) qm stop "$vmid"  || die "Échec arrêt forcé VM $vmid." ;;
        lxc)  pct stop "$vmid" || die "Échec arrêt forcé LXC $vmid." ;;
    esac

    wait_for "arrêt forcé VMID $vmid" \
        "_check_status_is $vmid stopped" 30 \
        || log_warn "La machine ne répond toujours pas."
    log_success "VMID $vmid arrêté de force."
}

# =============================================================================
# REBOOT
# =============================================================================
vm_reboot() {
    local vmid="$1"
    local type="${2:-$(vmid_type "$vmid")}"
    local current_status
    current_status=$(vmid_status "$vmid")

    if [[ "$current_status" != "running" ]]; then
        log_warn "VMID $vmid n'est pas en cours d'exécution (statut: $current_status)."
        log_info "Démarrage au lieu du redémarrage..."
        vm_start "$vmid" "$type"
        return $?
    fi

    log_info "Redémarrage de VMID $vmid..."
    case "$type" in
        qemu) qm reboot "$vmid"  || die "Échec du redémarrage VM $vmid." ;;
        lxc)  pct reboot "$vmid" || die "Échec du redémarrage LXC $vmid." ;;
    esac
    log_success "Signal de redémarrage envoyé à VMID $vmid."
}

# =============================================================================
# SUSPEND (VMs uniquement — LXC ne supporte pas)
# =============================================================================
vm_suspend() {
    local vmid="$1"
    local type="${2:-$(vmid_type "$vmid")}"

    if [[ "$type" == "lxc" ]]; then
        log_warn "La suspension n'est pas supportée sur les conteneurs LXC."
        log_info "Utilisez 'shutdown' ou 'stop' pour un LXC."
        return 1
    fi

    local current_status
    current_status=$(vmid_status "$vmid")
    if [[ "$current_status" != "running" ]]; then
        die "Impossible de suspendre VMID $vmid : statut actuel '$current_status' (requis: running)."
    fi

    log_info "Suspension de la VM $vmid (sauvegarde état RAM sur disque)..."
    qm suspend "$vmid" --todisk 1 \
        || die "Échec de la suspension VM $vmid."

    log_success "VM $vmid suspendue sur disque."
}

# =============================================================================
# RESUME
# =============================================================================
vm_resume() {
    local vmid="$1"
    local type="${2:-$(vmid_type "$vmid")}"
    local current_status
    current_status=$(vmid_status "$vmid")

    if [[ "$type" == "lxc" ]]; then
        log_warn "Resume non applicable aux LXC. Utilisez 'start'."
        vm_start "$vmid" "$type"
        return $?
    fi

    if [[ "$current_status" != "suspended" ]]; then
        log_warn "VMID $vmid n'est pas suspendu (statut: $current_status)."
        if [[ "$current_status" == "stopped" ]]; then
            log_info "Démarrage de la VM..."
            vm_start "$vmid" "$type"
        fi
        return 0
    fi

    log_info "Reprise de la VM $vmid depuis suspension..."
    qm resume "$vmid" || die "Échec du resume VM $vmid."

    wait_for "reprise VMID $vmid" \
        "_check_status_is $vmid running" "${TIMEOUT_START:-120}" \
        && log_success "VM $vmid reprise avec succès."
}

# =============================================================================
# RESET (reset matériel brutal)
# =============================================================================
vm_reset() {
    local vmid="$1"
    local type="${2:-$(vmid_type "$vmid")}"

    if [[ "$type" == "lxc" ]]; then
        log_warn "Reset matériel non applicable aux LXC. Utilisez stop+start."
        vm_stop "$vmid" "$type"
        sleep 2
        vm_start "$vmid" "$type"
        return $?
    fi

    local current_status
    current_status=$(vmid_status "$vmid")
    if [[ "$current_status" != "running" ]]; then
        die "Reset impossible : VMID $vmid n'est pas en cours d'exécution."
    fi

    confirm "Reset matériel brutal de VMID $vmid (équivalent bouton reset) ?" "n" \
        || { log_info "Annulé."; return 0; }

    log_warn "Reset matériel de VM $vmid..."
    qm reset "$vmid" || die "Échec du reset VM $vmid."
    log_success "Reset envoyé à VM $vmid."
}

# =============================================================================
# HELPERS INTERNES
# =============================================================================

# Vérifie que le statut d'une machine correspond à la valeur attendue
# Usage : _check_status_is VMID expected_status
_check_status_is() {
    local vmid="$1"
    local expected="$2"
    local current
    current=$(vmid_status "$vmid")
    [[ "$current" == "$expected" ]]
}
