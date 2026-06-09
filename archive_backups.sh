#!/bin/bash

# ==============================================================================
# SCRIPT DE GESTION ET COMPRESSION DES ARCHIVES (À DEUX NIVEAUX)
# PROPRIÉTAIRE : Yannick Nzau (Antigravity AI Assistant)
# DESCRIPTION   : 
#   1. Niveau Local : Copie les sauvegardes depuis /backup/... vers /housekeeping/...,
#      les compresse en .gz et les regroupe dans des dossiers mensuels (AAAA-MM).
#   2. Niveau Distant : Synchronise le répertoire d'archivage local /housekeeping/...
#      vers le serveur d'archivage distant via rsync.
#   3. Nettoyage : Supprime les fichiers locaux du répertoire d'origine (/backup/...)
#      des mois précédents (seul le mois en cours est conservé localement).
# ==============================================================================

# Mode strict
set -euo pipefail

# Mode Simulation (Dry Run)
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "========================================= "
    echo "   MODE SIMULATION (DRY RUN) ACTIVÉ      "
    echo "========================================= "
fi

# Configuration de la connexion et des dossiers
ARCHIVE_SERVER="192.168.13.201"
ARCHIVE_USER="oracle"

# Répertoires d'origine (locaux)
SOURCES=(
    "/backup/rman/FULL_BD_DUMP/"
    "/backup/rman/ALL_ARCHIVE_LOGS/"
    "/backup/sauv_ap/"
    "/backup/sauv_av/"
)

# Répertoires d'archivage correspondants (locaux et distants)
DESTS=(
    "/housekeeping/rman/FULL_BD_DUMP/"
    "/housekeeping/rman/ALL_ARCHIVE_LOGS/"
    "/housekeeping/sauv_ap/"
    "/housekeeping/sauv_av/"
)

echo "Serveur d'archivage distant : $ARCHIVE_SERVER"
echo "Utilisateur distant        : $ARCHIVE_USER"

# Validation de la connexion SSH sans mot de passe
if [[ "$DRY_RUN" == "false" ]]; then
    echo "Validation de la connexion SSH sans mot de passe..."
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "echo 'SSH_OK'" >/dev/null 2>&1; then
        echo "ERREUR : Impossible de se connecter au serveur ${ARCHIVE_SERVER} via SSH sans mot de passe." >&2
        exit 1
    fi
    echo "Connexion SSH OK."
else
    echo "[Dry-Run] Connexion SSH simulée."
fi

CURRENT_MONTH=$(date +%Y-%m)
CURRENT_TIME=$(date +%s)

