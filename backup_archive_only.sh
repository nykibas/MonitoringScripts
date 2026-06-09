#!/bin/bash

# ==============================================================================
# NOM DU SCRIPT : backup_archivelog_only.sh
# PROPRIÉTAIRE  : Yannick Nzau
# INSTANCE      : SOLID (DBPROD)
# SERVEUR       : SKN010SRVCBSBDD09
# DESCRIPTION   : Sauvegarde RMAN complète parallélisée sur 10 canaux
#                 incluant Datafiles, Archivelogs, Controlfile et SPFILE.
# ==============================================================================

# 1. Configuration de l'environnement Oracle
export ORACLE_SID=SOLID
export ORACLE_HOME=/oracle/app/product/19.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export DATE_STR=$(date +%Y%m%d_%H%M)

# 2. Définition des répertoires et du fichier log
BACKUP_ROOT="/backup"
DB_DUMP_DIR="$BACKUP_ROOT/FULL_BD_DUMP"
ARCH_DUMP_DIR="$BACKUP_ROOT/ALL_ARCHIVE_LOGS"
LOG_FILE="$BACKUP_ROOT/rman_backup_parallel_$DATE_STR.log"

# Création des répertoires si nécessaire
# mkdir -p $DB_DUMP_DIR $ARCH_DUMP_DIR

echo "------------------------------------------------------------" > $LOG_FILE
echo "DÉBUT DU BACKUP RMAN - OWNER: Yannick Nzau" >> $LOG_FILE
echo "DATE : $(date)" >> $LOG_FILE
echo "------------------------------------------------------------" >> $LOG_FILE

# 3. Lancement de RMAN
rman target / <<EOF >> $LOG_FILE 2>&1
# Rétention de 7 jours
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '$DB_DUMP_DIR/conf_%F';

# 1. Maintenance des catalogues
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;

# 2. Switch log avant backup
###SQL "ALTER SYSTEM SWITCH LOGFILE";

# Bloc de parallélisation sur 10 canaux (pour 10 vCPUs)
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c5 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c6 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c7 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c8 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c9 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c10 DEVICE TYPE DISK;

  # Backup explicite du SPFILE
  BACKUP AS COMPRESSED BACKUPSET SPFILE 
  FORMAT '$DB_DUMP_DIR/SPF_%d_%T_%U.ora';

  # 4. Backup des Archivelogs (Dossier ALL_ARCHIVE_LOGS)
  BACKUP AS COMPRESSED BACKUPSET ARCHIVELOG ALL 
  FORMAT '$ARCH_DUMP_DIR/ARCH_%d_%T_%U.bak'
  TAG 'ARCH_PARALLEL'
  DELETE INPUT;

  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
  RELEASE CHANNEL c3;
  RELEASE CHANNEL c4;
  RELEASE CHANNEL c5;
  RELEASE CHANNEL c6;
  RELEASE CHANNEL c7;
  RELEASE CHANNEL c8;
  RELEASE CHANNEL c9;
  RELEASE CHANNEL c10;
}

# 6. Switch log final pour valider la séquence
SQL "ALTER SYSTEM ARCHIVE LOG CURRENT";

# 7. Suppression des sauvegardes obsolètes (> 7 jours)
DELETE NOPROMPT OBSOLETE;

EXIT;
EOF

echo "------------------------------------------------------------" >> $LOG_FILE
echo "FIN DU BACKUP : $(date)" >> $LOG_FILE
echo "PROPRIÉTAIRE : Yannick Nzau" >> $LOG_FILE
echo "------------------------------------------------------------" >> $LOG_FILE
