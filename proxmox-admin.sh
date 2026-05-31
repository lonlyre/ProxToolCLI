#!/usr/bin/env bash
# =============================================================================
# proxmox-admin.sh — Script principal d'administration Proxmox VE
# =============================================================================
#
# Usage : proxmox-admin.sh COMMANDE [OPTIONS]
#
# Commandes :
#   deploy      — Déployer une VM ou un conteneur LXC
#   lifecycle   — Gérer le cycle de vie (start/stop/reboot/...)
#   supervision — Surveiller les machines (liste, ressources, connectivité)
#   snapshot    — Gérer les snapshots
#   backup      — Gérer les sauvegardes vzdump
#   delete      — Supprimer une machine
#   help        — Afficher l'aide
#
# Exemples :
#   proxmox-admin.sh deploy --type vm-template --name webserver --template 9000
#   proxmox-admin.sh lifecycle --action start --vmid 101
#   proxmox-admin.sh supervision list
#   proxmox-admin.sh snapshot create --vmid 101 --name avant-mise-a-jour
#   proxmox-admin.sh delete --vmid 101
#
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# --- Localisation du script (pour les chemins relatifs) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# --- Chargement du module commun ---
if [[ ! -f "${LIB_DIR}/common.sh" ]]; then
    echo "[ERREUR] Impossible de trouver ${LIB_DIR}/common.sh" >&2
    echo "  Assurez-vous de lancer ce script depuis son répertoire d'installation." >&2
    exit 1
fi
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# --- Chargement de la configuration ---
load_config "${SCRIPT_DIR}/config.conf"

# --- Version ---
PROXMOX_ADMIN_VERSION="1.0.0"

# =============================================================================
# AIDE PRINCIPALE
# =============================================================================
show_help() {
    echo ""
    echo -e "${C_BCYAN}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BCYAN}║          Proxmox Admin — Administration CLI v${PROXMOX_ADMIN_VERSION}          ║${C_RESET}"
    echo -e "${C_BCYAN}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    echo -e "${C_BOLD}USAGE :${C_RESET}"
    echo -e "  $(basename "$0") ${C_CYAN}COMMANDE${C_RESET} [OPTIONS]"
    echo ""
    echo -e "${C_BOLD}COMMANDES DISPONIBLES :${C_RESET}"
    echo ""
    echo -e "  ${C_BCYAN}deploy${C_RESET}        Déployer une nouvelle machine"
    echo -e "    ${C_DIM}--type vm-template${C_RESET}  Clone depuis template cloud-init"
    echo -e "    ${C_DIM}--type vm-iso${C_RESET}       Crée depuis une ISO"
    echo -e "    ${C_DIM}--type lxc${C_RESET}          Crée un conteneur LXC"
    echo ""
    echo -e "  ${C_BCYAN}lifecycle${C_RESET}     Gérer le cycle de vie d'une machine"
    echo -e "    ${C_DIM}--action start${C_RESET}     Démarrer"
    echo -e "    ${C_DIM}--action shutdown${C_RESET}  Arrêt propre (ACPI)"
    echo -e "    ${C_DIM}--action stop${C_RESET}      Arrêt forcé"
    echo -e "    ${C_DIM}--action reboot${C_RESET}    Redémarrer"
    echo -e "    ${C_DIM}--action suspend${C_RESET}   Suspendre (VMs)"
    echo -e "    ${C_DIM}--action resume${C_RESET}    Reprendre"
    echo -e "    ${C_DIM}--action reset${C_RESET}     Reset matériel brutal"
    echo ""
    echo -e "  ${C_BCYAN}supervision${C_RESET}   Surveiller les machines"
    echo -e "    ${C_DIM}list${C_RESET}               Lister toutes les VMs/LXC"
    echo -e "    ${C_DIM}resources${C_RESET}          Ressources d'une machine"
    echo -e "    ${C_DIM}check${C_RESET}              Test ping + SSH"
    echo -e "    ${C_DIM}info${C_RESET}               Infos complètes (resources + check)"
    echo ""
    echo -e "  ${C_BCYAN}snapshot${C_RESET}      Gérer les snapshots"
    echo -e "    ${C_DIM}create${C_RESET}             Créer un snapshot"
    echo -e "    ${C_DIM}list${C_RESET}               Lister les snapshots"
    echo -e "    ${C_DIM}restore${C_RESET}            Restaurer depuis un snapshot"
    echo -e "    ${C_DIM}delete${C_RESET}             Supprimer un snapshot"
    echo ""
    echo -e "  ${C_BCYAN}backup${C_RESET}        Gérer les sauvegardes vzdump"
    echo -e "    ${C_DIM}create${C_RESET}             Créer une sauvegarde"
    echo -e "    ${C_DIM}list${C_RESET}               Lister les sauvegardes"
    echo ""
    echo -e "  ${C_BCYAN}delete${C_RESET}        Supprimer une machine (avec confirmations)"
    echo ""
    echo -e "${C_BOLD}OPTIONS GLOBALES :${C_RESET}"
    echo -e "  ${C_DIM}--config FILE${C_RESET}  Chemin vers un fichier config alternatif"
    echo -e "  ${C_DIM}--node   NODE${C_RESET}  Surcharger le nœud Proxmox"
    echo -e "  ${C_DIM}--no-color${C_RESET}     Désactiver les couleurs ANSI"
    echo -e "  ${C_DIM}--yes${C_RESET}          Répondre oui à toutes les confirmations"
    echo -e "  ${C_DIM}--debug${C_RESET}        Mode verbeux (LOG_LEVEL=DEBUG)"
    echo -e "  ${C_DIM}--version${C_RESET}      Afficher la version"
    echo ""
    echo -e "${C_BOLD}EXEMPLES :${C_RESET}"
    echo -e "  # Déployer une VM depuis un template cloud-init"
    echo -e "  $(basename "$0") deploy --type vm-template \\"
    echo -e "      --name webserver --template 9000 \\"
    echo -e "      --cpu 2 --ram 2048 --disk 20 \\"
    echo -e "      --ip 192.168.1.50/24 --gw 192.168.1.1"
    echo ""
    echo -e "  # Déployer un LXC Debian"
    echo -e "  $(basename "$0") deploy --type lxc \\"
    echo -e "      --name monitoring --template local:vztmpl/debian-12.tar.zst \\"
    echo -e "      --cpu 1 --ram 512 --ip dhcp"
    echo ""
    echo -e "  # Lister toutes les machines en cours d'exécution"
    echo -e "  $(basename "$0") supervision list --status running"
    echo ""
    echo -e "  # Créer un snapshot avant une mise à jour"
    echo -e "  $(basename "$0") snapshot create --vmid 101 --name avant-maj \\"
    echo -e "      --desc 'Avant mise à jour système du $(date +%Y-%m-%d)'"
    echo ""
    echo -e "  # Supprimer une machine (avec double confirmation)"
    echo -e "  $(basename "$0") delete --vmid 101"
    echo ""
    echo -e "${C_DIM}Nœud actuel : ${PVE_NODE:-pve} | Config : ${PROXMOX_ADMIN_CONFIG:-config.conf}${C_RESET}"
    echo ""
}

