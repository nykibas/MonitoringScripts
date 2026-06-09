#!/bin/bash

# ==============================================================================
# SCRIPT DE SURVEILLANCE QUOTIDIENNE DES BASES DE DONNÉES ORACLE
# PROPRIÉTAIRE : Yannick Nzau (Antigravity AI Assistant)
# DESTINATAIRE : it@solidarbank.com
# PLANIFICATION: Tous les matins à 6h00 via Cron
# DESCRIPTION   : Analyse les instances Oracle en cours d'exécution,
#                 relève l'utilisation des tablespaces, les objets invalides,
#                 les index inutilisables, les contraintes désactivées,
#                 le statut Data Guard, RMAN, et les erreurs du journal d'alerte.
#                 Envoie les faits saillants dans le corps du mail et
#                 le rapport complet au format HTML en pièce jointe.
# ==============================================================================

# Mode strict
set -euo pipefail

TIMEOUT=1000
START_TIME=$(date +%s)

export \
  OUTPUT_FILE \
  TOTAL_ISSUES \
  ISSUE_COUNT \
  EXCLUDED_COUNT \
  SUMMARY_TEXT \
  UPTIME_BACKUP_SECTION \
  FOUND_ORACLE_HOMES

# Charger le profil d'environnement Oracle
if [ -f ~/.bash_profile ]; then
    . ~/.bash_profile
fi

# Fonction pour tester un Oracle Home
test_oracle_home() {
    local test_home=$1
    if [ -d "$test_home" ] && [ -f "$test_home/bin/sqlplus" ]; then
        return 0
    else
        return 1
    fi
}

# Initialisation
ORIGINAL_PATH=$PATH
unset ORACLE_HOME
declare -A DB_UPTIME_SUMMARY
declare -A DB_BACKUP_SUMMARY

# Répertoires Oracle Homes prédéfinis
ORACLE_POSSIBLE_HOMES=(
    "/oracle/app/product/19.0.0/dbhome_1"
    "/u01/app/oracle/product/19.0.0/dbhome_1"
)

echo "Recherche des installations Oracle..."
FOUND_ORACLE_HOMES=()

for OH in "${ORACLE_POSSIBLE_HOMES[@]}"; do
    if test_oracle_home "$OH"; then
        FOUND_ORACLE_HOMES+=("$OH")
        echo "Oracle Home trouvé : $OH"
    fi
done

