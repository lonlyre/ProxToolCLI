#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Fonctions communes : logs, couleurs, utilitaires
# =============================================================================
# Chargé automatiquement par tous les autres modules.
# NE PAS exécuter directement.

# Protection contre le double-chargement
[[ -n "${_COMMON_LOADED:-}" ]] && return 0
_COMMON_LOADED=1

# =============================================================================
# COULEURS & STYLES ANSI
# =============================================================================
_init_colors() {
    if [[ "${FORCE_COLOR:-1}" == "1" ]] || [[ -t 1 ]]; then
        C_RESET='\033[0m'
        C_BOLD='\033[1m'
        C_DIM='\033[2m'
        C_RED='\033[0;31m'
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[0;33m'
        C_BLUE='\033[0;34m'
        C_MAGENTA='\033[0;35m'
        C_CYAN='\033[0;36m'
        C_WHITE='\033[0;37m'
        C_BRED='\033[1;31m'
        C_BGREEN='\033[1;32m'
        C_BYELLOW='\033[1;33m'
        C_BBLUE='\033[1;34m'
        C_BCYAN='\033[1;36m'
    else
        C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
        C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE='' C_BRED='' C_BGREEN=''
        C_BYELLOW='' C_BBLUE='' C_BCYAN=''
    fi
}
_init_colors

# =============================================================================
# LOGGING
# =============================================================================

# Niveaux de log : DEBUG=0 INFO=1 WARN=2 ERROR=3
declare -A _LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

_should_log() {
    local level="$1"
    local configured_level="${LOG_LEVEL:-INFO}"
    (( ${_LOG_LEVELS[$level]:-1} >= ${_LOG_LEVELS[$configured_level]:-1} ))
}

_write_log() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Créer le répertoire de logs si nécessaire
    if [[ -n "${LOG_FILE:-}" ]]; then
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null || true
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_debug() {
    _should_log DEBUG || return 0
    echo -e "${C_DIM}[DEBUG] $*${C_RESET}" >&2
    _write_log "DEBUG" "$*"
}

log_info() {
    _should_log INFO || return 0
    echo -e "${C_BLUE}[INFO]${C_RESET}  $*"
    _write_log "INFO" "$*"
}

log_success() {
    _should_log INFO || return 0
    echo -e "${C_BGREEN}[OK]${C_RESET}    $*"
    _write_log "INFO" "[SUCCESS] $*"
}

log_warn() {
    _should_log WARN || return 0
    echo -e "${C_BYELLOW}[WARN]${C_RESET}  $*" >&2
    _write_log "WARN" "$*"
}

log_error() {
    _should_log ERROR || return 0
    echo -e "${C_BRED}[ERROR]${C_RESET} $*" >&2
    _write_log "ERROR" "$*"
}

# Affiche une ligne de séparation
log_separator() {
    local char="${1:--}"
    local width="${2:-70}"
    printf "${C_DIM}%${width}s${C_RESET}\n" | tr ' ' "$char"
}

# Titre de section
log_section() {
    echo ""
    log_separator "="
    echo -e "${C_BCYAN}  $*${C_RESET}"
    log_separator "="
}

# =============================================================================
# GESTION DES ERREURS
# =============================================================================

# Quitte proprement avec un message d'erreur
die() {
    local msg="${1:-Erreur inconnue}"
    local code="${2:-1}"
    log_error "$msg"
    log_error "Code de sortie : $code"
    exit "$code"
}

# Vérifie qu'une commande retourne 0, sinon die()
must_succeed() {
    local desc="${1:-commande}"
    shift
    log_debug "Exécution : $*"
    if ! "$@"; then
        die "Échec de : $desc ($*)" 1
    fi
}

# Exécute une commande et retourne son code de retour sans quitter
run_cmd() {
    log_debug "run_cmd: $*"
    "$@"
    return $?
}

# =============================================================================
# VALIDATION & PRÉREQUIS
# =============================================================================

# Vérifie que l'on tourne bien sur un nœud Proxmox
check_proxmox_host() {
    if ! command -v pvesh &>/dev/null && \
       ! command -v qm &>/dev/null && \
       ! command -v pct &>/dev/null; then
        die "Ce script doit être exécuté directement sur un nœud Proxmox VE.\n  Commandes qm/pct/pvesh introuvables." 2
    fi
}

# Vérifie qu'on tourne en root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Ce script doit être exécuté en tant que root." 3
    fi
}

# Vérifie que des dépendances sont installées
require_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Commandes manquantes : ${missing[*]}\nInstallez-les avant de continuer." 4
    fi
}

# =============================================================================
# VMID HELPERS
# =============================================================================

# Retourne le prochain VMID disponible
next_vmid() {
    local min="${VMID_MIN:-100}"
    local max="${VMID_MAX:-9999}"
    local id

    # pvesh retourne la liste de tous les IDs
    local used_ids
    used_ids=$(pvesh get /nodes/"${PVE_NODE}"/qemu --output-format json 2>/dev/null \
        | grep -o '"vmid":[0-9]*' | grep -o '[0-9]*' ; \
        pvesh get /nodes/"${PVE_NODE}"/lxc --output-format json 2>/dev/null \
        | grep -o '"vmid":[0-9]*' | grep -o '[0-9]*')

    for (( id=min; id<=max; id++ )); do
        if ! echo "$used_ids" | grep -qx "$id"; then
            echo "$id"
            return 0
        fi
    done
    die "Aucun VMID disponible entre $min et $max" 5
}

