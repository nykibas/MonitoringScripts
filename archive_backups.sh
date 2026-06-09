#!/bin/bash

# ==============================================================================
# SCRIPT DE GESTION ET COMPRESSION DES ARCHIVES
# PROPRIÉTAIRE : Yannick Nzau (Antigravity AI Assistant)
# DESCRIPTION   : Lit folders_to_sync.txt, transfère les fichiers vers le serveur
#                 d'archivage distant via rsync, vérifie la présence et la taille,
#                 puis compresse (gzip) et regroupe mensuellement (AAAA-MM) sur le 
#                 serveur distant. Supprime ensuite les fichiers locaux des mois
#                 précédents (ne garde que le mois en cours localement).
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

# Fichier de configuration
CONFIG_FILE="folders_to_sync.txt"

if [[ ! -f "$CONFIG_FILE" ]]; then
    # Essayer de trouver le fichier dans le dossier courant ou le répertoire parent
    if [[ -f "d:/MonitoringScripts/folders_to_sync.txt" ]]; then
        CONFIG_FILE="d:/MonitoringScripts/folders_to_sync.txt"
    elif [[ -f "/u01/app/oracle/folders_to_sync.txt" ]]; then
        CONFIG_FILE="/u01/app/oracle/folders_to_sync.txt"
    elif [[ -f "/backup/folders_to_sync.txt" ]]; then
        CONFIG_FILE="/backup/folders_to_sync.txt"
    else
        echo "ERREUR : Fichier de configuration $CONFIG_FILE introuvable." >&2
        exit 1
    fi
fi

echo "Lecture de la configuration depuis: $CONFIG_FILE"

# Extraction des informations de connexion
ARCHIVE_SERVER=$(grep "Servers d'archivage" "$CONFIG_FILE" | cut -d':' -f2- | xargs)
ARCHIVE_USER=$(grep "username" "$CONFIG_FILE" | cut -d':' -f2- | xargs)

if [[ -z "$ARCHIVE_SERVER" || -z "$ARCHIVE_USER" ]]; then
    echo "ERREUR : Impossible de lire les informations du serveur d'archivage ou d'utilisateur." >&2
    exit 1
fi

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

# Récupération des dossiers d'origine et d'archivage
SOURCES=($(awk "/Dossiers d'origine:/ {flag=1; next} /Dossiers d'archivage:/ {flag=0} flag && /^-/ {print \$2}" "$CONFIG_FILE"))
DESTS=($(awk "/Dossiers d'archivage:/ {flag=1; next} /Servers d'archivage:/ {flag=0} flag && /^-/ {print \$2}" "$CONFIG_FILE"))

