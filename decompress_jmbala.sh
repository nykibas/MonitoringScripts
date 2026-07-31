#!/bin/bash
# ==============================================================================
# SCRIPT DE REORGANISATION ET DECOMPRESSION DE DOSSIER (JMBALA)
# DESCRIPTION   : Déplace les fichiers du 16 Juillet 2026 dans le dossier
#                 "decompress" et les extrait (tar.gz, gz, zip).
# ==============================================================================

set -eo pipefail

DIR="/backup/appli/common/JMBALA"
TARGET_DIR="${DIR}/decompress"
DATE_TARGET="2026-07-16"

if [[ ! -d "$DIR" ]]; then
    echo "ERREUR : Le répertoire $DIR n'existe pas." >&2
    exit 1
fi

# Création du dossier cible si absent
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Création du dossier de destination : $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

echo "1. Recherche et déplacement des fichiers modifiés le $DATE_TARGET..."
# Trouver et déplacer uniquement les fichiers à la racine de JMBALA modifiés le 16/07
find "$DIR" -maxdepth 1 -type f -newermt "${DATE_TARGET} 00:00:00" ! -newermt "${DATE_TARGET} 23:59:59" | while read -r file; do
    echo "Déplacement de : $(basename "$file")"
    mv "$file" "$TARGET_DIR/"
done

echo "2. Décompression des fichiers déplacés dans $TARGET_DIR..."
cd "$TARGET_DIR"

# Décompression selon le type de fichier
for f in *; do
    if [[ ! -f "$f" ]]; then
        continue
    fi
    
    case "$f" in
        *.tar.gz|*.tgz)
            echo "Extraction tar.gz : $f"
            tar -xzf "$f"
            ;;
        *.gz)
            echo "Extraction gzip   : $f"
            gunzip "$f"
            ;;
        *.zip)
            echo "Extraction zip    : $f"
            unzip -q "$f"
            ;;
        *)
            echo "Ignoré ou déjà décompressé : $f"
            ;;
    esac
done

echo "Opération terminée avec succès."
