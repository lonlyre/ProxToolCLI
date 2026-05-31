#!/usr/bin/env bash
# =============================================================================
# lib/deploy.sh — Déploiement de VMs et conteneurs LXC
# =============================================================================
# Fonctions :
#   deploy_vm_from_template  — Clone une VM depuis un template cloud-init
#   deploy_vm_from_iso       — Crée une VM vierge depuis une ISO
#   deploy_lxc               — Crée un conteneur LXC depuis un template

[[ -n "${_DEPLOY_LOADED:-}" ]] && return 0
_DEPLOY_LOADED=1

# =============================================================================
# DÉPLOIEMENT VM — DEPUIS UN TEMPLATE CLOUD-INIT
# =============================================================================
# Usage : deploy_vm_from_template [options]
#
# Options :
#   --vmid       VMID cible (auto si omis)
#   --name       Nom de la VM
#   --template   VMID du template source
#   --cpu        Nombre de vCPU  (défaut: $VM_DEFAULT_CPU)
#   --ram        RAM en Mo       (défaut: $VM_DEFAULT_RAM)
#   --disk       Taille disque en Go (défaut: $VM_DEFAULT_DISK)
#   --storage    Stockage cible  (défaut: $DEFAULT_STORAGE)
#   --bridge     Bridge réseau   (défaut: $DEFAULT_BRIDGE)
#   --ip         IP statique CIDR (ex: 192.168.1.50/24) ou "dhcp"
#   --gw         Passerelle      (défaut: $DEFAULT_GATEWAY)
#   --dns        Serveurs DNS    (défaut: $DEFAULT_DNS)
#   --user       Utilisateur cloud-init
#   --sshkey     Chemin clé SSH publique
#   --tags       Tags Proxmox (virgule)
# =============================================================================
deploy_vm_from_template() {
    log_section "Déploiement VM depuis template (cloud-init)"

    # --- Parsing des arguments ---
    local vmid="" name="" template="" cpu="" ram="" disk="" storage=""
    local bridge="" ip="dhcp" gw="" dns="" user="" sshkey="" tags=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid)     vmid="$2";     shift 2 ;;
            --name)     name="$2";     shift 2 ;;
            --template) template="$2"; shift 2 ;;
            --cpu)      cpu="$2";      shift 2 ;;
            --ram)      ram="$2";      shift 2 ;;
            --disk)     disk="$2";     shift 2 ;;
            --storage)  storage="$2";  shift 2 ;;
            --bridge)   bridge="$2";   shift 2 ;;
            --ip)       ip="$2";       shift 2 ;;
            --gw)       gw="$2";       shift 2 ;;
            --dns)      dns="$2";      shift 2 ;;
            --user)     user="$2";     shift 2 ;;
            --sshkey)   sshkey="$2";   shift 2 ;;
            --tags)     tags="$2";     shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    # --- Validation des paramètres obligatoires ---
    [[ -z "$name"     ]] && name=$(prompt_value "Nom de la VM")
    [[ -z "$template" ]] && template=$(prompt_value "VMID du template source")
    [[ -z "$name"     ]] && die "Le nom de la VM est obligatoire."
    [[ -z "$template" ]] && die "Le VMID du template est obligatoire."

    # --- Valeurs par défaut ---
    cpu="${cpu:-${VM_DEFAULT_CPU:-2}}"
    ram="${ram:-${VM_DEFAULT_RAM:-2048}}"
    disk="${disk:-${VM_DEFAULT_DISK:-20}}"
    storage="${storage:-${DEFAULT_STORAGE:-local-lvm}}"
    bridge="${bridge:-${DEFAULT_BRIDGE:-vmbr0}}"
    gw="${gw:-${DEFAULT_GATEWAY:-}}"
    dns="${dns:-${DEFAULT_DNS:-8.8.8.8}}"
    user="${user:-${CI_DEFAULT_USER:-debian}}"
    sshkey="${sshkey:-${CI_DEFAULT_SSH_KEY:-}}"

    # --- VMID automatique ---
    if [[ -z "$vmid" ]]; then
        vmid=$(next_vmid)
        log_info "VMID auto-assigné : $vmid"
    fi

    # --- Vérifications préalables ---
    if vmid_exists "$vmid"; then
        die "VMID $vmid déjà utilisé."
    fi
    if ! qm status "$template" &>/dev/null; then
        die "Template VMID $template introuvable ou pas une VM."
    fi

    # --- Résumé ---
    log_info "Paramètres du déploiement :"
    echo -e "  ${C_BOLD}VMID      :${C_RESET} $vmid"
    echo -e "  ${C_BOLD}Nom       :${C_RESET} $name"
    echo -e "  ${C_BOLD}Template  :${C_RESET} $vmid_template → $template"
    echo -e "  ${C_BOLD}CPU       :${C_RESET} $cpu vCPU"
    echo -e "  ${C_BOLD}RAM       :${C_RESET} $(format_mem "$ram")"
    echo -e "  ${C_BOLD}Disque    :${C_RESET} ${disk} Go sur $storage"
    echo -e "  ${C_BOLD}Réseau    :${C_RESET} $bridge — IP: $ip"
    [[ -n "$gw"   ]] && echo -e "  ${C_BOLD}Passerelle:${C_RESET} $gw"
    echo -e "  ${C_BOLD}DNS       :${C_RESET} $dns"
    echo ""

    confirm "Lancer le déploiement ?" "y" || { log_info "Déploiement annulé."; return 0; }

    # --- Étape 1 : Clonage du template ---
    log_info "[1/5] Clonage du template $template → VMID $vmid..."
    if ! qm clone "$template" "$vmid" \
            --name "$name" \
            --storage "$storage" \
            --full 1; then
        die "Échec du clonage du template $template."
    fi
    log_success "Clone créé."

    # --- Étape 2 : Configuration matérielle ---
    log_info "[2/5] Configuration CPU / RAM..."
    qm set "$vmid" \
        --cores "$cpu" \
        --memory "$ram" \
        --balloon 0 \
        --agent enabled=1 \
        || die "Échec configuration matérielle."
    log_success "CPU/RAM configurés."

    # --- Étape 3 : Redimensionnement disque ---
    log_info "[3/5] Redimensionnement du disque système à ${disk}G..."
    # On resize scsi0 (disque principal du template)
    qm resize "$vmid" scsi0 "${disk}G" &>/dev/null \
        || log_warn "Redimensionnement ignoré (peut-être déjà à la bonne taille)."
    log_success "Disque configuré."

    # --- Étape 4 : Réseau ---
    log_info "[4/5] Configuration réseau..."
    local net_str="virtio,bridge=${bridge}"
    [[ -n "${DEFAULT_VLAN:-}" ]] && net_str="${net_str},tag=${DEFAULT_VLAN}"
    qm set "$vmid" --net0 "$net_str" || die "Échec configuration réseau."

    # Cloud-init IP
    local ipconfig="ip=${ip}"
    [[ "$ip" == "dhcp" ]] && ipconfig="ip=dhcp"
    [[ "$ip" != "dhcp" && -n "$gw" ]] && ipconfig="${ipconfig},gw=${gw}"
    qm set "$vmid" --ipconfig0 "$ipconfig" || die "Échec ipconfig cloud-init."
    log_success "Réseau configuré."

    # --- Étape 5 : Cloud-Init ---
    log_info "[5/5] Injection cloud-init (utilisateur, clé SSH, DNS)..."
    qm set "$vmid" \
        --ciuser "$user" \
        --nameserver "${dns//,/ }" \
        --searchdomain "${DEFAULT_SEARCH_DOMAIN:-local.lan}" \
        || die "Échec cloud-init base."

    if [[ -n "$sshkey" && -f "$sshkey" ]]; then
        qm set "$vmid" --sshkeys "$sshkey" \
            || log_warn "Impossible d'injecter la clé SSH : $sshkey"
    fi

    if [[ "${CI_UPGRADE:-1}" == "1" ]]; then
        qm set "$vmid" --ciupgrade 1 || true
    fi

    [[ -n "$tags" ]] && qm set "$vmid" --tags "$tags" || true

    log_success "Cloud-init configuré."
    log_separator
    log_success "VM $name (VMID $vmid) déployée avec succès."
    echo -e "  → Démarrez avec : ${C_CYAN}proxmox-admin.sh lifecycle --action start --vmid $vmid${C_RESET}"
}


