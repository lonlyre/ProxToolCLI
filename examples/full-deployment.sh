#!/usr/bin/env bash
# =============================================================================
# examples/full-deployment.sh — Exemple complet de déploiement documenté
# =============================================================================
#
# Ce script illustre un cycle de vie complet :
#   1. Déploiement d'un serveur web (VM cloud-init)
#   2. Déploiement d'un service de monitoring (LXC)
#   3. Vérification de la connectivité
#   4. Snapshot avant configuration
#   5. Simulation d'une mise à jour et rollback
#   6. Nettoyage
#
# Prérequis :
#   - Un template cloud-init existant (VMID 9000)
#   - Un template LXC Debian disponible dans le stockage local
#   - Le fichier config.conf correctement configuré
#
# Usage :
#   chmod +x examples/full-deployment.sh
#   ./examples/full-deployment.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADMIN="${SCRIPT_DIR}/proxmox-admin.sh"

# Vérifie que le script principal est présent
if [[ ! -x "$ADMIN" ]]; then
    echo "[ERREUR] proxmox-admin.sh introuvable ou non exécutable : $ADMIN"
    exit 1
fi

# Couleurs simples pour ce script d'exemple
GREEN='\033[1;32m' CYAN='\033[0;36m' YELLOW='\033[1;33m' RESET='\033[0m'

