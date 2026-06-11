#!/bin/bash

# ==============================================================================
# SCRIPT DE RÉORGANISATION RÉTROACTIVE DES ARCHIVES
# PROPRIÉTAIRE : Yannick Nzau (Antigravity AI Assistant)
# DESCRIPTION   : 
#   Parcourt un répertoire d'archivage (ou la liste par défaut), extrait la date
#   de génération réelle contenue dans le nom de chaque fichier de sauvegarde,
#   compresse les fichiers non compressés (gzip) et les range dans le sous-dossier
#   mensuel correspondant (format AAAA-MM).
# ==============================================================================

# Mode strict
set -eo pipefail

DRY_RUN=false
TARGET_DIR_ARG=""

# Analyse des arguments
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    else
        TARGET_DIR_ARG="$arg"
    fi
done

if [[ "$DRY_RUN" == "true" ]]; then
    echo "========================================= "
    echo "   MODE SIMULATION (DRY RUN) ACTIVÉ      "
    echo "========================================= "
fi

# Répertoires d'archivage par défaut
DEFAULT_DIRS=(
    "/housekeeping/rman/FULL_BD_DUMP/"
    "/housekeeping/rman/ALL_ARCHIVE_LOGS/"
    "/housekeeping/sauv_ap/"
    "/housekeeping/sauv_av/"
)

# Fonction pour réorganiser un dossier
reorganize_directory() {
    local target_dir="$1"
    
    # Assurer le slash de fin
    [[ "$target_dir" != */ ]] && target_dir="$target_dir/"
    
    echo "------------------------------------------------------------"
    echo "Réorganisation de : $target_dir"
    echo "------------------------------------------------------------"
    
    if [[ ! -d "$target_dir" ]]; then
        echo "ATTENTION : Le répertoire $target_dir n'existe pas. Passage au suivant."
        return
    fi
    
    # Obtenir la liste de tous les fichiers (recherche récursive)
    # On stocke d'abord dans une variable pour éviter que la liste ne change en cours de boucle
    local files_list
    files_list=$(find "$target_dir" -type f 2>/dev/null || true)
    
    if [[ -z "$files_list" ]]; then
        echo "Aucun fichier trouvé dans $target_dir."
        return
    fi
    
    local processed_count=0
    local moved_count=0
    local compressed_count=0
    
    while IFS= read -r file_path; do
        if [[ -z "$file_path" ]]; then
            continue
        fi
        
        local base
        base=$(basename "$file_path")
        
        # 1. Extraction de la date (séquence de 8 chiffres commençant par 20)
        local date_str
        date_str=$(echo "$base" | grep -o -E '20[0-9]{6}' | head -n 1 || true)
        
        local target_month
        if [[ -n "$date_str" ]]; then
            local year="${date_str:0:4}"
            local month="${date_str:4:2}"
            if [[ "$month" -ge 1 && "$month" -le 12 ]]; then
                target_month="${year}-${month}"
            else
                # Fallback si le mois est invalide (ex: 20261399)
                target_month=$(date -r "$file_path" +%Y-%m)
            fi
        else
            # Fallback sur la date de modification du fichier
            target_month=$(date -r "$file_path" +%Y-%m)
        fi
        
        local month_dir="${target_dir}${target_month}"
        
        # 2. Déterminer le nom final attendu
        local final_base="$base"
        local needs_compression=false
        
        if [[ "$base" != *.gz ]]; then
            needs_compression=true
            final_base="${base}.gz"
        fi
        
        local expected_path="${month_dir}/${final_base}"
        
        # 3. Vérifier si le fichier est déjà correctement placé et compressé
        if [[ "$file_path" == "$expected_path" ]]; then
            # Déjà correct
            continue
        fi
        
        processed_count=$((processed_count + 1))
        
        # 4. Traitement
        if [[ "$needs_compression" == "true" ]]; then
            echo "-> Fichier non compressé trouvé : $base"
            if [[ "$DRY_RUN" == "false" ]]; then
                # S'assurer que le répertoire mensuel existe
                mkdir -p "$month_dir"
                
                # Compresser
                echo "   Compression en cours..."
                gzip -f "$file_path"
                
                # Déplacer le .gz généré (qui est à l'emplacement d'origine avec suffixe .gz)
                mv -f "${file_path}.gz" "$month_dir/"
                compressed_count=$((compressed_count + 1))
                moved_count=$((moved_count + 1))
                echo "   Compressé et déplacé dans $target_month/"
            else
                echo "   [Dry-Run] gzip -f \"$file_path\""
                echo "   [Dry-Run] mv \"${file_path}.gz\" vers \"$month_dir/\""
                compressed_count=$((compressed_count + 1))
                moved_count=$((moved_count + 1))
            fi
        else
            echo "-> Fichier déjà compressé mais mal classé : $base (Déplacement vers $target_month/)"
            if [[ "$DRY_RUN" == "false" ]]; then
                # S'assurer que le répertoire mensuel existe
                mkdir -p "$month_dir"
                
                # Déplacer
                mv -f "$file_path" "$month_dir/"
                moved_count=$((moved_count + 1))
            else
                echo "   [Dry-Run] mv \"$file_path\" vers \"$month_dir/\""
                moved_count=$((moved_count + 1))
            fi
        fi
        
    done <<< "$files_list"
    
    echo "Terminé pour $target_dir. Fichiers analysés : $processed_count, Compressés : $compressed_count, Déplacés : $moved_count."
}

# Choix de la cible à traiter
if [[ -n "$TARGET_DIR_ARG" ]]; then
    # Traiter uniquement le répertoire passé en argument
    reorganize_directory "$TARGET_DIR_ARG"
else
    # Traiter tous les répertoires par défaut
    echo "Aucun répertoire spécifié. Traitement des répertoires par défaut de l'archivage..."
    for dir in "${DEFAULT_DIRS[@]}"; do
        reorganize_directory "$dir"
    done
fi

echo "============================================================"
echo "Processus de réorganisation des archives terminé."
echo "============================================================"