# Recherche dynamique si non trouvé
if [ ${#FOUND_ORACLE_HOMES[@]} -eq 0 ]; then
    echo "Aucun Oracle Home prédéfini trouvé. Recherche dynamique en cours..."
    while IFS= read -r -d '' sqlplus_path; do
        oracle_home=$(dirname $(dirname "$sqlplus_path"))
        if test_oracle_home "$oracle_home"; then
            FOUND_ORACLE_HOMES+=("$oracle_home")
            echo "Oracle Home trouvé dynamiquement : $oracle_home"
        fi
    done < <(find /u01 /opt -name sqlplus -type f 2>/dev/null -print0)
fi

if [ ${#FOUND_ORACLE_HOMES[@]} -eq 0 ]; then
    echo "ERREUR : Aucun environnement Oracle valide n'a été trouvé." >&2
    exit 1
fi

echo "${#FOUND_ORACLE_HOMES[@]} Oracle Home(s) identifié(s)."

check_timeout() {
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED_TIME -gt $TIMEOUT ]; then
        echo "Le script a dépassé le délai maximum de $TIMEOUT secondes." >&2
        exit 124
    fi
}

# Dossiers de rapports
OUTPUT_DIR="/home/oracle/oracle_reports"
if ! mkdir -p $OUTPUT_DIR 2>/dev/null; then
    OUTPUT_DIR="$(pwd)/oracle_reports"
    mkdir -p $OUTPUT_DIR
fi

OUTPUT_FILE="$OUTPUT_DIR/daily_oracle_report_$(date +%Y%m%d_%H%M%S).html"
TEMP_REPORT="/tmp/temp_oracle_report_$$.html"
SUMMARY_ISSUES="/tmp/summary_issues_$$.html"

# Initialisation du fichier de synthèse des anomalies
echo "" > $SUMMARY_ISSUES

# Génération du début du rapport HTML
cat << EOF > $TEMP_REPORT
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Rapport de Surveillance Oracle - $(date)</title>
     <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f4f6f9; color: #333; }
        h1 { color: #00205B; text-align: center; margin-bottom: 5px; }
        h2 { color: #00205B; border-bottom: 2px solid #00205B; padding-bottom: 5px; }
        h3 { color: #00418D; margin-left: 10px; }
        pre { background-color: #ffffff; padding: 15px; border-radius: 5px; border: 1px solid #ddd; overflow-x: auto; font-family: Consolas, monospace; font-size: 13px; }
        .section { margin-bottom: 30px; background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        .error { color: #D9534F; font-weight: bold; }
        .warning { color: #F0AD4E; font-weight: bold; }
        .critical { color: #D9534F; background-color: #FDF7F7; font-weight: bold; border-left: 5px solid #D9534F; }
        .locked { color: #D9534F; font-weight: bold; }
        .expired { color: #F0AD4E; font-weight: bold; }
        .high-usage { color: #D9534F; font-weight: bold; }
        .orange-bg { background-color: #FFF3CD; color: #856404; font-weight: bold; border-left: 4px solid #FFEBAA; }
        .oracle-home { color: #0056b3; font-weight: bold; background-color: #e6f2ff; padding: 5px 10px; border-radius: 3px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #00205B; color: white; }
        #toc { background-color: #fff; padding: 15px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        #toc h2 { border-bottom: 1px solid #ddd; margin-top: 0; }
        #toc ul { list-style-type: none; padding-left: 10px; }
        #toc li { margin-bottom: 8px; }
        #toc a { text-decoration: none; color: #0056b3; font-weight: 500; }
        #toc a:hover { text-decoration: underline; }
        .sid-section { border: 1px solid #ddd; border-radius: 8px; margin-bottom: 30px; padding: 20px; background-color: #fff; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        .sid-section h2 { background-color: #f0f4f8; padding: 10px; margin-top: 0; border-radius: 4px; }
        .oracle-home-section { border: 2px solid #00205B; border-radius: 10px; margin-bottom: 40px; padding: 20px; background-color: #fff; }
        .oracle-home-section h2 { background-color: #00205B; color: white; padding: 15px; margin-top: 0; border-radius: 6px; }
        .summary-issues { background-color: #FFF3CD; border: 2px solid #FFEBAA; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
        .summary-issues h2 { background-color: #FFC107; color: #333; padding: 10px; margin-top: 0; border-radius: 4px; }
        .issue-item { margin-bottom: 10px; padding: 8px 12px; background-color: #fff; border-left: 4px solid #FFC107; border-radius: 0 4px 4px 0; font-size: 14px; }
    </style>
</head>
<body>
    <h1>Rapport de Surveillance Oracle Quotidien</h1>
    <p style="text-align: center; font-size: 14px; color: #666;">Généré le : $(date)</p>
    
    <div id="toc">
        <h2>Table des matières</h2>
        <ul>
            <li><a href="#summary-issues">Faits Saillants (Synthèse)</a></li>
            <li><a href="#system-info">Informations Système & Disques</a></li>
EOF

# Ajouter les sections par base au sommaire
oracle_home_counter=1
declare -A ORACLE_HOME_DBS
for CURRENT_ORACLE_HOME in "${FOUND_ORACLE_HOMES[@]}"; do
    get_oracle_sids_for_toc() {
        local home_path=$1
        ps_output=$(ps -ef 2>/dev/null | grep -E "[o]ra_pmon|[p]mon_" | while read line; do
            if echo "$line" | grep -q "$home_path"; then
                echo "$line" | awk '{print $NF}' | sed -E 's/.*_(.+)$/\1/g'
            fi
        done | sort | uniq | head -3)
        
        if [ -n "$ps_output" ]; then
            echo "$ps_output" | tr '\n' ', ' | sed 's/,$//'
            return
        fi
        
        if [ -f /etc/oratab ]; then
            oratab_sids=$(grep -v "^#" /etc/oratab | while IFS=: read sid home startup; do
                if [ "$home" = "$home_path" ] || [ "$home/" = "$home_path/" ]; then
                    echo "$sid"
                fi
            done | grep -v '*' | sort | head -3 | tr '\n' ', ' | sed 's/,$//')
            
            if [ -n "$oratab_sids" ]; then
                echo "$oratab_sids"
                return
            fi
        fi
        echo "DB Inconnue"
    }
    
    DB_NAMES=$(get_oracle_sids_for_toc "$CURRENT_ORACLE_HOME")
    ORACLE_HOME_DBS["$CURRENT_ORACLE_HOME"]="$DB_NAMES"
    
    echo "            <li><a href=\"#oracle-home-$oracle_home_counter\">Instance(s) : $DB_NAMES ($CURRENT_ORACLE_HOME)</a></li>" >> $TEMP_REPORT
    oracle_home_counter=$((oracle_home_counter + 1))
done

echo "        </ul>" >> $TEMP_REPORT
echo "    </div>" >> $TEMP_REPORT

# Section Système (Disques, Mémoire, Processus)
add_system_section() {
    echo "<div class='section' id='system-info'>" >> $TEMP_REPORT
    echo "<h2>Informations Système</h2>" >> $TEMP_REPORT
    
    # Espace disque
    echo "<div class='section'>" >> $TEMP_REPORT
    echo "<h3>Espace Disque (df -h)</h3>" >> $TEMP_REPORT
    echo "<pre>" >> $TEMP_REPORT
    df -h 2>/dev/null | while IFS= read -r line; do
        line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        
        # Alerte si utilisation > 85%
        if echo "$line" | grep -E "8[5-9]%|9[0-9]%|100%" > /dev/null; then
            echo "<span class='orange-bg'>$line</span>"
            filesystem=$(echo "$line" | awk '{print $6}')
            usage=$(echo "$line" | awk '{print $5}')
            echo "<div class='issue-item'><strong>[ESPACE DISQUE]</strong> Utilisation élevée de $filesystem à $usage</div>" >> $SUMMARY_ISSUES
        else
            echo "$line"
        fi
    done >> $TEMP_REPORT
    echo "</pre>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    
    # Mémoire
    echo "<div class='section'>" >> $TEMP_REPORT
    echo "<h3>Vérification Mémoire RAM</h3>" >> $TEMP_REPORT
    echo "<pre>" >> $TEMP_REPORT
    (free -h || free -g || vmstat) 2>/dev/null | while IFS= read -r line; do
        line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "$line"
    done >> $TEMP_REPORT
    echo "</pre>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    
    # Processus PMON
    echo "<div class='section'>" >> $TEMP_REPORT
    echo "<h3>Processus Monitor Oracle (PMON)</h3>" >> $TEMP_REPORT
    echo "<pre>" >> $TEMP_REPORT
    ps -ef 2>/dev/null | grep -E "[o]ra_pmon|[p]mon_" | while IFS= read -r line; do
        line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "$line"
    done >> $TEMP_REPORT
    echo "</pre>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    
    echo "</div>" >> $TEMP_REPORT
}

add_system_section

# Extraction du nom du Listener
get_listener_names() {
    local oracle_home=$1
    local listener_file="$oracle_home/network/admin/listener.ora"
    local listener_names=""
    
    if [ -f "$listener_file" ]; then
        listener_names=$(grep -i '^[a-z0-9_]\+ *=' "$listener_file" | awk -F'=' '{print $1}' | sed 's/[[:space:]]*$//' | sort | uniq)
        echo "$listener_names"
    else
        echo "LISTENER"
    fi
}

# Traitement de chaque Oracle Home
oracle_home_counter=1
for CURRENT_ORACLE_HOME in "${FOUND_ORACLE_HOMES[@]}"; do
    echo "Traitement de l'Oracle Home : $CURRENT_ORACLE_HOME"
    
    export ORACLE_HOME=$CURRENT_ORACLE_HOME
    export PATH=$ORACLE_HOME/bin:$ORIGINAL_PATH
    
    DB_NAMES_FOR_HEADER="${ORACLE_HOME_DBS["$CURRENT_ORACLE_HOME"]}"
    
    echo "<div class='oracle-home-section' id='oracle-home-$oracle_home_counter'>" >> $TEMP_REPORT
    echo "<h2>Environnement : $DB_NAMES_FOR_HEADER</h2>" >> $TEMP_REPORT
    echo "<p class='oracle-home'>Chemin ORACLE_HOME : $ORACLE_HOME</p>" >> $TEMP_REPORT
    
    SQLPLUS=$ORACLE_HOME/bin/sqlplus
    
    if [ ! -f "$SQLPLUS" ]; then
        echo "<div class='section'><h3>Erreur</h3><pre class='critical'>Erreur : sqlplus introuvable à $SQLPLUS</pre></div></div>" >> $TEMP_REPORT
        oracle_home_counter=$((oracle_home_counter + 1))
        continue
    fi
    
    # Listener Status
    if [ -f "$ORACLE_HOME/bin/lsnrctl" ]; then
        echo "<div class='section'>" >> $TEMP_REPORT
        echo "<h3>Statut du Listener</h3>" >> $TEMP_REPORT
        echo "<pre>" >> $TEMP_REPORT
        
        LISTENER_NAMES=$(get_listener_names "$ORACLE_HOME")
        [ -z "$LISTENER_NAMES" ] && LISTENER_NAMES="LISTENER"
        
        for listener_name in $LISTENER_NAMES; do
            if [ -n "$listener_name" ]; then
                echo "=== Vérification du Listener : $listener_name ===" >> $TEMP_REPORT
                
                LISTENER_OUTPUT=$($ORACLE_HOME/bin/lsnrctl status "$listener_name" 2>&1)
                LISTENER_EXIT_CODE=$?
                
                echo "$LISTENER_OUTPUT" | while IFS= read -r line; do
                    line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                    
                    if echo "$line" | grep -iE "ERROR|not running|TNS-|could not contact|failed to contact" > /dev/null; then
                        echo "<span class='critical'>$line</span>"
                        error_msg=$(echo "$line" | sed 's/<[^>]*>//g' | tr -d '\n')
                        echo "<div class='issue-item'><strong>[LISTENER]</strong> Erreur $listener_name : $error_msg</div>" >> $SUMMARY_ISSUES
                    elif echo "$line" | grep -E "Instance.*status.*handler" > /dev/null; then
                        if echo "$line" | grep -v "status READY" > /dev/null; then
                            instance_name=$(echo "$line" | sed -n 's/.*Instance "\([^"]*\)".*/\1/p')
                            status=$(echo "$line" | sed -n 's/.*status \([^,]*\).*/\1/p')
                            echo "<span class='warning'>$line</span>"
                            echo "<div class='issue-item'><strong>[LISTENER]</strong> Instance \"$instance_name\" non prête (statut : $status)</div>" >> $SUMMARY_ISSUES
                        else
                            echo "$line"
                        fi
                    else
                        echo "$line"
                    fi
                done >> $TEMP_REPORT
                
                if [ $LISTENER_EXIT_CODE -ne 0 ]; then
                    echo "<span class='critical'>Échec de l'obtention du statut du listener $listener_name</span>" >> $TEMP_REPORT
                fi
                echo "" >> $TEMP_REPORT
            fi
        done
        echo "</pre>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
    fi
    
    # Détecter les SIDs actifs pour ce Home
    get_oracle_sids_for_home() {
        local home_path=$1
        ps_output=$(ps -ef 2>/dev/null | grep -E "[o]ra_pmon|[p]mon_" | while read line; do
            if echo "$line" | grep -q "$home_path"; then
                echo "$line" | awk '{print $NF}' | sed -E 's/.*_(.+)$/\1/g'
            fi
        done | sort | uniq)
        
        if [ -n "$ps_output" ]; then
            echo "$ps_output"
            return
        fi
        
        if [ -f /etc/oratab ]; then
            grep -v "^#" /etc/oratab | while IFS=: read sid home startup; do
                if [ "$home" = "$home_path" ] || [ "$home/" = "$home_path/" ]; then
                    echo "$sid"
                fi
            done | grep -v '*' | sort
            return
        fi
    }
    
    ORACLE_SIDS_FOR_HOME=$(get_oracle_sids_for_home "$CURRENT_ORACLE_HOME")
    
    if [ -z "$ORACLE_SIDS_FOR_HOME" ]; then
        echo "<div class='section'><h3>Bases Inactives</h3><pre class='warning'>Aucune base active trouvée pour cet Oracle Home</pre></div></div>" >> $TEMP_REPORT
        oracle_home_counter=$((oracle_home_counter + 1))
        continue
    fi
    
    # Traitement de chaque SID
    for SID in $ORACLE_SIDS_FOR_HOME; do
        echo "Traitement de la base de données : $SID"
        
        echo "<div class='sid-section' id='${CURRENT_ORACLE_HOME//\//_}_$SID'>" >> $TEMP_REPORT
        echo "<h2>Base de données : $SID</h2>" >> $TEMP_REPORT
        
        export ORACLE_SID=$SID
        
        # Test de connexion
        connection_test=$($SQLPLUS -S -L "/ as sysdba" << EOF
set heading off feedback off verify off pages 0 lines 200 trimout on
SELECT 'SUCCESS' FROM dual;
exit;
EOF
        )
        
        if ! echo "$connection_test" | grep -q "SUCCESS"; then
            echo "<div class='section'><h3>Erreur Connexion</h3><pre class='critical'>Impossible de se connecter à la base $SID (Instance inactive ou bloquée).</pre></div></div>" >> $TEMP_REPORT
            echo "<div class='issue-item'><strong>[CONNEXION BASE]</strong> Échec de connexion à la base $SID</div>" >> $SUMMARY_ISSUES
            continue
        fi
        
        # Collecter les infos Uptime et Backups RMAN pour le résumé du mail
        UPTIME_INFO=$($SQLPLUS -S "/ as sysdba" << EOF
set heading off feedback off verify off pages 0 lines 200
SELECT FLOOR(SYSDATE - STARTUP_TIME) || ' jours, ' || FLOOR(MOD((SYSDATE - STARTUP_TIME) * 24, 24)) || ' heures' FROM V\$INSTANCE;
exit;
EOF
        )
        
        LAST_BACKUP_INFO=$($SQLPLUS -S "/ as sysdba" << EOF
set heading off feedback off verify off pages 0 lines 200
SELECT INPUT_TYPE || ' - ' || STATUS || ' du ' || TO_CHAR(START_TIME, 'DD-MON-YYYY HH24:MI')
FROM (
    SELECT INPUT_TYPE, STATUS, START_TIME FROM V\$RMAN_BACKUP_JOB_DETAILS
    WHERE START_TIME >= SYSDATE - 30 ORDER BY START_TIME DESC
) WHERE ROWNUM = 1;
exit;
EOF
        )
        
        if [ -z "$LAST_BACKUP_INFO" ] || echo "$LAST_BACKUP_INFO" | grep -iq "no rows selected"; then
            LAST_BACKUP_INFO="Aucune sauvegarde trouvée ces 30 derniers jours"
        fi
        
        DB_UPTIME_SUMMARY["$SID"]="$UPTIME_INFO"
        DB_BACKUP_SUMMARY["$SID"]="$LAST_BACKUP_INFO"
        
        # Lancement des requêtes de diagnostic
        timeout 300s $SQLPLUS -S "/ as sysdba" << EOF >> $TEMP_REPORT
set pagesize 1000
set linesize 200
set feedback off
set heading on
set echo off
set verify off
set termout on

-- Info Base
prompt <div class='section'>
prompt <h3>Informations Générales</h3>
prompt <pre>
SELECT name, open_mode, log_mode, flashback_on, open_mode FROM v\$database;
prompt </pre>
prompt </div>

-- Sessions Actives
prompt <div class='section'>
prompt <h3>Sessions Actives</h3>
prompt <pre>
SELECT count(*) "Sessions", inst_id, status FROM gv\$session GROUP BY inst_id, status ORDER BY inst_id;
prompt </pre>
prompt </div>

-- PDBs
prompt <div class='section'>
prompt <h3>Bases Conteneurs (PDB)</h3>
prompt <pre>
show pdbs
prompt </pre>
prompt </div>

-- Utilisateurs verrouillés/expirés
prompt <div class='section'>
prompt <h3>Utilisateurs Verrouillés ou Expirant Bientôt (< 28 jours)</h3>
prompt <pre>
SET PAGESIZE 0
SET HEADING OFF
SELECT username || ' (PDB: ' || NVL((SELECT name FROM v\$pdbs WHERE con_id = u.con_id), 'CDB\$ROOT') || ') est ' || account_status || 
       '<!-- SUMMARY: [COMPTE UTILISATEUR] Compte ' || username || ' est ' || account_status || ' sur la base $SID -->'
FROM cdb_users u 
WHERE oracle_maintained = 'N' AND (account_status IN ('LOCKED', 'EXPIRED') OR (expiry_date IS NOT NULL AND expiry_date < SYSDATE + 28))
ORDER BY expiry_date DESC;
SET PAGESIZE 1000
SET HEADING ON
prompt </pre>
prompt </div>

-- Destination Flash Recovery Area
prompt <div class='section'>
prompt <h3>Espace Flash Recovery Area (FRA)</h3>
prompt <pre>
SELECT name, ROUND(space_limit/1024/1024/1024, 2) "LIMIT_GB", ROUND(space_used/1024/1024/1024,2) "USED_GB",
       ROUND((space_limit-space_used)/1024/1024/1024, 2) "FREE_GB",
       CASE 
           WHEN ROUND((space_used/space_limit)*100, 2) > 85 
           THEN '<span class="orange-bg">' || ROUND((space_used/space_limit)*100, 2) || '%</span><!-- SUMMARY: [RECOVERY AREA] Espace FRA saturé à ' || ROUND((space_used/space_limit)*100, 2) || '% - Base $SID -->'
           ELSE TO_CHAR(ROUND((space_used/space_limit)*100, 2)) || '%'
       END "USAGE"
FROM v\$recovery_file_dest;
prompt </pre>
prompt </div>

-- ASM Diskgroups
prompt <div class='section'>
prompt <h3>Groupes de disques ASM</h3>
prompt <pre>
SELECT name, state, type, ROUND(total_mb/1024, 2) "SIZE_GB", ROUND(free_mb/1024, 2) "FREE_GB",
       CASE 
           WHEN ROUND(((total_mb-free_mb)/total_mb)*100, 2) > 85 
           THEN '<span class="orange-bg">' || ROUND(((total_mb-free_mb)/total_mb)*100, 2) || '%</span><!-- SUMMARY: [ASM] Diskgroup ' || name || ' saturé à ' || ROUND(((total_mb-free_mb)/total_mb)*100, 2) || '% - Base $SID -->'
           ELSE TO_CHAR(ROUND(((total_mb-free_mb)/total_mb)*100, 2)) || '%'
       END "USAGE"
FROM v\$asm_diskgroup;
prompt </pre>
prompt </div>

-- RMAN Backups
prompt <div class='section'>
prompt <h3>Sauvegardes RMAN (10 derniers jours)</h3>
prompt <pre>
SET PAGESIZE 0
SET HEADING OFF
SELECT 'Session: ' || session_key || ' | Type: ' || input_type || ' | Statut: ' || 
       CASE 
           WHEN status = 'FAILED' THEN '<span class="critical">' || status || '</span><!-- SUMMARY: [RMAN BACKUP] Sauvegarde RMAN ÉCHOUÉE (Session ' || session_key || ') - Base $SID -->'
           WHEN status = 'RUNNING WITH ERRORS' THEN '<span class="orange-bg">' || status || '</span><!-- SUMMARY: [RMAN BACKUP] Sauvegarde RMAN avec ERREURS (Session ' || session_key || ') - Base $SID -->'
           ELSE status
       END || ' | Début: ' || TO_CHAR(start_time, 'DD-MM-YYYY HH24:MI') || ' | Fin: ' || NVL(TO_CHAR(end_time, 'DD-MM-YYYY HH24:MI'), 'N/A')
FROM v\$rman_backup_job_details
WHERE start_time >= SYSDATE - 10
ORDER BY start_time DESC;
SET PAGESIZE 1000
SET HEADING ON
prompt </pre>
prompt </div>

-- Verrous bloquants
prompt <div class='section'>
prompt <h3>Verrous Bloquants</h3>
prompt <pre>
SELECT sid, lmode, request, type, block 
FROM v\$lock 
WHERE block != 0;
prompt </pre>
prompt </div>

-- Corruptions de blocs
prompt <div class='section'>
prompt <h3>Corruptions de Blocs Physiques</h3>
prompt <pre>
SELECT * 
FROM v\$database_block_corruption;
prompt </pre>
prompt </div>

-- Objets Invalides
prompt <div class='section'>
prompt <h3>Objets Invalides (DBA_OBJECTS)</h3>
prompt <pre>
SELECT owner, object_type, COUNT(*) "NB_OBJECTS"
FROM dba_objects 
WHERE status = 'INVALID' 
GROUP BY owner, object_type
ORDER BY NB_OBJECTS DESC;
prompt </pre>
prompt </div>

-- NOUVEAU: Index Inutilisables (UNUSABLE)
prompt <div class='section'>
prompt <h3>Index Inutilisables (UNUSABLE)</h3>
prompt <pre>
SET PAGESIZE 0
SET HEADING OFF
SELECT owner || '.' || index_name || ' sur la table ' || table_name || ' est UNUSABLE' || 
       '<!-- SUMMARY: [INDEX DEFECTUEUX] L''index ' || owner || '.' || index_name || ' sur ' || table_name || ' est UNUSABLE - Base $SID -->'
FROM dba_indexes 
WHERE status = 'UNUSABLE'
ORDER BY owner, table_name;
SET PAGESIZE 1000
SET HEADING ON
prompt </pre>
prompt </div>

-- NOUVEAU: Contraintes Désactivées (DISABLED)
prompt <div class='section'>
prompt <h3>Contraintes Désactivées (DISABLED)</h3>
prompt <pre>
SET PAGESIZE 0
SET HEADING OFF
SELECT owner || '.' || constraint_name || ' sur la table ' || table_name || ' (Type: ' || constraint_type || ') est DISABLED' || 
       '<!-- SUMMARY: [CONTRAINTE DESACTIVEE] La contrainte ' || owner || '.' || constraint_name || ' sur ' || table_name || ' est DESACTIVEE - Base $SID -->'
FROM dba_constraints 
WHERE status = 'DISABLED'
ORDER BY owner, table_name;
SET PAGESIZE 1000
SET HEADING ON
prompt </pre>
prompt </div>

EXIT;
EOF
        
        check_timeout
        
        # Requête Tablespace avec traitement spécial
        TEMP_TS_OUTPUT="/tmp/tablespace_output_${SID}_$$.txt"
        
        timeout 300s $SQLPLUS -S "/ as sysdba" << EOF > $TEMP_TS_OUTPUT
SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF
SET LINESIZE 300

SELECT 
    cdb.tablespace_name || '|' ||
    c.name || '|' ||
    ROUND((cdb.bytes - SUM(fs.bytes)) * 100 / cdb.bytes, 2) || '|' ||
    ROUND(cdb.bytes/(1024*1024*1024), 2) || ' GB|' ||
    ROUND(SUM(fs.bytes)/(1024*1024*1024), 2) || ' GB|' ||
    ROUND((cdb.bytes-SUM(fs.bytes))/(cdb.maxbytes)*100, 2) || '|' ||
    cdb.autoextensible
FROM CDB_FREE_SPACE fs
JOIN (SELECT con_id, tablespace_name, SUM(bytes) bytes, 
             SUM(DECODE(maxbytes,0,bytes,maxbytes)) maxbytes, 
             MAX(autoextensible) autoextensible 
      FROM CDB_DATA_FILES 
      GROUP BY con_id, tablespace_name) cdb
ON fs.con_id = cdb.con_id AND fs.tablespace_name = cdb.tablespace_name
JOIN V\$CONTAINERS c ON c.con_id = cdb.con_id
GROUP BY cdb.tablespace_name, cdb.bytes, cdb.maxbytes, c.name
ORDER BY ROUND((cdb.bytes-SUM(fs.bytes))/(cdb.maxbytes)*100, 2) DESC;
EXIT;
EOF
        
        echo "<div class='section'>" >> $TEMP_REPORT
        echo "<h3>Occupation des Tablespaces (Tous PDBs)</h3>" >> $TEMP_REPORT
        echo "<pre>" >> $TEMP_REPORT
        echo "TABLESPACE      PDB_NAME        USAGE%   TAILLE          ESPACE_LIBRE   USAGE_MAX%  AUTOEXT" >> $TEMP_REPORT
        echo "--------------- --------------- -------- --------------- --------------- ----------- -------" >> $TEMP_REPORT
        
        while IFS='|' read -r ts_name pdb_name usage_pct ts_size ts_free used_pct_max auto_ext || [ -n "$ts_name" ]; do
            if [ -n "$ts_name" ]; then
                # Nettoyage des espaces
                used_pct_max_clean=$(echo "$used_pct_max" | tr -d '[:space:]')
                usage_pct_clean=$(echo "$usage_pct" | tr -d '[:space:]')
                
                formatted_line=$(printf "%-15s %-15s %-8s %-15s %-15s %-11s %s" \
                    "$ts_name" "$pdb_name" "${usage_pct_clean}%" "$ts_size" "$ts_free" "${used_pct_max_clean}%" "$auto_ext")
                
                # Flag d'alerte si l'usage dépasse 85% par rapport au maximum possible (maxbytes)
                if [ -n "$used_pct_max_clean" ] && awk "BEGIN{exit !($used_pct_max_clean > 85)}" 2>/dev/null; then
                    echo "<span class=\"orange-bg\">${formatted_line}</span>" >> $TEMP_REPORT
                    echo "<div class='issue-item'><strong>[TABLESPACE]</strong> Usage critique de ${pdb_name}/${ts_name} à ${used_pct_max_clean}% du MAX - Base $SID</div>" >> $SUMMARY_ISSUES
                else
                    echo "${formatted_line}" >> $TEMP_REPORT
                fi
            fi
        done < $TEMP_TS_OUTPUT
        
        echo "</pre>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
        rm -f $TEMP_TS_OUTPUT
        
        # Analyse des Alert Logs
        ALERT_LOG_DIR=$($SQLPLUS -S "/ as sysdba" << EOF
set heading off feedback off verify off pages 0 lines 200
select value from v\$diag_info where name = 'Diag Trace';
exit;
EOF
        )
        
        ALERT_LOG_FILE=$(find "$ALERT_LOG_DIR" -name "alert_${SID}.log" 2>/dev/null | head -1)
        
        echo "<div class='section'>" >> $TEMP_REPORT
        echo "<h3>Extraits Récents du Journal d'Alerte (Alert Log)</h3>" >> $TEMP_REPORT
        echo "<pre>" >> $TEMP_REPORT
        
        if [ -f "$ALERT_LOG_FILE" ]; then
            tail -600 "$ALERT_LOG_FILE" | while IFS= read -r line || [ -n "$line" ]; do
                original_line="$line"
                line_escaped=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                
                if echo "$original_line" | grep -iE "ORA-|ERROR|FATAL|SEVERE|CRITICAL" > /dev/null; then
                    echo "<span class='critical'>$line_escaped</span>"
                    if echo "$original_line" | grep -iE "ORA-|error" > /dev/null; then
                        cleaned_line=$(echo "$original_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                        [ ${#cleaned_line} -gt 150 ] && cleaned_line="${cleaned_line:0:150}..."
                        echo "<div class='issue-item'><strong>[ALERT LOG]</strong> $cleaned_line</div>" >> $SUMMARY_ISSUES
                    fi
                elif echo "$original_line" | grep -iE "WARNING|WARN" > /dev/null; then
                    echo "<span class='warning'>$line_escaped</span>"
                else
                    echo "$line_escaped"
                fi
            done >> $TEMP_REPORT
        else
            echo "<span class='warning'>Fichier alert_${SID}.log introuvable sous : $ALERT_LOG_DIR</span>" >> $TEMP_REPORT
            echo "<div class='issue-item'><strong>[ALERT LOG]</strong> Alert log introuvable pour $SID</div>" >> $SUMMARY_ISSUES
        fi
        
        echo "</pre>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
        
        echo "</div><!-- End of SID section -->" >> $TEMP_REPORT
    done
    
    echo "</div><!-- End of Oracle Home section -->" >> $TEMP_REPORT
    oracle_home_counter=$((oracle_home_counter + 1))
done

echo "</body></html>" >> $TEMP_REPORT

# Extraction et nettoyage des commentaires SQL SUMMARY de faits saillants
grep -o '<!-- SUMMARY: \[.*\] .* -->' $TEMP_REPORT 2>/dev/null | sed 's/<!-- SUMMARY: //' | sed 's/ -->//' | while IFS= read -r summary_line; do
    echo "<div class='issue-item'>$summary_line</div>" >> $SUMMARY_ISSUES
done

# Reconstruction du rapport final consolidé
cat > $OUTPUT_FILE << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Rapport de Diagnostic Oracle Quotidien</title>
     <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f4f6f9; color: #333; }
        h1 { color: #00205B; text-align: center; margin-bottom: 5px; }
        h2 { color: #00205B; border-bottom: 2px solid #00205B; padding-bottom: 5px; }
        h3 { color: #00418D; margin-left: 10px; }
        pre { background-color: #ffffff; padding: 15px; border-radius: 5px; border: 1px solid #ddd; overflow-x: auto; font-family: Consolas, monospace; font-size: 13px; }
        .section { margin-bottom: 30px; background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        .error { color: #D9534F; font-weight: bold; }
        .warning { color: #F0AD4E; font-weight: bold; }
        .critical { color: #D9534F; background-color: #FDF7F7; font-weight: bold; border-left: 5px solid #D9534F; }
        .locked { color: #D9534F; font-weight: bold; }
        .expired { color: #F0AD4E; font-weight: bold; }
        .high-usage { color: #D9534F; font-weight: bold; }
        .orange-bg { background-color: #FFF3CD; color: #856404; font-weight: bold; border-left: 4px solid #FFEBAA; }
        .oracle-home { color: #0056b3; font-weight: bold; background-color: #e6f2ff; padding: 5px 10px; border-radius: 3px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #00205B; color: white; }
        #toc { background-color: #fff; padding: 15px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        #toc h2 { border-bottom: 1px solid #ddd; margin-top: 0; }
        #toc ul { list-style-type: none; padding-left: 10px; }
        #toc li { margin-bottom: 8px; }
        #toc a { text-decoration: none; color: #0056b3; font-weight: 500; }
        #toc a:hover { text-decoration: underline; }
        .sid-section { border: 1px solid #ddd; border-radius: 8px; margin-bottom: 30px; padding: 20px; background-color: #fff; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        .sid-section h2 { background-color: #f0f4f8; padding: 10px; margin-top: 0; border-radius: 4px; }
        .oracle-home-section { border: 2px solid #00205B; border-radius: 10px; margin-bottom: 40px; padding: 20px; background-color: #fff; }
        .oracle-home-section h2 { background-color: #00205B; color: white; padding: 15px; margin-top: 0; border-radius: 6px; }
        .summary-issues { background-color: #FFF3CD; border: 2px solid #FFEBAA; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
        .summary-issues h2 { background-color: #FFC107; color: #333; padding: 10px; margin-top: 0; border-radius: 4px; }
        .issue-item { margin-bottom: 10px; padding: 8px 12px; background-color: #fff; border-left: 4px solid #FFC107; border-radius: 0 4px 4px 0; font-size: 14px; }
    </style>
</head>
<body>
EOF

echo "    <h1>Rapport Quotidien de Santé Base de Données Oracle</h1>" >> $OUTPUT_FILE
echo "    <p style=\"text-align: center;\">Généré le : $(date)</p>" >> $OUTPUT_FILE
echo "    <p style=\"text-align: center;\">Nombre d'environnements Oracle Homes scannés : ${#FOUND_ORACLE_HOMES[@]}</p>" >> $OUTPUT_FILE

# Section de Synthèse des Alertes (Faits Saillants) en haut du fichier HTML
echo "    <div class='summary-issues' id='summary-issues'>" >> $OUTPUT_FILE
echo "        <h2>Faits Saillants (Failles et Alertes)</h2>" >> $OUTPUT_FILE

if [ -s "$SUMMARY_ISSUES" ]; then
    cat $SUMMARY_ISSUES >> $OUTPUT_FILE
else
    echo "        <div class='issue-item' style='background-color: #D4EDDA; border-left: 4px solid #28A745; color: #155724;'>" >> $OUTPUT_FILE
    echo "            <strong>[CONCORDANCE]</strong> Aucune anomalie détectée sur la base de données !" >> $OUTPUT_FILE
    echo "        </div>" >> $OUTPUT_FILE
fi

echo "    </div>" >> $OUTPUT_FILE

# Récupérer le reste du corps HTML généré dans TEMP_REPORT
sed -n '/<div id="toc">/,/<\/body>/p' $TEMP_REPORT | sed '$d' >> $OUTPUT_FILE

# Ajouter le pied de page HTML
cat << EOF >> $OUTPUT_FILE
<div style="text-align: center; margin-top: 40px; padding: 20px; border-top: 1px solid #ccc; color: #666; font-size: 12px; background-color: #f9f9f9;">
    <div style="margin-bottom: 10px;">
        <strong>Système de surveillance Oracle automatique</strong>
    </div>
    <div style="margin-top: 5px; font-size: 11px;">
        Oracle Health Check & Alerts | Solidarbank IT Dept | 2026
    </div>
</div>
</body>
</html>
EOF

# Nettoyage des fichiers temporaires
rm -f $TEMP_REPORT $SUMMARY_ISSUES

chmod 644 $OUTPUT_FILE

# ===== Configuration de la Messagerie =====
TO="it@solidarbank.com"
FROM="monitoring@solidarbank.com"
SUBJECT="[ALERT ORACLE] Rapport Quotidien de Santé - $(hostname) - $(date +%d/%m/%Y)"

# Chemin du fichier d'exclusion
EXCLUSION_FILE="/home/oracle/scripts/oracle_monitor_exclusions.txt"
[ ! -f "$EXCLUSION_FILE" ] && EXCLUSION_FILE="oracle_monitor_exclusions.txt"

# Extraction et formatage textuel des anomalies (Faits Saillants)
SUMMARY_RAW=$(grep "class='issue-item'" "$OUTPUT_FILE" | \
    sed 's/.*<div class=.issue-item[^>]*>//g' | \
    sed 's/<\/div>.*//g' | \
    sed 's/<strong>//g' | \
    sed 's/<\/strong>//g' | \
    sed 's/&amp;/\&/g' | \
    sed 's/&lt;/</g' | \
    sed 's/&gt;/>/g' | \
    sed 's/<span[^>]*>//g' | \
    sed 's/<\/span>//g' | \
    sed 's/^[[:space:]]*//' | \
    sed 's/[[:space:]]*$//')

SUMMARY_ALL=$(echo "$SUMMARY_RAW" | sed 's/] \[/]\n[/g')

# Application des filtres d'exclusion
if [ -f "$EXCLUSION_FILE" ]; then
    TEMP_FILTERED="/tmp/filtered_issues_$$.txt"
    echo "$SUMMARY_ALL" > "$TEMP_FILTERED"
    
    cat "$EXCLUSION_FILE" | tr -d '\r' | while IFS= read -r line || [ -n "$line" ]; do
        exclusion_pattern=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$exclusion_pattern" ]] || [[ "$exclusion_pattern" =~ ^# ]]; then
            continue
        fi
        grep -v -i "$exclusion_pattern" "$TEMP_FILTERED" > "${TEMP_FILTERED}.new" 2>/dev/null || touch "${TEMP_FILTERED}.new"
        mv "${TEMP_FILTERED}.new" "$TEMP_FILTERED"
    done
    
    SUMMARY_TEXT=$(cat "$TEMP_FILTERED")
    rm -f "$TEMP_FILTERED"
else
    SUMMARY_TEXT="$SUMMARY_ALL"
fi

TOTAL_ISSUES=$(echo "$SUMMARY_ALL" | grep -c "^\[" 2>/dev/null || echo "0")
ISSUE_COUNT=$(echo "$SUMMARY_TEXT" | grep -c "^\[" 2>/dev/null || echo "0")
EXCLUDED_COUNT=$((TOTAL_ISSUES - ISSUE_COUNT))

# Construction du récapitulatif Uptime & Backups RMAN pour le corps du mail
UPTIME_BACKUP_SECTION=""
for sid_key in "${!DB_UPTIME_SUMMARY[@]}"; do
    UPTIME_BACKUP_SECTION="${UPTIME_BACKUP_SECTION}- Base [$sid_key] : Uptime = ${DB_UPTIME_SUMMARY[$sid_key]} | Dernière sauvegarde : ${DB_BACKUP_SUMMARY[$sid_key]}\n"
done

# Construction finale du CORPS du mail en texte clair
BODY=$(cat <<EOF
Bonjour,

Veuillez trouver ci-dessous le rapport de santé quotidien de la base de données Oracle ($(hostname)), scannée le $(date).

======================================================================
SYNTHÈSE DES BASES (UPTIME & SAUVEGARDES RMAN)
======================================================================
$(echo -e "$UPTIME_BACKUP_SECTION")

======================================================================
FAITS SAILLANTS (ANOMALIES ET ALERTES DÉTECTÉES)
======================================================================
Nombre total d'anomalies détectées : ${TOTAL_ISSUES}
Nombre d'anomalies après filtrage    : ${ISSUE_COUNT}
Nombre d'anomalies exclues          : ${EXCLUDED_COUNT}

----------------------------------------------------------------------
Alertes actives :
----------------------------------------------------------------------
${SUMMARY_TEXT:-Aucune anomalie détectée ce matin.}

======================================================================
Le rapport de scan complet et interactif au format HTML est joint à cet e-mail.

Cordialement,
L'équipe d'administration système et bases de données
EOF
)

# Envoi de l'e-mail avec pièce jointe
echo "Envoi du mail d'alerte quotidien à $TO..."
if echo "$BODY" | /usr/bin/mailx -r "$FROM" -a "$OUTPUT_FILE" -s "$SUBJECT" "$TO" >/dev/null 2>&1; then
    echo "Mail envoyé avec succès à $TO."
else
    # Fallback si mailx complet n'est pas configuré, tenter mail standard
    if echo "$BODY" | mail -s "$SUBJECT" "$TO" >/dev/null 2>&1; then
        echo "Mail envoyé via fallback standard à $TO."
    else
        echo "ERREUR : Échec de l'envoi du mail. Veuillez vérifier la configuration réseau du serveur postfix/sendmail." >&2
    fi
fi

echo "Fin du traitement du rapport de santé quotidien Oracle."