# =============================================================================
# DÉPLOIEMENT VM — DEPUIS ISO
# =============================================================================
# Usage : deploy_vm_from_iso [options]
#
# Options : mêmes que deploy_vm_from_template, sauf --template
#   --iso        Chemin ISO dans le stockage (ex: local:iso/debian-12.iso)
#   --boot-disk  Taille du disque de boot en Go
# =============================================================================
deploy_vm_from_iso() {
    log_section "Déploiement VM depuis ISO"

    local vmid="" name="" iso="" cpu="" ram="" disk="" storage=""
    local bridge="" ip="dhcp" gw="" dns="" tags="" bios="" machine=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid)      vmid="$2";     shift 2 ;;
            --name)      name="$2";     shift 2 ;;
            --iso)       iso="$2";      shift 2 ;;
            --cpu)       cpu="$2";      shift 2 ;;
            --ram)       ram="$2";      shift 2 ;;
            --disk)      disk="$2";     shift 2 ;;
            --storage)   storage="$2";  shift 2 ;;
            --bridge)    bridge="$2";   shift 2 ;;
            --ip)        ip="$2";       shift 2 ;;
            --gw)        gw="$2";       shift 2 ;;
            --bios)      bios="$2";     shift 2 ;;
            --tags)      tags="$2";     shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    # Valeurs obligatoires
    [[ -z "$name" ]] && name=$(prompt_value "Nom de la VM")
    [[ -z "$iso"  ]] && iso=$(prompt_value "Chemin ISO (ex: local:iso/debian-12.iso)")
    [[ -z "$name" ]] && die "Nom obligatoire."
    [[ -z "$iso"  ]] && die "ISO obligatoire."

    # Valeurs par défaut
    cpu="${cpu:-${VM_DEFAULT_CPU:-2}}"
    ram="${ram:-${VM_DEFAULT_RAM:-2048}}"
    disk="${disk:-${VM_DEFAULT_DISK:-20}}"
    storage="${storage:-${DEFAULT_STORAGE:-local-lvm}}"
    bridge="${bridge:-${DEFAULT_BRIDGE:-vmbr0}}"
    bios="${bios:-${VM_DEFAULT_BIOS:-seabios}}"
    machine="${machine:-${VM_DEFAULT_MACHINE:-q35}}"

    # VMID
    [[ -z "$vmid" ]] && vmid=$(next_vmid) && log_info "VMID auto : $vmid"
    vmid_exists "$vmid" && die "VMID $vmid déjà utilisé."

    # Résumé
    log_info "Paramètres :"
    echo -e "  VMID: $vmid | Nom: $name | ISO: $iso"
    echo -e "  CPU: $cpu | RAM: $(format_mem "$ram") | Disque: ${disk}G sur $storage"
    echo -e "  BIOS: $bios | Machine: $machine | Bridge: $bridge"

    confirm "Créer la VM ?" "y" || { log_info "Annulé."; return 0; }

    log_info "[1/4] Création de la VM..."
    qm create "$vmid" \
        --name "$name" \
        --cores "$cpu" \
        --memory "$ram" \
        --bios "$bios" \
        --machine "$machine" \
        --ostype "${VM_DEFAULT_OSTYPE:-l26}" \
        --cdrom "$iso" \
        --boot "order=ide2;scsi0" \
        --agent enabled=1 \
        || die "Échec création VM."
    log_success "VM créée."

    log_info "[2/4] Création du disque système (${disk}G)..."
    qm set "$vmid" \
        --scsi0 "${storage}:${disk},format=qcow2" \
        --scsihw virtio-scsi-pci \
        || die "Échec création disque."
    log_success "Disque créé."

    log_info "[3/4] Configuration réseau..."
    local net_str="virtio,bridge=${bridge}"
    [[ -n "${DEFAULT_VLAN:-}" ]] && net_str="${net_str},tag=${DEFAULT_VLAN}"
    qm set "$vmid" \
        --net0 "$net_str" \
        --tablet 0 \
        || die "Échec réseau."
    log_success "Réseau configuré."

    log_info "[4/4] Finalisation..."
    [[ -n "$tags" ]] && qm set "$vmid" --tags "$tags" || true
    log_success "VM $name (VMID $vmid) prête. Démarrez et installez l'OS via VNC/console."
}