step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}  ÉTAPE : $*${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

pause() {
    echo -e "${YELLOW}  [Appuyez sur Entrée pour continuer...]${RESET}"
    read -r
}

# =============================================================================
# VARIABLES DU SCÉNARIO
# =============================================================================
TEMPLATE_VMID=9000                        # VMID du template cloud-init
WEB_VMID=201                              # VMID du serveur web (VM)
MON_VMID=202                              # VMID du monitoring (LXC)
WEB_IP="192.168.1.201/24"
MON_IP="192.168.1.202/24"
GATEWAY="192.168.1.1"
LXC_TEMPLATE="local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║        Proxmox Admin — Exemple de déploiement complet       ║${RESET}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Scénario : Déploiement d'un stack web + monitoring"
echo "  VM web   : VMID $WEB_VMID — IP $WEB_IP"
echo "  LXC mon  : VMID $MON_VMID — IP $MON_IP"
echo ""
echo -e "${YELLOW}  NOTE : Ce script est en mode --yes (pas de confirmation interactive).${RESET}"
echo -e "${YELLOW}  Vérifiez que les VMIDs $WEB_VMID et $MON_VMID sont libres !${RESET}"
echo ""
pause

# =============================================================================
# ÉTAPE 1 — DÉPLOIEMENT DU SERVEUR WEB (VM cloud-init)
# =============================================================================
step "1/7 — Déploiement du serveur web (VM)"

"$ADMIN" --yes deploy --type vm-template \
    --vmid   "$WEB_VMID" \
    --name   "web-prod-01" \
    --template "$TEMPLATE_VMID" \
    --cpu    2 \
    --ram    2048 \
    --disk   30 \
    --ip     "$WEB_IP" \
    --gw     "$GATEWAY" \
    --dns    "8.8.8.8,8.8.4.4" \
    --tags   "web,production" \
    --sshkey "$HOME/.ssh/id_rsa.pub"

echo -e "${GREEN}  ✔ VM web-prod-01 (VMID $WEB_VMID) déployée${RESET}"
pause

# =============================================================================
# ÉTAPE 2 — DÉPLOIEMENT DU MONITORING (LXC)
# =============================================================================
step "2/7 — Déploiement du monitoring (LXC Debian)"

"$ADMIN" --yes deploy --type lxc \
    --vmid     "$MON_VMID" \
    --name     "monitoring-01" \
    --template "$LXC_TEMPLATE" \
    --cpu      1 \
    --ram      1024 \
    --swap     512 \
    --disk     10 \
    --ip       "$MON_IP" \
    --gw       "$GATEWAY" \
    --dns      "8.8.8.8" \
    --tags     "monitoring,production"

echo -e "${GREEN}  ✔ LXC monitoring-01 (VMID $MON_VMID) créé${RESET}"
pause

# =============================================================================
# ÉTAPE 3 — DÉMARRAGE DES MACHINES
# =============================================================================
step "3/7 — Démarrage de toutes les machines"

echo "  Démarrage de la VM web ($WEB_VMID)..."
"$ADMIN" lifecycle --action start --vmid "$WEB_VMID"

echo "  Démarrage du LXC monitoring ($MON_VMID)..."
"$ADMIN" lifecycle --action start --vmid "$MON_VMID"

echo ""
echo "  Attente de 30 secondes pour le boot + cloud-init..."
for i in $(seq 30 -1 1); do
    printf "\r  Attente : %2d secondes..." "$i"
    sleep 1
done
echo ""

echo -e "${GREEN}  ✔ Toutes les machines démarrées${RESET}"
pause

# =============================================================================
# ÉTAPE 4 — SUPERVISION & VÉRIFICATION
# =============================================================================
step "4/7 — Supervision et vérification de l'infrastructure"

echo "  === Liste de toutes les machines ==="
"$ADMIN" supervision list

echo ""
echo "  === Ressources détaillées : VM web ==="
"$ADMIN" supervision resources --vmid "$WEB_VMID"

echo ""
echo "  === Test de connectivité : VM web ==="
"$ADMIN" supervision check \
    --vmid "$WEB_VMID" \
    --ip   "${WEB_IP%%/*}"

echo ""
echo "  === Test de connectivité : LXC monitoring ==="
"$ADMIN" supervision check \
    --vmid "$MON_VMID" \
    --ip   "${MON_IP%%/*}"

pause

# =============================================================================
# ÉTAPE 5 — SNAPSHOT AVANT CONFIGURATION
# =============================================================================
step "5/7 — Snapshots 'pre-config' (avant mise en production)"

echo "  Snapshot de la VM web..."
"$ADMIN" snapshot create \
    --vmid "$WEB_VMID" \
    --name "pre-config" \
    --desc "Etat propre avant configuration applicative - $(date '+%Y-%m-%d')"

echo ""
echo "  Snapshot du LXC monitoring..."
"$ADMIN" snapshot create \
    --vmid "$MON_VMID" \
    --name "pre-config" \
    --desc "Etat propre avant installation Prometheus - $(date '+%Y-%m-%d')"

echo ""
echo "  === Liste des snapshots VM web ==="
"$ADMIN" snapshot list --vmid "$WEB_VMID"

pause

# =============================================================================
# ÉTAPE 6 — SIMULATION D'UN PROBLÈME ET ROLLBACK
# =============================================================================
step "6/7 — Simulation d'une mise à jour problématique + rollback"

echo "  [Simulation] Création d'un snapshot 'apres-maj-cassee'..."
"$ADMIN" snapshot create \
    --vmid "$WEB_VMID" \
    --name "apres-maj-cassee" \
    --desc "Simulation d'une mise a jour defectueuse"

echo ""
echo -e "${YELLOW}  [Simulation] La mise à jour a cassé le service !${RESET}"
echo "  Rollback vers le snapshot 'pre-config'..."
echo ""

"$ADMIN" --yes snapshot restore \
    --vmid "$WEB_VMID" \
    --name "pre-config"

echo ""
echo "  Redémarrage après rollback..."
"$ADMIN" lifecycle --action start --vmid "$WEB_VMID"

echo -e "${GREEN}  ✔ Rollback effectué avec succès${RESET}"
pause

# =============================================================================
# ÉTAPE 7 — BILAN FINAL ET NETTOYAGE DU SNAPSHOT CASSÉ
# =============================================================================
step "7/7 — Bilan et nettoyage"

echo "  === État final de l'infrastructure ==="
"$ADMIN" supervision list

echo ""
echo "  Nettoyage du snapshot 'apres-maj-cassee'..."
"$ADMIN" --yes snapshot delete \
    --vmid "$WEB_VMID" \
    --name "apres-maj-cassee"

echo ""
echo "  === Snapshots restants sur VM web ==="
"$ADMIN" snapshot list --vmid "$WEB_VMID"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║           Déploiement complet terminé avec succès !         ║${RESET}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Infrastructure déployée :"
echo "    • web-prod-01  (VM  VMID $WEB_VMID) — IP: ${WEB_IP%%/*}"
echo "    • monitoring-01 (LXC VMID $MON_VMID) — IP: ${MON_IP%%/*}"
echo ""
echo "  Commandes utiles :"
echo "    Voir l'état :   $ADMIN supervision list"
echo "    SSH web :       ssh debian@${WEB_IP%%/*}"
echo "    SSH monitoring: ssh root@${MON_IP%%/*}"
echo ""
echo "  Pour supprimer ce lab :"
echo "    $ADMIN --yes delete --vmid $WEB_VMID"
echo "    $ADMIN --yes delete --vmid $MON_VMID"
echo ""