for i in "${!SOURCES[@]}"; do
    SRC_DIR="${SOURCES[$i]}"
    DST_DIR="${DESTS[$i]}"
    
    # Assurer les slashes de fin
    [[ "$SRC_DIR" != */ ]] && SRC_DIR="$SRC_DIR/"
    [[ "$DST_DIR" != */ ]] && DST_DIR="$DST_DIR/"
    
    echo "------------------------------------------------------------"
    echo "Traitement de la source : $SRC_DIR"
    echo "------------------------------------------------------------"
    
    if [[ ! -d "$SRC_DIR" ]]; then
        echo "ATTENTION : Le répertoire local d'origine $SRC_DIR n'existe pas. Passage au suivant."
        continue
    fi
    
    # S'assurer que le répertoire d'archivage local existe
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$DST_DIR"
    else
        echo "[Dry-Run] mkdir -p local : $DST_DIR"
    fi
    
    # Lister les fichiers locaux dans le dossier d'origine
    LOCAL_FILES=$(find "$SRC_DIR" -type f)
    
    if [[ -n "$LOCAL_FILES" ]]; then
        while IFS= read -r LOCAL_FILE; do
            REL_PATH="${LOCAL_FILE#$SRC_DIR}"
            LOCAL_SIZE=$(stat -c %s "$LOCAL_FILE")
            
            # Obtenir la date de modification du fichier
            FILE_MTIME=$(stat -c %Y "$LOCAL_FILE")
            FILE_MONTH=$(date -r "$LOCAL_FILE" +%Y-%m)
            
            # Sécurité : Éviter de traiter les fichiers modifiés il y a moins de 10 minutes
            AGE=$((CURRENT_TIME - FILE_MTIME))
            if [[ $AGE -lt 600 ]]; then
                echo "Skipping $REL_PATH : Fichier récemment modifié ou en cours d'écriture ($AGE secondes)."
                continue
            fi
            
            # Chemins d'archivage locaux
            LOCAL_UNCOMPRESSED_PATH="${DST_DIR}${REL_PATH}"
            LOCAL_COMPRESSED_PATH="${DST_DIR}${FILE_MONTH}/${REL_PATH}.gz"
            
            IS_ARCHIVED_LOCALLY=false
            
            # 1. Vérification si le fichier est déjà archivé et compressé localement
            if [[ -f "$LOCAL_COMPRESSED_PATH" ]]; then
                echo "Déjà archivé localement (compressé) : $REL_PATH dans $FILE_MONTH"
                IS_ARCHIVED_LOCALLY=true
            else
                # Archivage local temporaire (non compressé)
                echo "Archivage local requis pour : $REL_PATH"
                if [[ "$DRY_RUN" == "false" ]]; then
                    # S'assurer que le sous-dossier existe (pour préserver la hiérarchie)
                    mkdir -p "$(dirname "$LOCAL_UNCOMPRESSED_PATH")"
                    
                    # Copier le fichier localement
                    cp -f "$LOCAL_FILE" "$LOCAL_UNCOMPRESSED_PATH"
                    
                    # Vérification de la taille locale
                    COPY_SIZE=$(stat -c %s "$LOCAL_UNCOMPRESSED_PATH")
                    if [[ "$COPY_SIZE" -eq "$LOCAL_SIZE" ]]; then
                        # Compression locale
                        gzip -f "$LOCAL_UNCOMPRESSED_PATH"
                        
                        # Créer le répertoire mensuel local
                        mkdir -p "${DST_DIR}${FILE_MONTH}"
                        
                        # Déplacer le fichier compressé
                        mv -f "${LOCAL_UNCOMPRESSED_PATH}.gz" "${DST_DIR}${FILE_MONTH}/"
                        
                        if [[ -f "$LOCAL_COMPRESSED_PATH" ]]; then
                            echo "Archivage et compression locaux OK pour : $REL_PATH"
                            IS_ARCHIVED_LOCALLY=true
                        else
                            echo "ERREUR : Échec du déplacement du fichier compressé pour $REL_PATH." >&2
                        fi
                    else
                        echo "ERREUR : Échec de la copie locale pour $REL_PATH (différence de taille)." >&2
                    fi
                else
                    echo "[Dry-Run] cp $LOCAL_FILE vers $LOCAL_UNCOMPRESSED_PATH"
                    echo "[Dry-Run] gzip $LOCAL_UNCOMPRESSED_PATH"
                    echo "[Dry-Run] mv ${LOCAL_UNCOMPRESSED_PATH}.gz vers ${DST_DIR}${FILE_MONTH}/"
                    IS_ARCHIVED_LOCALLY=true
                fi
            fi
            
            # 2. Nettoyage local du répertoire d'origine si le fichier appartient à un mois précédent
            if [[ "$IS_ARCHIVED_LOCALLY" == "true" ]]; then
                if [[ "$FILE_MONTH" != "$CURRENT_MONTH" ]]; then
                    if [[ "$DRY_RUN" == "false" ]]; then
                        echo "Nettoyage d'origine : Suppression de $LOCAL_FILE (mois précédent : $FILE_MONTH)"
                        rm -f "$LOCAL_FILE"
                    else
                        echo "[Dry-Run] Nettoyage d'origine : Suppression de $LOCAL_FILE"
                    fi
                else
                    echo "Fichier d'origine conservé (mois en cours : $FILE_MONTH) : $REL_PATH"
                fi
            fi
            
        done <<< "$LOCAL_FILES"
    else
        echo "Aucun fichier local dans le dossier d'origine $SRC_DIR."
    fi
    
    # 3. Synchronisation vers le serveur d'archivage distant
    echo "Synchronisation de l'archive locale vers le serveur distant..."
    if [[ "$DRY_RUN" == "false" ]]; then
        # S'assurer que le répertoire cible existe sur le serveur distant
        ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "mkdir -p \"$DST_DIR\""
        
        # Lancement de rsync pour synchroniser le répertoire d'archivage
        if rsync -avz -e ssh "$DST_DIR" "${ARCHIVE_USER}@${ARCHIVE_SERVER}:${DST_DIR}"; then
            echo "Synchronisation distante réussie pour : $DST_DIR"
        else
            echo "ERREUR : Échec de la synchronisation distante via rsync pour $DST_DIR." >&2
        fi
    else
        echo "[Dry-Run] ssh mkdir -p $DST_DIR sur le serveur distant"
        echo "[Dry-Run] rsync -avz -e ssh $DST_DIR vers ${ARCHIVE_USER}@${ARCHIVE_SERVER}:${DST_DIR}"
    fi
    
done

echo "Processus d'archivage à deux niveaux terminé."