# =============================================================================
# DÉPLOIEMENT LXC
# =============================================================================
# Usage : deploy_lxc [options]
#
# Options :
#   --vmid       VMID cible (auto si omis)
#   --name       Hostname du conteneur
#   --template   Template LXC (ex: local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst)
#   --cpu        Nombre de vCPU
#   --ram        RAM en Mo
#   --swap       SWAP en Mo
#   --disk       Taille du rootfs en Go
#   --storage    Stockage cible
#   --bridge     Bridge réseau
#   --ip         IP statique CIDR ou "dhcp"
#   --gw         Passerelle
#   --dns        DNS
#   --password   Mot de passe root (ou sera généré)
#   --sshkey     Clé SSH publique
#   --unpriv     1 (défaut) = non privilégié
#   --tags       Tags Proxmox
# =============================================================================
deploy_lxc() {
    log_section "Déploiement conteneur LXC"

    local vmid="" name="" template="" cpu="" ram="" swap="" disk="" storage=""
    local bridge="" ip="dhcp" gw="" dns="" password="" sshkey="" unpriv="" tags=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmid)     vmid="$2";     shift 2 ;;
            --name)     name="$2";     shift 2 ;;
            --template) template="$2"; shift 2 ;;
            --cpu)      cpu="$2";      shift 2 ;;
            --ram)      ram="$2";      shift 2 ;;
            --swap)     swap="$2";     shift 2 ;;
            --disk)     disk="$2";     shift 2 ;;
            --storage)  storage="$2";  shift 2 ;;
            --bridge)   bridge="$2";   shift 2 ;;
            --ip)       ip="$2";       shift 2 ;;
            --gw)       gw="$2";       shift 2 ;;
            --dns)      dns="$2";      shift 2 ;;
            --password) password="$2"; shift 2 ;;
            --sshkey)   sshkey="$2";   shift 2 ;;
            --unpriv)   unpriv="$2";   shift 2 ;;
            --tags)     tags="$2";     shift 2 ;;
            *) die "Paramètre inconnu : $1" ;;
        esac
    done

    # Valeurs obligatoires
    [[ -z "$name"     ]] && name=$(prompt_value "Hostname du conteneur")
    [[ -z "$template" ]] && template=$(prompt_value "Template LXC")
    [[ -z "$name"     ]] && die "Hostname obligatoire."
    [[ -z "$template" ]] && die "Template obligatoire."

    # Valeurs par défaut
    cpu="${cpu:-${LXC_DEFAULT_CPU:-1}}"
    ram="${ram:-${LXC_DEFAULT_RAM:-512}}"
    swap="${swap:-${LXC_DEFAULT_SWAP:-512}}"
    disk="${disk:-${LXC_DEFAULT_DISK:-8}}"
    storage="${storage:-${DEFAULT_STORAGE:-local-lvm}}"
    bridge="${bridge:-${DEFAULT_BRIDGE:-vmbr0}}"
    gw="${gw:-${DEFAULT_GATEWAY:-}}"
    dns="${dns:-${DEFAULT_DNS:-8.8.8.8}}"
    unpriv="${unpriv:-${LXC_DEFAULT_UNPRIVILEGED:-1}}"

    # Génère un mot de passe si non fourni
    if [[ -z "$password" ]]; then
        password=$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 20)
        log_warn "Mot de passe root auto-généré : ${C_BOLD}$password${C_RESET}"
        log_warn "Notez-le ! Il ne sera plus affiché."
    fi

    # VMID automatique
    [[ -z "$vmid" ]] && vmid=$(next_vmid) && log_info "VMID auto : $vmid"
    vmid_exists "$vmid" && die "VMID $vmid déjà utilisé."

    # Construction de la chaîne réseau
    local net_str="name=eth0,bridge=${bridge}"
    if [[ "$ip" == "dhcp" ]]; then
        net_str="${net_str},ip=dhcp"
    else
        net_str="${net_str},ip=${ip}"
        [[ -n "$gw" ]] && net_str="${net_str},gw=${gw}"
    fi
    [[ -n "${DEFAULT_VLAN:-}" ]] && net_str="${net_str},tag=${DEFAULT_VLAN}"

    # Résumé
    log_info "Paramètres du conteneur :"
    echo -e "  ${C_BOLD}VMID      :${C_RESET} $vmid"
    echo -e "  ${C_BOLD}Hostname  :${C_RESET} $name"
    echo -e "  ${C_BOLD}Template  :${C_RESET} $template"
    echo -e "  ${C_BOLD}CPU       :${C_RESET} $cpu vCPU"
    echo -e "  ${C_BOLD}RAM       :${C_RESET} $(format_mem "$ram") + SWAP $(format_mem "$swap")"
    echo -e "  ${C_BOLD}Disque    :${C_RESET} ${disk}G sur $storage"
    echo -e "  ${C_BOLD}Réseau    :${C_RESET} $net_str"
    echo -e "  ${C_BOLD}Non-priv  :${C_RESET} $unpriv"
    echo ""

    confirm "Créer le conteneur ?" "y" || { log_info "Annulé."; return 0; }

    log_info "[1/2] Création du conteneur LXC..."
    local pct_args=(
        pct create "$vmid" "$template"
        --hostname "$name"
        --cores "$cpu"
        --memory "$ram"
        --swap "$swap"
        --rootfs "${storage}:${disk}"
        --net0 "$net_str"
        --nameserver "${dns//,/ }"
        --searchdomain "${DEFAULT_SEARCH_DOMAIN:-local.lan}"
        --password "$password"
        --unprivileged "$unpriv"
        --onboot 0
        --start 0
    )

    # Clé SSH optionnelle
    if [[ -n "$sshkey" && -f "$sshkey" ]]; then
        pct_args+=(--ssh-public-keys "$sshkey")
    fi

    [[ -n "$tags" ]] && pct_args+=(--tags "$tags")

    if ! "${pct_args[@]}"; then
        die "Échec de la création du conteneur LXC $vmid."
    fi
    log_success "Conteneur LXC créé."

    log_info "[2/2] Configuration supplémentaire..."
    # Active le nesting pour Docker-in-LXC si non privilégié
    if [[ "$unpriv" == "1" ]]; then
        pct set "$vmid" --features nesting=1 || true
    fi

    log_separator
    log_success "Conteneur $name (VMID $vmid) créé avec succès."
    echo -e "  → Démarrez avec : ${C_CYAN}proxmox-admin.sh lifecycle --action start --vmid $vmid${C_RESET}"
}
