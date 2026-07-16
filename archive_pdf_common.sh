#!/bin/bash

# ==============================================================================
# SCRIPT D'ARCHIVAGE DES PDF APPLICATIFS
# PROPRIÉTAIRE : Yannick Nzau (Antigravity AI Assistant)
# DESCRIPTION   : 
#   1. Recherche tous les sous-répertoires dans /appli/common et recrée à l'identique
#      la structure dans /backup/appli/common.
#   2. Recherche les fichiers PDF correspondants à "printout.*.pdf" vieux de plus 
#      de 5 jours.
#   3. Compresse chaque PDF au format .tar.gz individuellement dans le dossier 
#      d'archivage correspondant.
#   4. Valide l'archive puis supprime le fichier PDF d'origine de la source.
# ==============================================================================

# Mode strict
set -eo pipefail

DRY_RUN=false
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
        echo "========================================= "
        echo "   MODE SIMULATION (DRY RUN) ACTIVÉ      "
        echo "========================================= "
    fi
done

# Configuration des chemins
SRC_DIR="/appli/common"
DST_DIR="/backup/appli/common"

# Délai de conservation (5 jours en secondes : 5 * 24 * 3600)
RETENTION_SECONDS=$((5 * 24 * 3600))
CURRENT_TIME=$(date +%s)

echo "Démarrage du processus d'archivage des PDF..."
echo "Source      : $SRC_DIR"
echo "Destination : $DST_DIR"
echo "Seuil d'âge : 5 jours ($RETENTION_SECONDS secondes)"

if [[ ! -d "$SRC_DIR" ]]; then
    echo "ERREUR : Répertoire source $SRC_DIR introuvable." >&2
    exit 1
fi

# 1. Recréer l'arborescence des sous-répertoires dans l'archive
echo "Synchronisation de la structure des sous-répertoires..."
find "$SRC_DIR" -mindepth 1 -type d 2>/dev/null | while read -r subdir; do
    rel_dir="${subdir#$SRC_DIR/}"
    backup_subdir="${DST_DIR}/${rel_dir}"
    
    if [[ ! -d "$backup_subdir" ]]; then
        echo "Création du nouveau sous-répertoire dans l'archive : $rel_dir"
        if [[ "$DRY_RUN" == "false" ]]; then
            mkdir -p "$backup_subdir"
        fi
    fi
done

# 2. Rechercher et traiter les fichiers PDF printout.*.pdf
echo "Recherche des fichiers PDF printout.*.pdf vieux de plus de 5 jours..."
PDF_FILES=$(find "$SRC_DIR" -type f -name "printout.*.pdf" -o -name "printout.*.PDF" 2>/dev/null || true)

if [[ -z "$PDF_FILES" ]]; then
    echo "Aucun fichier PDF correspondant trouvé."
    exit 0
fi

processed_count=0
archived_count=0

while IFS= read -r file_path; do
    if [[ -z "$file_path" ]]; then
        continue
    fi
    
    # Vérifier que le fichier existe
    if [[ ! -f "$file_path" ]]; then
        continue
    fi
    
    # Récupérer l'âge du fichier
    FILE_MTIME=$(stat -c %Y "$file_path")
    AGE=$((CURRENT_TIME - FILE_MTIME))
    
    # Filtrer par âge (> 5 jours)
    if [[ $AGE -le $RETENTION_SECONDS ]]; then
        # Fichier trop récent, on l'ignore
        continue
    fi
    
    processed_count=$((processed_count + 1))
    
    # Extraire les composants du chemin
    dir_path=$(dirname "$file_path")
    base_name=$(basename "$file_path")
    
    # Nettoyer l'extension .pdf/.PDF pour nommer le tar.gz
    base_without_ext=$(echo "$base_name" | sed -E 's/\.[pP][dD][fF]$//')
    
    # Déterminer le chemin relatif du répertoire
    rel_dir=""
    if [[ "$dir_path" != "$SRC_DIR" ]]; then
        rel_dir="${dir_path#$SRC_DIR/}"
    fi
    
    # Répertoire cible de sauvegarde
    backup_target_dir="${DST_DIR}"
    if [[ -n "$rel_dir" ]]; then
        backup_target_dir="${DST_DIR}/${rel_dir}"
    fi
    
    target_archive="${backup_target_dir}/${base_without_ext}.tar.gz"
    
    # Vérifier si l'archive existe déjà
    if [[ -f "$target_archive" ]]; then
        echo "L'archive existe déjà : $(basename "$target_archive") dans $rel_dir"
        # Le fichier d'origine peut être nettoyé si l'archive est valide
        if [[ "$DRY_RUN" == "false" ]]; then
            echo "Nettoyage du fichier d'origine déjà archivé..."
            rm -f "$file_path"
        else
            echo "[Dry-Run] rm -f \"$file_path\""
        fi
        continue
    fi
    
    # Traitement d'archivage
    echo "Archivage requis : $rel_dir/$base_name (Âge : $((AGE / 86400)) jours)"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # S'assurer que le répertoire de destination existe (au cas où)
        mkdir -p "$backup_target_dir"
        
        # Compression individuelle en tar.gz
        # -C permet de se placer dans le répertoire pour ne pas archiver le chemin absolu
        if tar -czf "$target_archive" -C "$dir_path" "$base_name"; then
            # Validation de la présence et taille de l'archive
            if [[ -f "$target_archive" && -s "$target_archive" ]]; then
                echo "Archive générée avec succès : $(basename "$target_archive")"
                # Suppression du fichier d'origine
                rm -f "$file_path"
                archived_count=$((archived_count + 1))
            else
                echo "ERREUR : L'archive générée $target_archive est invalide ou vide." >&2
                rm -f "$target_archive"
            fi
        else
            echo "ERREUR : Échec de la compression de $file_path." >&2
        fi
    else
        echo "[Dry-Run] tar -czf \"$target_archive\" -C \"$dir_path\" \"$base_name\""
        echo "[Dry-Run] rm -f \"$file_path\""
        archived_count=$((archived_count + 1))
    fi
    
done <<< "$PDF_FILES"

echo "------------------------------------------------------------"
echo "Processus d'archivage terminé."
echo "Fichiers PDF analysés (> 5 jours) : $processed_count"
echo "Fichiers PDF archivés et purgés  : $archived_count"
echo "------------------------------------------------------------"