# =============================================================================
# PARSEUR DES ARGUMENTS GLOBAUX
# =============================================================================
parse_global_args() {
    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                load_config "$2"
                shift 2
                ;;
            --node)
                PVE_NODE="$2"
                shift 2
                ;;
            --no-color)
                FORCE_COLOR=0
                _init_colors
                shift
                ;;
            --yes|-y)
                CONFIRM_DESTRUCTIVE=0
                shift
                ;;
            --debug)
                LOG_LEVEL=DEBUG
                shift
                ;;
            --version)
                echo "proxmox-admin v${PROXMOX_ADMIN_VERSION}"
                exit 0
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Retourner les arguments non-globaux
    printf '%s\n' "${args[@]}"
}

# =============================================================================
# CHARGEMENT CONDITIONNEL DES MODULES
# =============================================================================
load_module() {
    local module="$1"
    local module_file="${LIB_DIR}/${module}.sh"

    if [[ ! -f "$module_file" ]]; then
        die "Module introuvable : ${module_file}" 10
    fi
    # shellcheck source=/dev/null
    source "$module_file"
}

# =============================================================================
# POINT D'ENTRÉE PRINCIPAL
# =============================================================================
main() {
    # Vérifications préalables
    check_root
    check_proxmox_host

    # Pas d'arguments → aide
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Récupère la commande principale
    local command="$1"
    shift

    # Parse les arguments globaux et récupère les restants
    local remaining_args=()
    while IFS= read -r line; do
        remaining_args+=("$line")
    done < <(parse_global_args "$@")

    log_debug "Commande: $command | Args restants: ${remaining_args[*]:-}"

    # --- Dispatcher ---
    case "$command" in

        # ── DEPLOY ──────────────────────────────────────────────────────────
        deploy)
            load_module deploy
            local dtype=""
            local deploy_args=()

            # Extrait --type et passe le reste à la fonction
            local i=0
            while [[ $i -lt ${#remaining_args[@]} ]]; do
                if [[ "${remaining_args[$i]}" == "--type" ]]; then
                    (( i++ ))
                    dtype="${remaining_args[$i]}"
                else
                    deploy_args+=("${remaining_args[$i]}")
                fi
                (( i++ ))
            done

            case "$dtype" in
                vm-template|vm|template)
                    deploy_vm_from_template "${deploy_args[@]:-}" ;;
                vm-iso|iso)
                    deploy_vm_from_iso      "${deploy_args[@]:-}" ;;
                lxc|ct)
                    deploy_lxc              "${deploy_args[@]:-}" ;;
                "")
                    echo -e "\n${C_BYELLOW}Type de déploiement non spécifié.${C_RESET}"
                    echo "Sélectionnez le type :"
                    echo "  1) VM depuis template cloud-init"
                    echo "  2) VM depuis ISO"
                    echo "  3) Conteneur LXC"
                    echo -n "Votre choix [1-3] : "
                    read -r choice
                    case "$choice" in
                        1) deploy_vm_from_template "${deploy_args[@]:-}" ;;
                        2) deploy_vm_from_iso      "${deploy_args[@]:-}" ;;
                        3) deploy_lxc              "${deploy_args[@]:-}" ;;
                        *) die "Choix invalide." ;;
                    esac
                    ;;
                *) die "Type de déploiement inconnu : '$dtype'. Valeurs : vm-template, vm-iso, lxc" ;;
            esac
            ;;

        # ── LIFECYCLE ───────────────────────────────────────────────────────
        lifecycle|lc)
            load_module lifecycle
            lifecycle_action "${remaining_args[@]:-}"
            ;;

        # ── SUPERVISION ─────────────────────────────────────────────────────
        supervision|sup|monitor)
            load_module supervision
            local sub_cmd="${remaining_args[0]:-list}"
            local sub_args=("${remaining_args[@]:1}")
            case "$sub_cmd" in
                list)      supervision_list      "${sub_args[@]:-}" ;;
                resources) supervision_resources "${sub_args[@]:-}" ;;
                check)     supervision_check     "${sub_args[@]:-}" ;;
                info)      supervision_info      "${sub_args[@]:-}" ;;
                *) die "Sous-commande supervision inconnue : '$sub_cmd'. Valeurs : list, resources, check, info" ;;
            esac
            ;;

        # ── SNAPSHOT ────────────────────────────────────────────────────────
        snapshot|snap)
            load_module snapshot
            local sub_cmd="${remaining_args[0]:-list}"
            local sub_args=("${remaining_args[@]:1}")
            case "$sub_cmd" in
                create)  snapshot_create  "${sub_args[@]:-}" ;;
                list)    snapshot_list    "${sub_args[@]:-}" ;;
                restore) snapshot_restore "${sub_args[@]:-}" ;;
                delete)  snapshot_delete  "${sub_args[@]:-}" ;;
                *) die "Sous-commande snapshot inconnue : '$sub_cmd'. Valeurs : create, list, restore, delete" ;;
            esac
            ;;

        # ── BACKUP ──────────────────────────────────────────────────────────
        backup|bak)
            load_module snapshot
            local sub_cmd="${remaining_args[0]:-list}"
            local sub_args=("${remaining_args[@]:1}")
            case "$sub_cmd" in
                create) backup_create "${sub_args[@]:-}" ;;
                list)   backup_list   "${sub_args[@]:-}" ;;
                *) die "Sous-commande backup inconnue : '$sub_cmd'. Valeurs : create, list" ;;
            esac
            ;;

        # ── DELETE ──────────────────────────────────────────────────────────
        delete|destroy|rm)
            load_module lifecycle  # Pour vm_shutdown
            load_module snapshot   # Pour lister les snapshots
            load_module delete
            delete_machine "${remaining_args[@]:-}"
            ;;

        # ── AIDE ────────────────────────────────────────────────────────────
        help|--help|-h)
            show_help
            ;;

        # ── INCONNU ─────────────────────────────────────────────────────────
        *)
            log_error "Commande inconnue : '$command'"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# --- Gestion des interruptions propres ---
trap 'echo -e "\n${C_YELLOW}[INTERRUPTION] Script interrompu.${C_RESET}"; exit 130' INT TERM

# --- Lancement ---
main "$@"
