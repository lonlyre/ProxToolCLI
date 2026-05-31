# 🖥️ Proxmox Admin — Administration CLI complète

> Scripts Bash modulaires pour administrer une infrastructure Proxmox VE de A à Z, sans passer par l'interface web.

---

## 📋 Table des matières

- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Configuration](#configuration)
- [Structure du projet](#structure-du-projet)
- [Utilisation](#utilisation)
  - [Déploiement](#déploiement)
  - [Cycle de vie](#cycle-de-vie)
  - [Supervision](#supervision)
  - [Snapshots](#snapshots)
  - [Sauvegardes](#sauvegardes)
  - [Suppression](#suppression)
- [Exemple complet documenté](#exemple-complet-documenté)
- [Gestion des erreurs](#gestion-des-erreurs)
- [Journalisation](#journalisation)
- [Variables d'environnement](#variables-denvironnement)

---

## Fonctionnalités

| Module | Fonctionnalités |
|--------|----------------|
| **Deploy** | Clone VM depuis template cloud-init, création depuis ISO, déploiement LXC |
| **Lifecycle** | start, shutdown (ACPI), stop (forcé), reboot, suspend, resume, reset |
| **Supervision** | Listing avec statuts colorés, métriques CPU/RAM/disque temps réel, ping + SSH |
| **Snapshot** | Créer, lister, restaurer, supprimer des snapshots |
| **Backup** | Sauvegardes vzdump avec compression zstd |
| **Delete** | Suppression sécurisée avec double confirmation et retape du nom |

---

## Prérequis

- **Proxmox VE 7.x ou 8.x** sur le nœud cible
- Exécution directement sur le nœud (`root` requis)
- Commandes : `qm`, `pct`, `pvesh`, `vzdump` (incluses dans Proxmox)
- `bash` ≥ 4.3, `bc`, `ping`, `ssh` (optionnel pour supervision)

```bash
# Vérification rapide des dépendances
command -v qm pvesh pct vzdump bc
```

---

## Installation

```bash
# Cloner le dépôt sur le nœud Proxmox
git clone https://github.com/votre-org/proxmox-admin.git /opt/proxmox-admin
cd /opt/proxmox-admin

# Rendre les scripts exécutables
chmod +x proxmox-admin.sh
chmod +x lib/*.sh
chmod +x examples/*.sh

# (Optionnel) Lien symbolique global
ln -s /opt/proxmox-admin/proxmox-admin.sh /usr/local/bin/proxmox-admin

# Copier et adapter la configuration
cp config.conf config.local.conf
nano config.local.conf
```

---

## Configuration

Toute la configuration est centralisée dans `config.conf`. Copiez-le et adaptez :

```bash
# config.conf (extraits clés)

# Nœud Proxmox
PVE_NODE="pve"
PVE_HOST="192.168.1.10"

# Stockage
DEFAULT_STORAGE="local-lvm"
BACKUP_STORAGE="local"

# Réseau par défaut
DEFAULT_BRIDGE="vmbr0"
DEFAULT_GATEWAY="192.168.1.1"
DEFAULT_DNS="8.8.8.8,8.8.4.4"

# Défauts VM
VM_DEFAULT_CPU=2
VM_DEFAULT_RAM=2048
VM_DEFAULT_DISK=20

# Défauts LXC
LXC_DEFAULT_CPU=1
LXC_DEFAULT_RAM=512
```

**Surcharge par variable d'environnement** : toutes les variables de `config.conf` peuvent être surchargées :

```bash
export PVE_NODE=pve2
export DEFAULT_STORAGE=ceph
proxmox-admin supervision list
```

---

## Structure du projet

```
proxmox-admin/
├── proxmox-admin.sh        # Point d'entrée principal (dispatcher)
├── config.conf             # Configuration centralisée
├── lib/
│   ├── common.sh           # Fonctions partagées : logs, couleurs, helpers VMID
│   ├── deploy.sh           # Déploiement VM (template/ISO) et LXC
│   ├── lifecycle.sh        # Cycle de vie : start/stop/reboot/suspend/resume/reset
│   ├── supervision.sh      # Liste, ressources, connectivité
│   ├── snapshot.sh         # Snapshots et sauvegardes vzdump
│   └── delete.sh           # Suppression sécurisée
├── examples/
│   └── full-deployment.sh  # Exemple complet documenté
└── README.md
```

**Principe de modularité** : le script principal charge uniquement le module nécessaire. Chaque module peut aussi être chargé indépendamment (`source lib/deploy.sh`).

---

## Utilisation

### Aide

```bash
proxmox-admin help
proxmox-admin --version
```

### Options globales disponibles sur toutes les commandes

| Option | Description |
|--------|-------------|
| `--config FILE` | Fichier de configuration alternatif |
| `--node NODE` | Surcharge le nœud Proxmox |
| `--yes` / `-y` | Répondre oui à toutes les confirmations |
| `--no-color` | Désactiver les couleurs ANSI |
| `--debug` | Mode verbeux |

---

### Déploiement

#### VM depuis template cloud-init

```bash
proxmox-admin deploy --type vm-template \
  --name   "web-prod-01" \
  --template 9000 \
  --cpu    2 \
  --ram    2048 \
  --disk   30 \
  --ip     192.168.1.50/24 \
  --gw     192.168.1.1 \
  --dns    "8.8.8.8,8.8.4.4" \
  --user   debian \
  --sshkey ~/.ssh/id_rsa.pub \
  --tags   "web,production"
```

> **Pré-requis** : Avoir un template cloud-init (image Debian/Ubuntu configurée avec `--ide2 local:cloudinit`). 
> Si `--vmid` est omis, il est auto-assigné dans la plage `VMID_MIN`–`VMID_MAX`.

#### VM depuis ISO

```bash
proxmox-admin deploy --type vm-iso \
  --name  "windows-server" \
  --iso   "local:iso/win2022.iso" \
  --cpu   4 \
  --ram   4096 \
  --disk  80 \
  --bios  ovmf
```

#### Conteneur LXC

```bash
proxmox-admin deploy --type lxc \
  --name     "db-postgres" \
  --template "local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst" \
  --cpu      2 \
  --ram      1024 \
  --swap     512 \
  --disk     20 \
  --ip       192.168.1.60/24 \
  --gw       192.168.1.1 \
  --sshkey   ~/.ssh/id_rsa.pub
```

> Si `--password` est omis, un mot de passe root sécurisé est généré et affiché **une seule fois**.

---

### Cycle de vie

```bash
# Démarrer
proxmox-admin lifecycle --action start --vmid 101

# Arrêt propre (signal ACPI, attend l'arrêt complet)
proxmox-admin lifecycle --action shutdown --vmid 101

# Arrêt forcé (comme couper le courant)
proxmox-admin lifecycle --action stop --vmid 101

# Arrêt propre avec fallback forcé si timeout
proxmox-admin lifecycle --action shutdown --vmid 101 --force

# Redémarrer
proxmox-admin lifecycle --action reboot --vmid 101

# Suspendre sur disque (VMs uniquement)
proxmox-admin lifecycle --action suspend --vmid 101

# Reprendre depuis suspension
proxmox-admin lifecycle --action resume --vmid 101

# Reset matériel brutal (équivalent bouton reset)
proxmox-admin lifecycle --action reset --vmid 101
```

---

### Supervision

```bash
# Lister toutes les machines (VMs + LXC)
proxmox-admin supervision list

# Filtrer par type
proxmox-admin supervision list --type vm
proxmox-admin supervision list --type lxc

# Filtrer par statut
proxmox-admin supervision list --status running
proxmox-admin supervision list --status stopped

# Ressources détaillées d'une machine (config + métriques temps réel)
proxmox-admin supervision resources --vmid 101

# Vérification connectivité (ping + SSH + ports 80/443)
proxmox-admin supervision check --vmid 101
proxmox-admin supervision check --vmid 101 --ip 192.168.1.50 --user debian

# Infos complètes (ressources + connectivité)
proxmox-admin supervision info --vmid 101
```

**Exemple de sortie `supervision list` :**

```
══════════════════════════════════════════════════════════════════════
  Liste des machines — nœud : pve
══════════════════════════════════════════════════════════════════════
VMID   TYPE   NOM                       STATUT      CPU   RAM          DISQUE     IP
----------------------------------------------------------------------
101    VM     web-prod-01               running      12%   512 Mo/2048  30G        192.168.1.50
102    VM     db-postgres               stopped      -     -/4096 Mo    80G        -
201    LXC    monitoring-01             running       3%   128 Mo/512   10G        192.168.1.201
----------------------------------------------------------------------
  Total : 2 VM(s), 1 LXC(s) — 2 en cours d'exécution
```

---

### Snapshots

```bash
# Créer un snapshot (machine peut être running ou stopped)
proxmox-admin snapshot create \
  --vmid 101 \
  --name "avant-mise-a-jour" \
  --desc "Avant apt upgrade du $(date +%Y-%m-%d)"

# Avec sauvegarde de la RAM (VM uniquement, plus lent)
proxmox-admin snapshot create \
  --vmid 101 \
  --name "snapshot-complet" \
  --with-memory 1

# Lister les snapshots
proxmox-admin snapshot list --vmid 101

# Restaurer (la machine sera arrêtée si nécessaire)
proxmox-admin snapshot restore --vmid 101 --name "avant-mise-a-jour"

# Supprimer un snapshot
proxmox-admin snapshot delete --vmid 101 --name "snapshot-complet"
```

---

### Sauvegardes

```bash
# Créer une sauvegarde vzdump (mode snapshot = sans interruption)
proxmox-admin backup create --vmid 101

# Avec stockage et mode spécifiques
proxmox-admin backup create \
  --vmid    101 \
  --storage "backup-nas" \
  --mode    "snapshot" \
  --compress "zstd"

# Modes disponibles : snapshot (défaut), suspend, stop

# Lister les sauvegardes
proxmox-admin backup list
proxmox-admin backup list --vmid 101
```

---

### Suppression

```bash
# Suppression avec double confirmation (retape le nom)
proxmox-admin delete --vmid 101

# Avec suppression des disques non référencés
proxmox-admin delete --vmid 101 --purge-disk

# Mode automatique (scripts CI/CD) — DANGEREUX
proxmox-admin --yes delete --vmid 101 --force
```

> La suppression effectue automatiquement : arrêt → suppression snapshots → destruction.
> Une trace est écrite dans le fichier de log avec l'opérateur et l'horodatage.

---

## Exemple complet documenté

Le script `examples/full-deployment.sh` démontre un cycle complet :

```bash
# Lire le script avant de l'exécuter !
cat examples/full-deployment.sh

# Adapter les variables en tête du script
nano examples/full-deployment.sh

# Exécuter
chmod +x examples/full-deployment.sh
./examples/full-deployment.sh
```

**Scénario couvert :**

1. Déploiement VM serveur web (clone template cloud-init)
2. Déploiement LXC monitoring (Debian)
3. Démarrage des deux machines
4. Attente du boot + vérification connectivité
5. Snapshot `pre-config` sur les deux machines
6. Simulation d'une mise à jour problématique
7. Rollback vers le snapshot propre
8. Bilan final et nettoyage

---

## Gestion des erreurs

Tous les scripts utilisent `set -euo pipefail` et une gestion explicite des codes de retour :

| Code | Signification |
|------|---------------|
| 0 | Succès |
| 1 | Erreur générale / commande échouée |
| 2 | Pas sur un nœud Proxmox |
| 3 | Pas root |
| 4 | Dépendances manquantes |
| 5 | Pas de VMID disponible |
| 10 | Module introuvable |
| 130 | Interruption (Ctrl+C) |

Les messages d'erreur sont explicites et écrits sur `stderr` avec préfixe `[ERROR]`.

---

## Journalisation

Les logs sont écrits dans `$LOG_FILE` (défaut : `/var/log/proxmox-admin/proxmox-admin.log`) :

```
[2025-01-15 14:32:01] [INFO] Déploiement VM depuis template (cloud-init)
[2025-01-15 14:32:05] [INFO] [SUCCESS] Clone créé.
[2025-01-15 14:33:12] [INFO] [SUCCESS] VM web-prod-01 (VMID 101) déployée avec succès.
[2025-01-15 15:10:44] [INFO] SUPPRESSION: VMID=105 NAME=test-vm TYPE=qemu par root le mer. 15 janv.
```

Niveaux : `DEBUG`, `INFO`, `WARN`, `ERROR` (configurable via `LOG_LEVEL`).

---

## Variables d'environnement

Toutes les variables de `config.conf` peuvent être surchargées :

```bash
# Exemples
export PVE_NODE=pve2                    # Nœud cible
export DEFAULT_STORAGE=ceph-pool        # Stockage
export CONFIRM_DESTRUCTIVE=0            # Désactiver confirmations
export LOG_LEVEL=DEBUG                  # Mode verbeux
export TIMEOUT_START=180                # Timeout démarrage

proxmox-admin supervision list
```

---

## Contribuer

1. Forkez le dépôt
2. Créez une branche feature (`git checkout -b feature/ma-fonctionnalite`)
3. Committez avec des messages clairs
4. Vérifiez avec `shellcheck` :
   ```bash
   shellcheck proxmox-admin.sh lib/*.sh
   ```
5. Soumettez une Pull Request

---

## Licence

MIT — Libre d'utilisation, de modification et de distribution.