# Vérifie qu'un VMID existe (VM ou LXC)
vmid_exists() {
    local vmid="$1"
    qm status "$vmid" &>/dev/null || pct status "$vmid" &>/dev/null
}

# Retourne "qemu" si c'est une VM, "lxc" si c'est un conteneur, "" sinon
vmid_type() {
    local vmid="$1"
    if qm status "$vmid" &>/dev/null; then
        echo "qemu"
    elif pct status "$vmid" &>/dev/null; then
        echo "lxc"
    else
        echo ""
    fi
}

# Retourne le statut d'une VM/LXC : running | stopped | suspended | ...
vmid_status() {
    local vmid="$1"
    local type
    type=$(vmid_type "$vmid")
    case "$type" in
        qemu)  qm status "$vmid" 2>/dev/null | awk '{print $2}' ;;
        lxc)   pct status "$vmid" 2>/dev/null | awk '{print $2}' ;;
        *)     echo "unknown" ;;
    esac
}

# Retourne le nom d'une VM/LXC
vmid_name() {
    local vmid="$1"
    local type
    type=$(vmid_type "$vmid")
    case "$type" in
        qemu)  qm config "$vmid" 2>/dev/null | grep '^name:' | awk '{print $2}' ;;
        lxc)   pct config "$vmid" 2>/dev/null | grep '^hostname:' | awk '{print $2}' ;;
        *)     echo "unknown" ;;
    esac
}

# =============================================================================
# INTERACTION UTILISATEUR
# =============================================================================

# Demande confirmation (retourne 0=oui, 1=non)
confirm() {
    local prompt="${1:-Confirmer ?}"
    local default="${2:-n}"   # y ou n

    if [[ "${CONFIRM_DESTRUCTIVE:-1}" == "0" ]]; then
        return 0  # Mode non-interactif : toujours oui
    fi

    local choices
    if [[ "$default" == "y" ]]; then
        choices="[O/n]"
    else
        choices="[o/N]"
    fi

    echo -en "${C_BYELLOW}${prompt} ${choices} ${C_RESET}"
    read -r answer
    answer="${answer,,}"  # lowercase

    if [[ "$default" == "y" ]]; then
        [[ "$answer" == "n" ]] && return 1 || return 0
    else
        [[ "$answer" == "o" || "$answer" == "y" ]] && return 0 || return 1
    fi
}

# Saisie utilisateur avec valeur par défaut
prompt_value() {
    local label="$1"
    local default="${2:-}"
    local value

    if [[ -n "$default" ]]; then
        echo -en "${C_CYAN}${label} [${default}]: ${C_RESET}"
    else
        echo -en "${C_CYAN}${label}: ${C_RESET}"
    fi
    read -r value
    echo "${value:-$default}"
}

# =============================================================================
# FORMATAGE
# =============================================================================

# Convertit des Mo en affichage humain
format_mem() {
    local mb="$1"
    if (( mb >= 1024 )); then
        printf "%.1f Go" "$(echo "scale=1; $mb/1024" | bc)"
    else
        echo "${mb} Mo"
    fi
}

# Barre de progression simple
progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-40}"
    local pct=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    printf "\r${C_CYAN}[%s%s]${C_RESET} %3d%%" \
        "$(printf '#%.0s' $(seq 1 "$filled"))" \
        "$(printf '.%.0s' $(seq 1 "$empty"))" \
        "$pct"
}

# Attend avec un spinner jusqu'à ce qu'une condition soit vraie
wait_for() {
    local desc="$1"
    local check_fn="$2"
    local timeout="${3:-60}"
    local spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local elapsed=0

    echo -en "${C_CYAN}  En attente : $desc...${C_RESET} "
    while ! $check_fn; do
        printf "\r${C_CYAN}  En attente : $desc... ${spin_chars[$((i % 10))]}${C_RESET}"
        sleep 1
        (( elapsed++ ))
        (( i++ ))
        if (( elapsed >= timeout )); then
            echo ""
            log_warn "Timeout atteint ($timeout s) pour : $desc"
            return 1
        fi
    done
    echo -e "\r${C_BGREEN}  ✔ $desc${C_RESET}               "
    return 0
}

# =============================================================================
# CHARGEMENT DE LA CONFIGURATION
# =============================================================================

load_config() {
    local config_file="${1:-}"

    # Cherche config.conf dans l'ordre de priorité
    local candidates=(
        "${config_file}"
        "${PROXMOX_ADMIN_CONFIG:-}"
        "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/../config.conf"
        "/etc/proxmox-admin/config.conf"
        "$HOME/.proxmox-admin.conf"
    )

    local loaded=0
    for f in "${candidates[@]}"; do
        if [[ -n "$f" && -f "$f" ]]; then
            # shellcheck source=/dev/null
            source "$f"
            log_debug "Configuration chargée depuis : $f"
            loaded=1
            break
        fi
    done

    if (( loaded == 0 )); then
        log_warn "Aucun fichier config.conf trouvé, utilisation des valeurs par défaut."
    fi
}