if [[ ${#SOURCES[@]} -eq 0 || ${#DESTS[@]} -eq 0 || ${#SOURCES[@]} -ne ${#DESTS[@]} ]]; then
    echo "ERREUR : Incohérence dans les dossiers d'origine et d'archivage dans $CONFIG_FILE." >&2
    exit 1
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
    echo "Traitement : $SRC_DIR ===> ${ARCHIVE_USER}@${ARCHIVE_SERVER}:$DST_DIR"
    echo "------------------------------------------------------------"
    
    if [[ ! -d "$SRC_DIR" ]]; then
        echo "ATTENTION : Le répertoire local $SRC_DIR n'existe pas. Passage au suivant."
        continue
    fi
    
    # S'assurer que le répertoire d'archivage de base existe sur le serveur distant
    if [[ "$DRY_RUN" == "false" ]]; then
        ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "mkdir -p \"$DST_DIR\""
    else
        echo "[Dry-Run] mkdir -p \"$DST_DIR\" sur le serveur distant."
    fi
    
    # Inventaire de tous les fichiers distants (chemin et taille) pour optimiser
    echo "Inventaire des fichiers archivés distants..."
    if [[ "$DRY_RUN" == "false" ]]; then
        # Exécute find et stat pour avoir tous les fichiers existants sous DST_DIR
        REMOTE_INVENTORY=$(ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "find \"$DST_DIR\" -type f -exec stat -c '%n:%s' {} +" 2>/dev/null || true)
    else
        REMOTE_INVENTORY=""
    fi
    
    # Fonction locale de recherche dans l'inventaire distant
    get_remote_size() {
        local path="$1"
        echo "$REMOTE_INVENTORY" | grep -F "${path}:" | sed 's/.*://' | head -n 1
    }
    
    # Lister les fichiers locaux
    LOCAL_FILES=$(find "$SRC_DIR" -type f)
    
    if [[ -z "$LOCAL_FILES" ]]; then
        echo "Aucun fichier local trouvé dans $SRC_DIR."
        continue
    fi
    
    while IFS= read -r LOCAL_FILE; do
        REL_PATH="${LOCAL_FILE#$SRC_DIR}"
        LOCAL_SIZE=$(stat -c %s "$LOCAL_FILE")
        
        # Obtenir la date de modification du fichier
        FILE_MTIME=$(stat -c %Y "$LOCAL_FILE")
        FILE_MONTH=$(date -r "$LOCAL_FILE" +%Y-%m)
        
        # Éviter de traiter les fichiers modifiés il y a moins de 10 minutes (sauvegarde en cours)
        AGE=$((CURRENT_TIME - FILE_MTIME))
        if [[ $AGE -lt 600 ]]; then
            echo "Skipping $REL_PATH : Fichier en cours d'écriture ou récemment modifié ($AGE secondes)."
            continue
        fi
        
        # Chemins attendus sur le serveur d'archivage
        REMOTE_UNCOMPRESSED_PATH="${DST_DIR}${REL_PATH}"
        REMOTE_COMPRESSED_PATH="${DST_DIR}${FILE_MONTH}/${REL_PATH}.gz"
        
        # 1. Vérification s'il est déjà archivé et compressé mensuellement
        COMPRESSED_SIZE=$(get_remote_size "$REMOTE_COMPRESSED_PATH")
        if [[ -n "$COMPRESSED_SIZE" ]]; then
            echo "Déjà archivé (compressé) : $REL_PATH dans le dossier mensuel $FILE_MONTH"
            # Si le fichier d'origine appartient à un mois précédent, nettoyage local
            if [[ "$FILE_MONTH" != "$CURRENT_MONTH" ]]; then
                if [[ "$DRY_RUN" == "false" ]]; then
                    echo "Suppression locale du vieux fichier : $LOCAL_FILE"
                    rm -f "$LOCAL_FILE"
                else
                    echo "[Dry-Run] Suppression locale du vieux fichier : $LOCAL_FILE"
                fi
            else
                echo "Fichier local conservé car il est du mois en cours ($FILE_MONTH)."
            fi
            continue
        fi
        
        # 2. Vérification s'il existe en version non compressée sur le serveur distant
        UNCOMPRESSED_SIZE=$(get_remote_size "$REMOTE_UNCOMPRESSED_PATH")
        IS_VALID=false
        
        if [[ -n "$UNCOMPRESSED_SIZE" && "$UNCOMPRESSED_SIZE" -eq "$LOCAL_SIZE" ]]; then
            echo "Déjà présent et valide : $REL_PATH (taille : $LOCAL_SIZE octets)"
            IS_VALID=true
        else
            # 3. Synchronisation car non présent ou taille différente
            echo "Archivage requis pour : $REL_PATH (taille locale : $LOCAL_SIZE octets)"
            if [[ "$DRY_RUN" == "false" ]]; then
                # S'assurer que le sous-dossier de destination existe (pour les arborescences imbriquées)
                REMOTE_PARENT_DIR=$(dirname "$REMOTE_UNCOMPRESSED_PATH")
                ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "mkdir -p \"$REMOTE_PARENT_DIR\""
                
                # Transfert du fichier
                rsync -avz -e ssh "$LOCAL_FILE" "${ARCHIVE_USER}@${ARCHIVE_SERVER}:${REMOTE_UNCOMPRESSED_PATH}"
                
                # Vérification après transfert
                REMOTE_CHECK_SIZE=$(ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "stat -c %s \"$REMOTE_UNCOMPRESSED_PATH\"" 2>/dev/null || echo "0")
                if [[ "$REMOTE_CHECK_SIZE" -eq "$LOCAL_SIZE" ]]; then
                    echo "Vérification OK pour : $REL_PATH"
                    IS_VALID=true
                else
                    echo "ERREUR : Échec de la vérification de taille pour $REL_PATH après rsync." >&2
                fi
            else
                echo "[Dry-Run] rsync $LOCAL_FILE vers ${ARCHIVE_USER}@${ARCHIVE_SERVER}:${REMOTE_UNCOMPRESSED_PATH}"
                IS_VALID=true
            fi
        fi
        
        # 4. Compression et Déplacement mensuel
        if [[ "$IS_VALID" == "true" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                echo "Compression et regroupement mensuel distant pour : $REL_PATH"
                # Créer le répertoire mensuel distant
                ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "mkdir -p \"${DST_DIR}${FILE_MONTH}\""
                # Compresser (gzip remplace le fichier par .gz)
                ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "gzip -f \"$REMOTE_UNCOMPRESSED_PATH\""
                # Déplacer dans le répertoire mensuel
                ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "mv -f \"${REMOTE_UNCOMPRESSED_PATH}.gz\" \"${DST_DIR}${FILE_MONTH}/\""
                
                # Valider que le fichier final compressé est bien présent
                REMOTE_FINAL_CHECK=$(ssh -n "${ARCHIVE_USER}@${ARCHIVE_SERVER}" "[ -f \"$REMOTE_COMPRESSED_PATH\" ] && echo 'OK' || echo 'FAIL'")
                if [[ "$REMOTE_FINAL_CHECK" != "OK" ]]; then
                    echo "ERREUR : Échec de la validation de la compression distante pour $REMOTE_COMPRESSED_PATH." >&2
                    continue
                fi
            else
                echo "[Dry-Run] mkdir -p \"${DST_DIR}${FILE_MONTH}\" sur le serveur distant."
                echo "[Dry-Run] gzip -f \"$REMOTE_UNCOMPRESSED_PATH\" sur le serveur distant."
                echo "[Dry-Run] mv -f \"${REMOTE_UNCOMPRESSED_PATH}.gz\" \"${DST_DIR}${FILE_MONTH}/\" sur le serveur distant."
            fi
            
            # 5. Nettoyage local si le fichier est d'un mois précédent
            if [[ "$FILE_MONTH" != "$CURRENT_MONTH" ]]; then
                if [[ "$DRY_RUN" == "false" ]]; then
                    echo "Nettoyage local : Suppression de $LOCAL_FILE"
                    rm -f "$LOCAL_FILE"
                else
                    echo "[Dry-Run] Nettoyage local : Suppression de $LOCAL_FILE"
                fi
            else
                echo "Fichier local conservé (mois en cours : $FILE_MONTH)."
            fi
        fi
        
    done <<< "$LOCAL_FILES"
    
done

echo "Processus d'archivage terminé."
