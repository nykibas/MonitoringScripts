#!/bin/bash

# ==============================================================================
# SCRIPT DE GESTION ET COMPRESSION DES ARCHIVES (À DEUX NIVEAUX)
# PROPRIÉTAIRE : Yannick Nzau (Antigravity AI Assistant)
# DESCRIPTION   : 
#   1. Compression Initiale : Compresse les sauvegardes sur place (.gz) dans /backup/...
#   2. Niveau Local (Niveau 1) : Copie les sauvegardes compressées directement
#      dans leur sous-dossier mensuel d'archivage local (ex: /housekeeping/.../AAAA-MM/).
#   3. Niveau Distant (Niveau 2) : Synchronise le répertoire d'archivage local
#      /housekeeping/... vers le serveur d'archivage distant via rsync.
#   4. Nettoyage : Supprime les fichiers gzippés du répertoire d'origine (/backup/...)
#      des mois précédents (seul le mois en cours est conservé localement).
# ==============================================================================

# Mode strict
set -eo pipefail

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
    LOCAL_FILES=$(find "$SRC_DIR" -type f 2>/dev/null || true)
    
    if [[ -n "$LOCAL_FILES" ]]; then
        while IFS= read -r LOCAL_FILE; do
            if [[ -z "$LOCAL_FILE" ]]; then
                continue
            fi
            
            # S'assurer que le fichier existe toujours
            if [[ ! -f "$LOCAL_FILE" ]]; then
                continue
            fi
            
            # Obtenir l'âge du fichier
            FILE_MTIME=$(stat -c %Y "$LOCAL_FILE")
            AGE=$((CURRENT_TIME - FILE_MTIME))
            if [[ $AGE -lt 600 ]]; then
                echo "Skipping $(basename "$LOCAL_FILE") : Fichier récemment modifié ou en cours d'écriture ($AGE secondes)."
                continue
            fi
            
            # Déterminer le mois à partir du nom du fichier d'origine, sinon fallback date de modification
            BASE_NAME=$(basename "$LOCAL_FILE")
            # Enlever l'extension .gz si présente pour l'extraction de la date
            NAME_FOR_DATE="${BASE_NAME%.gz}"
            DATE_STR=$(echo "$NAME_FOR_DATE" | grep -o -E '20[0-9]{6}' | head -n 1 || true)
            
            FILE_MONTH=""
            if [[ -n "$DATE_STR" ]]; then
                YEAR="${DATE_STR:0:4}"
                MONTH="${DATE_STR:4:2}"
                if [[ "$MONTH" -ge 1 && "$MONTH" -le 12 ]]; then
                    FILE_MONTH="${YEAR}-${MONTH}"
                else
                    FILE_MONTH=$(date -r "$LOCAL_FILE" +%Y-%m)
                fi
            else
                FILE_MONTH=$(date -r "$LOCAL_FILE" +%Y-%m)
            fi
            
            WORKING_FILE="$LOCAL_FILE"
            IS_COMPRESSED=false
            if [[ "$LOCAL_FILE" == *.gz ]]; then
                IS_COMPRESSED=true
            fi
            
            # 1. Compression sur place dans le dossier d'origine si non compressé
            if [[ "$IS_COMPRESSED" == "false" ]]; then
                echo "-> Compression initiale de $BASE_NAME sur la source..."
                if [[ "$DRY_RUN" == "false" ]]; then
                    gzip -f "$WORKING_FILE"
                    WORKING_FILE="${WORKING_FILE}.gz"
                else
                    echo "[Dry-Run] gzip -f \"$WORKING_FILE\""
                    WORKING_FILE="${WORKING_FILE}.gz"
                fi
            fi
            
            # Mettre à jour le chemin relatif et le nom compressé
            REL_PATH="${WORKING_FILE#$SRC_DIR}"
            LOCAL_COMPRESSED_PATH="${DST_DIR}${FILE_MONTH}/${REL_PATH}"
            is_archived_locally=false
            
            # 2. Vérification si le fichier compressé existe déjà dans l'archive locale
            if [[ -f "$LOCAL_COMPRESSED_PATH" ]]; then
                echo "Déjà archivé localement (compressé) : $REL_PATH dans $FILE_MONTH"
                is_archived_locally=true
            else
                # Copie directe vers le dossier d'archivage mensuel local
                echo "Copie vers l'archive locale : $REL_PATH -> $FILE_MONTH/"
                if [[ "$DRY_RUN" == "false" ]]; then
                    # Créer le répertoire mensuel local
                    mkdir -p "$(dirname "$LOCAL_COMPRESSED_PATH")"
                    
                    # Copier le fichier compressé
                    cp -f "$WORKING_FILE" "$LOCAL_COMPRESSED_PATH"
                    
                    # Vérification de la taille
                    ORIG_SIZE=$(stat -c %s "$WORKING_FILE")
                    COPY_SIZE=$(stat -c %s "$LOCAL_COMPRESSED_PATH")
                    
                    if [[ "$COPY_SIZE" -eq "$ORIG_SIZE" ]]; then
                        echo "Copie locale OK pour : $REL_PATH"
                        is_archived_locally=true
                    else
                        echo "ERREUR : Échec de la copie locale pour $REL_PATH (différence de taille)." >&2
                    fi
                else
                    echo "[Dry-Run] mkdir -p \"$(dirname "$LOCAL_COMPRESSED_PATH")\""
                    echo "[Dry-Run] cp -f \"$WORKING_FILE\" vers \"$LOCAL_COMPRESSED_PATH\""
                    is_archived_locally=true
                fi
            fi
            
            # 3. Nettoyage du répertoire d'origine si le fichier appartient à un mois précédent
            if [[ "$is_archived_locally" == "true" ]]; then
                if [[ "$FILE_MONTH" != "$CURRENT_MONTH" ]]; then
                    if [[ "$DRY_RUN" == "false" ]]; then
                        echo "Nettoyage d'origine : Suppression de $WORKING_FILE (mois précédent : $FILE_MONTH)"
                        rm -f "$WORKING_FILE"
                    else
                        echo "[Dry-Run] Nettoyage d'origine : Suppression de $WORKING_FILE"
                    fi
                else
                    echo "Fichier d'origine conservé (mois en cours : $FILE_MONTH) : $REL_PATH"
                fi
            fi
            
        done <<< "$LOCAL_FILES"
    else
        echo "Aucun fichier local dans le dossier d'origine $SRC_DIR."
    fi
    
    # 4. Synchronisation vers le serveur d'archivage distant
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
