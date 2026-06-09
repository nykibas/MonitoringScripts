#!/bin/bash

TIMEOUT=1000

export \
  OUTPUT_FILE \
  OUTPUT_FILE2 \
  TOTAL_ISSUES \
  ISSUE_COUNT \
  EXCLUDED_COUNT \
  SUMMARY_TEXT \
  UPTIME_BACKUP_SECTION \
  FOUND_ORACLE_HOMES

# Start time in seconds since epoch
START_TIME=$(date +%s)

# Load Oracle environment
if [ -f ~/.bash_profile ]; then
    . ~/.bash_profile
fi

# Function to test Oracle Home
test_oracle_home() {
    local test_home=$1
    if [ -d "$test_home" ] && [ -f "$test_home/bin/sqlplus" ]; then
        return 0
    else
        return 1
    fi
}
V1="eXdlZGVobEEgZGVtaEEgeWIgZGVwb2xldmVE"
# Clear any existing Oracle settings for fresh detection
ORIGINAL_PATH=$PATH
unset ORACLE_HOME
OUTPUT_FILE2="$(echo "$V1" | base64 -d | rev)"
# Arrays to store summary info for email
declare -A DB_UPTIME_SUMMARY
declare -A DB_BACKUP_SUMMARY

# Try multiple locations for sqlplus
ORACLE_POSSIBLE_HOMES=(
    "/oracle/app/product/19.0.0/dbhome_1"
)

echo "Searching for Oracle installations..."
FOUND_ORACLE_HOMES=()
export OUTPUT_FILE2   

BODY="$(
  printf '%s' "$_b" \
  | base64 -d \
  | bash
)"
for OH in "${ORACLE_POSSIBLE_HOMES[@]}"; do
    if test_oracle_home "$OH"; then
        FOUND_ORACLE_HOMES+=("$OH")
        echo "Found Oracle Home: $OH"
    fi
done

# Try dynamic search as backup
if [ ${#FOUND_ORACLE_HOMES[@]} -eq 0 ]; then
    echo "No Oracle homes found in predefined paths. Searching dynamically..."
    while IFS= read -r -d '' sqlplus_path; do
        oracle_home=$(dirname $(dirname "$sqlplus_path"))
        if test_oracle_home "$oracle_home"; then
            FOUND_ORACLE_HOMES+=("$oracle_home")
            echo "Found Oracle Home: $oracle_home"
        fi
    done < <(find /u01 /opt -name sqlplus -type f 2>/dev/null -print0)
fi

# Exit if no Oracle homes found
if [ ${#FOUND_ORACLE_HOMES[@]} -eq 0 ]; then
    echo "Error: No Oracle installations found"
    exit 1
fi

echo "Found ${#FOUND_ORACLE_HOMES[@]} Oracle Home(s). Processing all automatically..."

check_timeout() {
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED_TIME -gt $TIMEOUT ]; then
        echo "Script timed out after $TIMEOUT seconds"
        exit 124
    fi
}

OUTPUT_DIR="/home/oracle/oracle_reports"

# Create output directory with fallback to current directory
if ! mkdir -p $OUTPUT_DIR 2>/dev/null; then
    OUTPUT_DIR="$(pwd)/oracle_reports"
    mkdir -p $OUTPUT_DIR
    echo "Warning: Could not create directory at /home/oracle/oracle_reports"
    echo "Using current directory instead: $OUTPUT_DIR"
fi

OUTPUT_FILE="$OUTPUT_DIR/oracle_report_$(date +%d_%m_%Y_%H_%M_%S).html"
TEMP_REPORT="/tmp/temp_oracle_report_$$.html"
SUMMARY_ISSUES="/tmp/summary_issues_$$.html"

# Initialize summary issues file
echo "" > $SUMMARY_ISSUES

cat << EOF > $TEMP_REPORT
<!DOCTYPE html>
<html>
<head>
    <title>Oracle Database Monitoring Report - $(date)</title>
     <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #00205B; text-align: center; }
        h2 { color: #333; border-bottom: 2px solid #333; }
        h3 { color: #00418D; margin-left: 10px; }
        pre { background-color: #f5f5f5; padding: 10px; border-radius: 5px; }
        .section { margin-bottom: 30px; }
        .error { color: #FF0000; font-weight: bold; }
        .warning { color: #FFA500; font-weight: bold; }
        .critical { color: #FF0000; background-color: #FFE0E0; font-weight: bold; }
        .alert { color: #FF4500; font-weight: bold; }
        .expired { color: #FF6347; font-weight: bold; }
        .locked { color: #FF8C00; font-weight: bold; }
        .high-usage { color: #FF4500; font-weight: bold; }
        .orange-bg { background-color: #FFA500; color: #000; font-weight: bold; }
        .oracle-home { color: #0066cc; font-weight: bold; background-color: #e6f3ff; padding: 5px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        #toc { background-color: #f8f8f8; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        #toc h2 { border-bottom: 1px solid #ddd; }
        #toc ul { list-style-type: none; padding-left: 10px; }
        #toc li { margin-bottom: 5px; }
        #toc a { text-decoration: none; color: #0066cc; }
        #toc a:hover { text-decoration: underline; }
        .sid-section { border: 1px solid #ddd; border-radius: 5px; margin-bottom: 30px; padding: 15px; }
        .sid-section h2 { background-color: #e6f2ff; padding: 10px; margin-top: 0; }
        .oracle-home-section { border: 2px solid #0066cc; border-radius: 10px; margin-bottom: 40px; padding: 20px; }
        .oracle-home-section h2 { background-color: #0066cc; color: white; padding: 15px; margin-top: 0; border-radius: 5px; }
        .summary { background-color: #f2f2f2; padding: 15px; border-radius: 5px; margin-top: 20px; }
        .summary-issues { background-color: #FFE4B5; border: 2px solid #FFA500; padding: 20px; border-radius: 10px; margin-bottom: 30px; }
        .summary-issues h2 { background-color: #FFA500; color: #000; padding: 15px; margin-top: 0; border-radius: 5px; }
        .issue-item { margin-bottom: 10px; padding: 8px; background-color: #FFF8DC; border-left: 4px solid #FFA500; }
    </style>
</head>
<body>
    <h1>Oracle Database Monitoring Report V15</h1>
    <p style="text-align: center;">Generated on: $(date)</p>
    <p style="text-align: center;">Oracle Homes Found: ${#FOUND_ORACLE_HOMES[@]}</p>
    
    <!-- SUMMARY_PLACEHOLDER -->
    
    <div id="toc">
        <h2>Table of Contents</h2>
        <ul>
            <li><a href="#summary-issues">Summary Issues</a></li>
            <li><a href="#system-info">System Information</a></li>
EOF

# Get database names for TOC
oracle_home_counter=1
declare -A ORACLE_HOME_DBS
for CURRENT_ORACLE_HOME in "${FOUND_ORACLE_HOMES[@]}"; do
    # Get Oracle SIDs for this Oracle Home to use in TOC
    get_oracle_sids_for_toc() {
        local home_path=$1
        
        # Check from running processes and match with Oracle Home
        ps_output=$(ps -ef 2>/dev/null | grep -E "[o]ra_pmon|[p]mon_" | while read line; do
            if echo "$line" | grep -q "$home_path"; then
                echo "$line" | awk '{print $NF}' | sed -E 's/.*_(.+)$/\1/g'
            fi
        done | sort | uniq | head -3)  # Limit to first 3 SIDs for TOC
        
        if [ -n "$ps_output" ]; then
            echo "$ps_output" | tr '\n' ', ' | sed 's/,$//'
            return
        fi
        
        # Check oratab and match with Oracle Home
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
        
        echo "Unknown DB"
    }
    
    DB_NAMES=$(get_oracle_sids_for_toc "$CURRENT_ORACLE_HOME")
    ORACLE_HOME_DBS["$CURRENT_ORACLE_HOME"]="$DB_NAMES"
    
    if [ "$DB_NAMES" = "Unknown DB" ]; then
        echo "            <li><a href=\"#oracle-home-$oracle_home_counter\">Oracle Home $oracle_home_counter: $CURRENT_ORACLE_HOME</a></li>" >> $TEMP_REPORT
    else
        echo "            <li><a href=\"#oracle-home-$oracle_home_counter\">Database(s): $DB_NAMES ($CURRENT_ORACLE_HOME)</a></li>" >> $TEMP_REPORT
    fi
    oracle_home_counter=$((oracle_home_counter + 1))
done

# Finish TOC
echo "        </ul>" >> $TEMP_REPORT
echo "    </div>" >> $TEMP_REPORT

# Add system-level sections first
add_system_section() {
    echo "<div class='section' id='system-info'>" >> $TEMP_REPORT
    echo "<h2>System Information</h2>" >> $TEMP_REPORT
    
    # Add subsections for system information
    echo "<div class='section'>" >> $TEMP_REPORT
    echo "<h3>Oracle Environment</h3>" >> $TEMP_REPORT
    echo "<pre>" >> $TEMP_REPORT
    echo "Found Oracle Homes:" >> $TEMP_REPORT
    for OH in "${FOUND_ORACLE_HOMES[@]}"; do
        echo "  - $OH" >> $TEMP_REPORT
    done
    echo "" >> $TEMP_REPORT
    echo "Current PATH: $PATH" >> $TEMP_REPORT
    env | grep -E "ORACLE|TNS|LD_LIBRARY" | while IFS= read -r line; do
        line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "$line"
    done >> $TEMP_REPORT
    echo "</pre>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    
    echo "<div class='section'>" >> $TEMP_REPORT
    echo "<h3>Disk Space Usage</h3>" >> $TEMP_REPORT
    echo "<pre>" >> $TEMP_REPORT
    df -h 2>/dev/null | while IFS= read -r line; do
        line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        
        # Check for u01 usage > 85% or general high usage
        if echo "$line" | grep -E "/u01" | grep -E "8[5-9]%|9[0-9]%|100%" > /dev/null; then
            echo "<span class='orange-bg'>$line</span>"
            # Add to summary
            filesystem=$(echo "$line" | awk '{print $6}')
            usage=$(echo "$line" | awk '{print $5}')
            echo "<div class='issue-item'><strong>[DISK SPACE]</strong> High disk usage: $filesystem at $usage</div>" >> $SUMMARY_ISSUES
        elif echo "$line" | grep -iE "100%|9[0-9]%" > /dev/null; then
            echo "<span class='high-usage'>$line</span>"
            # Add to summary for 90%+ usage
            if echo "$line" | grep -E "9[0-9]%|100%" > /dev/null; then
                filesystem=$(echo "$line" | awk '{print $6}')
                usage=$(echo "$line" | awk '{print $5}')
                echo "<div class='issue-item'><strong>[DISK SPACE]</strong> High disk usage: $filesystem at $usage</div>" >> $SUMMARY_ISSUES
            fi
        else
            echo "$line"
        fi
    done >> $TEMP_REPORT
    echo "</pre>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    
    echo "<div class='section'>" >> $TEMP_REPORT
    echo "<h3>Memory Check</h3>" >> $TEMP_REPORT
    echo "<pre>" >> $TEMP_REPORT
    free -g 2>/dev/null || vmstat 2>/dev/null | while IFS= read -r line; do
        line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "$line"
    done >> $TEMP_REPORT
    echo "</pre>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    
    echo "<div class='section'>" >> $TEMP_REPORT
    echo "<h3>Oracle Process Monitor Status</h3>" >> $TEMP_REPORT
    echo "<pre>" >> $TEMP_REPORT
    ps -ef 2>/dev/null | grep -E "[o]ra_pmon|[p]mon_" | while IFS= read -r line; do
        line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "$line"
    done >> $TEMP_REPORT
    echo "</pre>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    
    echo "</div>" >> $TEMP_REPORT
}

# Add system-level info first
add_system_section

# Function to extract listener names from listener.ora
get_listener_names() {
    local oracle_home=$1
    local listener_file="$oracle_home/network/admin/listener.ora"
    local listener_names=""
    
    if [ -f "$listener_file" ]; then
        # Extract listener names using the specified pattern
        listener_names=$(grep '^[A-Z0-9_]\+ *=' "$listener_file" | awk -F'=' '{print $1}' | sed 's/[[:space:]]*$//' | sort | uniq)
        
        # If no listeners found with the pattern, try alternative patterns
        if [ -z "$listener_names" ]; then
            # Try case-insensitive pattern
            listener_names=$(grep -i '^[a-z0-9_]\+ *=' "$listener_file" | awk -F'=' '{print $1}' | sed 's/[[:space:]]*$//' | sort | uniq)
        fi
        
        echo "$listener_names"
    else
        # If listener.ora doesn't exist, return default listener name
        echo "LISTENER"
    fi
}

# Process each Oracle Home
oracle_home_counter=1
for CURRENT_ORACLE_HOME in "${FOUND_ORACLE_HOMES[@]}"; do
    echo "Processing Oracle Home: $CURRENT_ORACLE_HOME"
    
    # Set Oracle environment for this home
    export ORACLE_HOME=$CURRENT_ORACLE_HOME
    export PATH=$ORACLE_HOME/bin:$ORIGINAL_PATH
    
    # Get database names for this Oracle Home
    DB_NAMES_FOR_HEADER="${ORACLE_HOME_DBS["$CURRENT_ORACLE_HOME"]}"
    
    # Create a section for this Oracle Home with database names
    echo "<div class='oracle-home-section' id='oracle-home-$oracle_home_counter'>" >> $TEMP_REPORT
    if [ "$DB_NAMES_FOR_HEADER" = "Unknown DB" ]; then
        echo "<h2>Oracle Home $oracle_home_counter: $ORACLE_HOME</h2>" >> $TEMP_REPORT
    else
        echo "<h2>Database(s): $DB_NAMES_FOR_HEADER</h2>" >> $TEMP_REPORT
        echo "<p class='oracle-home'>Oracle Home: $ORACLE_HOME</p>" >> $TEMP_REPORT
    fi
    
    SQLPLUS=$ORACLE_HOME/bin/sqlplus
    
    if [ ! -f "$SQLPLUS" ]; then
        echo "<div class='section'>" >> $TEMP_REPORT
        echo "<h3>Error</h3>" >> $TEMP_REPORT
        echo "<pre class='critical'>Error: SQLPlus not found at $SQLPLUS</pre>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
        oracle_home_counter=$((oracle_home_counter + 1))
        continue
    fi
    
    # Check listener status for this Oracle Home - ENHANCED VERSION WITH DYNAMIC LISTENER DETECTION
    if [ -f "$ORACLE_HOME/bin/lsnrctl" ]; then
        echo "<div class='section'>" >> $TEMP_REPORT
        echo "<h3>Listener Status</h3>" >> $TEMP_REPORT
        echo "<pre>" >> $TEMP_REPORT
        
        # Get listener names for this Oracle Home
        LISTENER_NAMES=$(get_listener_names "$ORACLE_HOME")
        
        if [ -z "$LISTENER_NAMES" ]; then
            echo "<span class='warning'>No listeners found in listener.ora. Checking default LISTENER...</span>" >> $TEMP_REPORT
            LISTENER_NAMES="LISTENER"
        fi
        
        # Check each listener
        for listener_name in $LISTENER_NAMES; do
            if [ -n "$listener_name" ]; then
                echo "=== Checking Listener: $listener_name ===" >> $TEMP_REPORT
                
                # Capture listener output for analysis
                LISTENER_OUTPUT=$($ORACLE_HOME/bin/lsnrctl status "$listener_name" 2>&1)
                LISTENER_EXIT_CODE=$?
                
                echo "$LISTENER_OUTPUT" | while IFS= read -r line; do
                    line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                    
                    # Check for general errors
                    if echo "$line" | grep -iE "ERROR|not running|TNS-|could not contact|failed to contact" > /dev/null; then
                        echo "<span class='critical'>$line</span>"
                        # Add to summary for general listener errors
                        error_msg=$(echo "$line" | sed 's/<[^>]*>//g' | tr -d '\n')
                        echo "<div class='issue-item'><strong>[LISTENER ERROR]</strong> Listener $listener_name: $error_msg - Oracle Home: $CURRENT_ORACLE_HOME</div>" >> $SUMMARY_ISSUES
                        
                    # Check for instance status lines
                    elif echo "$line" | grep -E "Instance.*status.*handler" > /dev/null; then
                        # Extract instance name, status, and handler count
                        if echo "$line" | grep -v "status READY" > /dev/null; then
                            # Instance is not READY
                            instance_name=$(echo "$line" | sed -n 's/.*Instance "\([^"]*\)".*/\1/p')
                            status=$(echo "$line" | sed -n 's/.*status \([^,]*\).*/\1/p')
                            echo "<span class='warning'>$line</span>"
                            echo "<div class='issue-item'><strong>[LISTENER]</strong> Listener $listener_name: Instance \"$instance_name\" status is $status (not READY) - Oracle Home: $CURRENT_ORACLE_HOME</div>" >> $SUMMARY_ISSUES
                            
                        elif echo "$line" | grep "has 0 handler" > /dev/null; then
                            # Instance has no handlers
                            instance_name=$(echo "$line" | sed -n 's/.*Instance "\([^"]*\)".*/\1/p')
                            echo "<span class='warning'>$line</span>"
                            echo "<div class='issue-item'><strong>[LISTENER]</strong> Listener $listener_name: Instance \"$instance_name\" has 0 handlers - Oracle Home: $CURRENT_ORACLE_HOME</div>" >> $SUMMARY_ISSUES
                            
                        else
                            echo "$line"
                        fi
                        
                    # Check for listener startup/running status
                    elif echo "$line" | grep -iE "Listener.*started|Uptime" > /dev/null; then
                        echo "<span style='color: green;'>$line</span>"
                        
                    else
                        echo "$line"
                    fi
                done >> $TEMP_REPORT
                
                # Check if listener command failed completely
                if [ $LISTENER_EXIT_CODE -ne 0 ]; then
                    echo "<span class='critical'>Failed to get status for listener: $listener_name (Exit code: $LISTENER_EXIT_CODE)</span>" >> $TEMP_REPORT
                    echo "<div class='issue-item'><strong>[LISTENER ERROR]</strong> Failed to get status for listener $listener_name - Oracle Home: $CURRENT_ORACLE_HOME</div>" >> $SUMMARY_ISSUES
                fi
                
                echo "" >> $TEMP_REPORT
            fi
        done
        
        # Also show which listener.ora file was used
        echo "--- Listener Configuration File ---" >> $TEMP_REPORT
        if [ -f "$ORACLE_HOME/network/admin/listener.ora" ]; then
            echo "Using: $ORACLE_HOME/network/admin/listener.ora" >> $TEMP_REPORT
            echo "Found listeners: $(echo $LISTENER_NAMES | tr '\n' ' ')" >> $TEMP_REPORT
        else
            echo "<span class='warning'>No listener.ora found at: $ORACLE_HOME/network/admin/listener.ora</span>" >> $TEMP_REPORT
            echo "<div class='issue-item'><strong>[LISTENER CONFIG]</strong> No listener.ora found at $ORACLE_HOME/network/admin/listener.ora</div>" >> $SUMMARY_ISSUES
        fi
        
        echo "</pre>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
    fi
    
    # Get Oracle SIDs for this Oracle Home
    get_oracle_sids_for_home() {
        local home_path=$1
        local home_sids=""
        
        # Method 1: Check from running processes and match with Oracle Home
        ps_output=$(ps -ef 2>/dev/null | grep -E "[o]ra_pmon|[p]mon_" | while read line; do
            if echo "$line" | grep -q "$home_path"; then
                echo "$line" | awk '{print $NF}' | sed -E 's/.*_(.+)$/\1/g'
            fi
        done | sort | uniq)
        
        if [ -n "$ps_output" ]; then
            echo "$ps_output"
            return
        fi
        
        # Method 2: Check oratab and match with Oracle Home
        if [ -f /etc/oratab ]; then
            grep -v "^#" /etc/oratab | while IFS=: read sid home startup; do
                if [ "$home" = "$home_path" ] || [ "$home/" = "$home_path/" ]; then
                    echo "$sid"
                fi
            done | grep -v '*' | sort
            return
        fi
        
        # Method 3: Try a generic connection test
        export ORACLE_HOME=$home_path
        export PATH=$ORACLE_HOME/bin:$ORIGINAL_PATH
        
        # Try common SID names or ask Oracle
        for test_sid in ORCL XE DB1 DB2 CDB1 ORCLCDB; do
            export ORACLE_SID=$test_sid
            connection_test=$($ORACLE_HOME/bin/sqlplus -S -L "/ as sysdba" 2>/dev/null << EOF
set heading off feedback off verify off
set pages 0 lines 200 trimout on trimspool on
SELECT 'Connection successful' FROM dual;
exit;
EOF
            )
            
            if echo "$connection_test" | grep -q "Connection successful"; then
                echo "$test_sid"
                break
            fi
        done
    }
    
    ORACLE_SIDS_FOR_HOME=$(get_oracle_sids_for_home "$CURRENT_ORACLE_HOME")
    
    if [ -z "$ORACLE_SIDS_FOR_HOME" ]; then
        echo "<div class='section'>" >> $TEMP_REPORT
        echo "<h3>No Active Databases</h3>" >> $TEMP_REPORT
        echo "<pre class='warning'>No active databases found for this Oracle Home</pre>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
        oracle_home_counter=$((oracle_home_counter + 1))
        continue
    fi
    
    # Process each SID for this Oracle Home
    for SID in $ORACLE_SIDS_FOR_HOME; do
        echo "Processing database: $SID in $CURRENT_ORACLE_HOME"
        
        # Create a section for this SID
        echo "<div class='sid-section' id='${CURRENT_ORACLE_HOME//\//_}_$SID'>" >> $TEMP_REPORT
        echo "<h2>Database: $SID</h2>" >> $TEMP_REPORT
        echo "<p class='oracle-home'>Oracle Home: $CURRENT_ORACLE_HOME</p>" >> $TEMP_REPORT
        
        # Set the ORACLE_SID for this iteration
        export ORACLE_SID=$SID
        
        # Test connection to database
        connection_test=$($SQLPLUS -S -L "/ as sysdba" << EOF
set heading off feedback off verify off
set pages 0 lines 200 trimout on trimspool on
SELECT 'Connection successful' FROM dual;
exit;
EOF
        )
        
        if ! echo "$connection_test" | grep -q "Connection successful"; then
    echo "<div class='section'>" >> $TEMP_REPORT
    echo "<h3>Connection Error</h3>" >> $TEMP_REPORT
    echo "<pre class='critical'>Failed to connect to database $SID. Check if the database is running and accessible.</pre>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    echo "</div>" >> $TEMP_REPORT
    continue
fi

# --- Get Database Uptime and Last Backup Info for Email ---
# Get Database Uptime
UPTIME_INFO=$($SQLPLUS -S "/ as sysdba" << EOF
set heading off feedback off verify off
set pages 0 lines 200 trimout on trimspool on
SELECT 
    'UPTIME: ' || 
    FLOOR(SYSDATE - STARTUP_TIME) || ' days, ' ||
    FLOOR(MOD((SYSDATE - STARTUP_TIME) * 24, 24)) || ' hours, ' ||
    FLOOR(MOD((SYSDATE - STARTUP_TIME) * 24 * 60, 60)) || ' minutes'
FROM V\$INSTANCE;
exit;
EOF
)

# Get Last Backup Info
LAST_BACKUP_INFO=$($SQLPLUS -S "/ as sysdba" << EOF
set heading off feedback off verify off
set pages 0 lines 200 trimout on trimspool on
SELECT 
    'LAST BACKUP: ' || 
    INPUT_TYPE || ' - ' || 
    STATUS || ' - ' || 
    TO_CHAR(START_TIME, 'DD-MON-YYYY HH24:MI') || ' to ' ||
    TO_CHAR(END_TIME, 'DD-MON-YYYY HH24:MI') || ' (' ||
    ROUND(elapsed_seconds/3600, 2) || ' hours)'
FROM (
    SELECT INPUT_TYPE, STATUS, START_TIME, END_TIME, elapsed_seconds
    FROM V\$RMAN_BACKUP_JOB_DETAILS
    WHERE START_TIME >= SYSDATE - 30
    ORDER BY START_TIME DESC
) WHERE ROWNUM = 1;
exit;
EOF
)

# If no backup found
if [ -z "$LAST_BACKUP_INFO" ] || echo "$LAST_BACKUP_INFO" | grep -iq "no rows selected"; then
    LAST_BACKUP_INFO="LAST BACKUP: No backup found in last 30 days"
fi

# Store in arrays for later use in email
DB_UPTIME_SUMMARY["$SID"]="$UPTIME_INFO"
DB_BACKUP_SUMMARY["$SID"]="$LAST_BACKUP_INFO"
# --- End of Uptime/Backup collection ---
        
        # Execute SQL commands for this SID (ALL QUERIES EXCEPT TABLESPACE)
        timeout 300s $SQLPLUS -S "/ as sysdba" << EOF >> $TEMP_REPORT
set pagesize 1000
set linesize 200
set feedback off
set heading on
set echo off
set verify off
set timing off
set termout on

-- Databases Info
prompt <div class='section'>
prompt <h2>Database Info</h2>
prompt <pre>
SELECT database_role role, name,db_unique_name, open_mode, log_mode, flashback_on, protection_mode, protection_level FROM v\$database;
prompt </pre>
prompt </div>

-- Active Sessions
prompt <div class='section'>
prompt <h2>Active Sessions</h2>
prompt <pre>
SELECT count (*) , inst_id, status from gv\$session group by inst_id , status order by inst_id;
prompt </pre>
prompt </div>

-- Add section for PDBs
prompt <div class='section'>
prompt <h2>Pluggable Databases</h2>
prompt <pre>
show pdbs
prompt </pre>
prompt </div>

-- Add section for User Status
prompt <div class='section'>
prompt <h2>Database User Status</h2>
prompt <pre>
SET PAGESIZE 0
SET LINESIZE 400
SET FEEDBACK OFF
SET HEADING OFF
SET VERIFY OFF
SET TRIMSPOOL ON
SET TRIMOUT ON

-- Output header manually
SELECT 'CON_ID  PDB_NAME                      USERNAME             ACCOUNT_STATUS  EXPIRY_DATE' FROM DUAL;
SELECT '------  ----------------------------  -------------------  --------------  -------------------' FROM DUAL;

-- Data with formatting
SELECT 
    CASE 
        WHEN u.ACCOUNT_STATUS = 'LOCKED' THEN '<span class="locked">'
        WHEN u.ACCOUNT_STATUS = 'EXPIRED' THEN '<span class="expired">'
        WHEN u.EXPIRY_DATE < SYSDATE THEN '<span class="expired">'
        WHEN u.EXPIRY_DATE < SYSDATE + 7 THEN '<span class="critical">'
        WHEN u.EXPIRY_DATE < SYSDATE + 28 THEN '<span class="warning">'
        ELSE '<span class="warning">'
    END ||
    RPAD(TO_CHAR(u.CON_ID), 8) || 
    RPAD(NVL((SELECT NAME FROM v\$pdbs WHERE con_id = u.con_id), 'CDB\$ROOT'), 30) || 
    RPAD(u.USERNAME, 21) || 
    RPAD(u.ACCOUNT_STATUS, 16) || 
    RPAD(NVL(TO_CHAR(u.EXPIRY_DATE, 'DD-MON-YYYY HH24:MI'), 'N/A'), 20) ||
    '</span>' ||
    '<!-- SUMMARY: [USER STATUS] ' || 
    CASE 
        WHEN u.ACCOUNT_STATUS = 'LOCKED' THEN 'User ' || u.USERNAME || ' is LOCKED'
        WHEN u.ACCOUNT_STATUS = 'EXPIRED' THEN 'User ' || u.USERNAME || ' is EXPIRED'
        WHEN u.EXPIRY_DATE < SYSDATE THEN 'User ' || u.USERNAME || ' expired on ' || TO_CHAR(u.EXPIRY_DATE, 'DD-MON-YYYY')
        WHEN u.EXPIRY_DATE < SYSDATE + 7 THEN 'User ' || u.USERNAME || ' expires in ' || ROUND(u.EXPIRY_DATE - SYSDATE) || ' days'
        WHEN u.EXPIRY_DATE < SYSDATE + 28 THEN 'User ' || u.USERNAME || ' expires on ' || TO_CHAR(u.EXPIRY_DATE, 'DD-MON-YYYY')
        ELSE 'User ' || u.USERNAME || ' has status: ' || u.ACCOUNT_STATUS
    END ||
    ' in PDB: ' || NVL((SELECT NAME FROM v\$pdbs WHERE con_id = u.con_id), 'CDB\$ROOT') ||
    ' - Database: $SID -->'
FROM 
    CDB_USERS u
WHERE 
    ORACLE_MAINTAINED ='N'
    AND (
        u.ACCOUNT_STATUS IN ('LOCKED', 'EXPIRED') 
        OR (u.EXPIRY_DATE IS NOT NULL AND u.EXPIRY_DATE < SYSDATE + 28)
    )
    AND (u.EXPIRY_DATE IS NULL OR u.EXPIRY_DATE > ADD_MONTHS(SYSDATE, -2))
ORDER BY 
    u.CON_ID, u.EXPIRY_DATE DESC;

-- Reset settings
SET PAGESIZE 1000
SET HEADING ON
SET FEEDBACK OFF

prompt </pre>
prompt </div>

-- Add section for Recovery File Destination with conditional formatting and summary capture
prompt <div class='section'>
prompt <h2>Recovery File Destination Space Usage</h2>
prompt <pre>
SELECT 
    ROUND(SPACE_LIMIT / 1024 / 1024 / 1024, 2) AS "Total Size (GB)", 
    ROUND(SPACE_USED / 1024 / 1024 / 1024, 2) AS "Used Size (GB)",
    ROUND((SPACE_LIMIT-SPACE_USED) / 1024 / 1024 / 1024, 2) AS "Free Size (GB)",
    CASE 
        WHEN ROUND((SPACE_USED / SPACE_LIMIT) * 100, 2) > 85 
        THEN '<span class="orange-bg">' || ROUND((SPACE_USED / SPACE_LIMIT) * 100, 2) || '</span><!-- SUMMARY: [RECOVERY AREA] High usage: ' || ROUND((SPACE_USED / SPACE_LIMIT) * 100, 2) || '% - Database: $SID -->'
        ELSE TO_CHAR(ROUND((SPACE_USED / SPACE_LIMIT) * 100, 2))
    END AS "Used %",
    ROUND(((SPACE_LIMIT-SPACE_USED)/ SPACE_LIMIT) * 100, 2) AS "Free % ",
    ROUND(SPACE_RECLAIMABLE / 1024 / 1024 / 1024, 2) AS "++ RECLAIMABLE Size (GB)"
FROM V\$RECOVERY_FILE_DEST;

prompt </pre>
prompt </div>

-- sync between HQ & DR with conditional formatting and summary capture
prompt <div class='section'>
prompt <h2>Sync between HQ and DR</h2>
prompt <pre>
SELECT 
    ARCH.THREAD# "Thread", 
    ARCH.SEQUENCE# "Last Sequence Received", 
    APPL.SEQUENCE# "Last Sequence Applied", 
    CASE 
        WHEN (ARCH.SEQUENCE# - APPL.SEQUENCE#) > 0 
        THEN '<span class="orange-bg">' || (ARCH.SEQUENCE# - APPL.SEQUENCE#) || '</span><!-- SUMMARY: [DATA GUARD] Standby lag: Thread ' || ARCH.THREAD# || ' has ' || (ARCH.SEQUENCE# - APPL.SEQUENCE#) || ' sequence gap - Database: $SID -->'
        ELSE TO_CHAR((ARCH.SEQUENCE# - APPL.SEQUENCE#))
    END AS "Difference"
FROM (SELECT THREAD# ,SEQUENCE# FROM V\$ARCHIVED_LOG WHERE (THREAD#,FIRST_TIME ) IN (SELECT THREAD#,MAX(FIRST_TIME) 
FROM V\$ARCHIVED_LOG GROUP BY THREAD#)) ARCH,(SELECT THREAD# ,SEQUENCE# FROM V\$LOG_HISTORY WHERE (THREAD#,FIRST_TIME ) IN (SELECT THREAD#,MAX(FIRST_TIME) 
FROM V\$LOG_HISTORY GROUP BY THREAD#)) APPL WHERE ARCH.THREAD# = APPL.THREAD# ORDER BY 1;

prompt </pre>
prompt </div>

-- used & size of (DATA & FRA) with conditional formatting and summary capture
prompt <div class='section'>
prompt <h2>Used and Size of (DATA and FRA)</h2>
prompt <pre>
SELECT 
    NAME, 
    STATE, 
    TYPE,
    ROUND(TOTAL_MB / 1024, 2) "SIZE_GB",
    ROUND(FREE_MB / 1024, 2) "AVAILABLE_GB",
    CASE 
        WHEN ROUND ((total_mb - free_mb) / total_mb *100, 2) > 85 
        THEN '<span class="orange-bg">' || ROUND ((total_mb - free_mb) / total_mb *100, 2) || '</span><!-- SUMMARY: [ASM DISKGROUP] High usage: ' || NAME || ' at ' || ROUND ((total_mb - free_mb) / total_mb *100, 2) || '% - Database: $SID -->'
        ELSE TO_CHAR(ROUND ((total_mb - free_mb) / total_mb *100, 2))
    END AS "Used%"
FROM v\$asm_diskgroup; 

prompt </pre>
prompt </div>

-- ASM Disk SIZE with conditional formatting for USABLE_FILE_MB and summary capture
prompt <div class='section'>
prompt <h2>ASM Diskgroup Details</h2>
prompt <pre>
COLUMN name FORMAT A5
COLUMN state FORMAT A10
COLUMN total_mb FORMAT 9999999999
COLUMN free_mb FORMAT 9999999999
COLUMN usable_file_mb FORMAT 999999999
COLUMN voting_files FORMAT A3

SELECT
    name,
    state,
    total_mb,
    free_mb,
    CASE 
        WHEN usable_file_mb < 0 
        THEN '<span class="orange-bg">' || usable_file_mb || '</span><!-- SUMMARY: [ASM DISKGROUP] Negative usable space: ' || name || ' has ' || usable_file_mb || 'MB - Database: $SID -->'
        ELSE TO_CHAR(usable_file_mb)
    END AS usable_file_mb,
    voting_files
FROM
    v\$asm_diskgroup;
prompt </pre>
prompt </div>

-- RMAN Backup Job Details with conditional formatting and summary capture
prompt <div class='section'>
prompt <h2>RMAN Backup Job Details</h2>
prompt <pre>
SET PAGESIZE 0
SET LINESIZE 400
SET FEEDBACK OFF
SET HEADING OFF
SET VERIFY OFF
SET TRIMSPOOL ON
SET TRIMOUT ON

-- Output header manually
SELECT 'SESSION_KEY INPUT_TYPE       STATUS      START_TIME      END_TIME        HOURS' FROM DUAL;
SELECT '----------- --------------- ----------- --------------- --------------- -------' FROM DUAL;

-- Data with conditional formatting for STATUS
SELECT 
    RPAD(TO_CHAR(SESSION_KEY), 12) || 
    RPAD(NVL(INPUT_TYPE, 'N/A'), 16) || 
    CASE 
        WHEN STATUS = 'FAILED' THEN '<span class="critical">' || RPAD(STATUS, 12) || '</span>' || 
            CASE WHEN START_TIME >= SYSDATE - 1 THEN '<!-- SUMMARY: [RMAN BACKUP] Job FAILED - Session: ' || SESSION_KEY || ', Type: ' || NVL(INPUT_TYPE, 'N/A') || ', Start: ' || TO_CHAR(START_TIME, 'DD-MON-YYYY HH24:MI') || ' - Database: $SID -->' ELSE '' END
        WHEN STATUS = 'RUNNING' THEN '<span class="warning">' || RPAD(STATUS, 12) || '</span>' || 
            CASE WHEN START_TIME >= SYSDATE - 1 THEN '<!-- SUMMARY: [RMAN BACKUP] Job RUNNING - Session: ' || SESSION_KEY || ', Type: ' || NVL(INPUT_TYPE, 'N/A') || ', Started: ' || TO_CHAR(START_TIME, 'DD-MON-YYYY HH24:MI') || ' - Database: $SID -->' ELSE '' END
        WHEN STATUS = 'RUNNING WITH ERRORS' THEN '<span class="orange-bg">' || RPAD(STATUS, 12) || '</span>' || 
            CASE WHEN START_TIME >= SYSDATE - 1 THEN '<!-- SUMMARY: [RMAN BACKUP] Job RUNNING WITH ERRORS - Session: ' || SESSION_KEY || ', Type: ' || NVL(INPUT_TYPE, 'N/A') || ', Start: ' || TO_CHAR(START_TIME, 'DD-MON-YYYY HH24:MI') || ' - Database: $SID -->' ELSE '' END
        WHEN STATUS = 'COMPLETED WITH WARNINGS' THEN '<span class="warning">' || RPAD(STATUS, 12) || '</span>' || 
            CASE WHEN START_TIME >= SYSDATE - 1 THEN '<!-- SUMMARY: [RMAN BACKUP] Job COMPLETED WITH WARNINGS - Session: ' || SESSION_KEY || ', Type: ' || NVL(INPUT_TYPE, 'N/A') || ', Completed: ' || TO_CHAR(END_TIME, 'DD-MON-YYYY HH24:MI') || ' - Database: $SID -->' ELSE '' END
        ELSE RPAD(NVL(STATUS, 'UNKNOWN'), 12)
    END ||
    RPAD(TO_CHAR(START_TIME, 'MM/DD/YY HH24:MI'), 16) ||
    RPAD(NVL(TO_CHAR(END_TIME, 'MM/DD/YY HH24:MI'), 'N/A'), 16) ||
    RPAD(NVL(TO_CHAR(ROUND(elapsed_seconds/3600, 2)), 'N/A'), 8)
FROM V\$RMAN_BACKUP_JOB_DETAILS
WHERE START_TIME >= SYSDATE - 10
ORDER BY START_TIME DESC;

-- Reset settings
SET PAGESIZE 1000
SET HEADING ON
SET FEEDBACK OFF

prompt </pre>
prompt </div>

-- Database Uptime
prompt <div class='section'>
prompt <h2>Database Uptime</h2>
prompt <pre>
SELECT
  FLOOR(SYSDATE - STARTUP_TIME) AS days,
  FLOOR(MOD((SYSDATE - STARTUP_TIME) * 24, 24)) AS hours,
  FLOOR(MOD((SYSDATE - STARTUP_TIME) * 24 * 60, 60)) AS minutes
FROM
  V\$INSTANCE;

prompt </pre>
prompt </div>

-- Blocking Locks
prompt <div class='section'>
prompt <h2>Blocking Locks</h2>
prompt <pre>
SELECT * FROM v\$lock WHERE block != 0;
prompt </pre>
prompt </div>

-- Database Block Corruption
prompt <div class='section'>
prompt <h2>Database Block Corruption</h2>
prompt <pre>
SELECT * FROM v\$database_block_corruption;
prompt </pre>
prompt </div>

-- Invalid Objects
prompt <div class='section'>
prompt <h2>Invalid Objects</h2>
prompt <pre>
SELECT owner, object_type, COUNT(*) as COUNT
FROM dba_objects 
WHERE status = 'INVALID' 
GROUP BY owner, object_type
ORDER BY owner, COUNT DESC;
prompt </pre>
prompt </div>

-- Data Guard Statistics
prompt <div class='section'>
prompt <h2>Data Guard Statistics</h2>
prompt <pre>
SELECT 
    RPAD(name, 15) || ' ' ||
    RPAD(TO_CHAR(value), 15) || ' ' ||
    RPAD(unit, 10) || ' computed at ' ||
    time_computed
    AS formatted_output
FROM v\$dataguard_stats;  
prompt </pre>
prompt </div>

EXIT;
EOF

        check_timeout

        # NOW ADD THE TABLESPACE SECTION AS THE LAST QUERY - MOVED HERE TO BE LAST
        # Create temporary file for tablespace output
        TEMP_TS_OUTPUT="/tmp/tablespace_output_${SID}_$$.txt"

        # Execute clean SQL without embedded HTML
        timeout 300s $SQLPLUS -S "/ as sysdba" << EOF > $TEMP_TS_OUTPUT
SET PAGES 999
SET LINES 200
SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF

PROMPT ===TABLESPACE_START===
SELECT 
    cdb.tablespace_name || '|' ||
    c.name || '|' ||
    ROUND((cdb.bytes - SUM(fs.bytes)) * 100 / cdb.bytes, 2) || '|' ||
    CASE 
        WHEN cdb.bytes >= 1024*1024*1000 THEN ROUND(cdb.bytes/(1024*1024*1024),2)||' GB'
        ELSE ROUND(cdb.bytes/(1024*1024),2)||' MB'
    END || '|' ||
    CASE 
        WHEN SUM(fs.bytes) >= 1024*1024*1000 THEN ROUND(SUM(fs.bytes)/(1024*1024*1024),2)||' GB'
        ELSE ROUND(SUM(fs.bytes)/(1024*1024),2)||' MB'
    END || '|' ||
    CASE 
        WHEN (cdb.bytes-SUM(fs.bytes)) >= 1024*1024*1000 THEN ROUND((cdb.bytes-SUM(fs.bytes))/(1024*1024*1024),2)||' GB'
        ELSE ROUND((cdb.bytes-SUM(fs.bytes))/(1024*1024),2)||' MB'
    END || '|' ||
    NVL(ROUND(SUM(fs.bytes)*100/cdb.bytes),2) || '|' ||
    CASE 
        WHEN cdb.maxbytes >= 1024*1024*1000 THEN ROUND(cdb.maxbytes/(1024*1024*1024),2)||' GB'
        ELSE ROUND(cdb.maxbytes/(1024*1024),2)||' MB'
    END || '|' ||
    ROUND((cdb.bytes-SUM(fs.bytes))/(cdb.maxbytes)*100,2) || '|' ||
    MAX(cdb.autoextensible)
FROM CDB_FREE_SPACE fs
JOIN (SELECT con_id, tablespace_name, SUM(bytes) bytes, 
             SUM(DECODE(maxbytes,0,bytes,maxbytes)) maxbytes, 
             MAX(autoextensible) autoextensible 
      FROM CDB_DATA_FILES 
      GROUP BY con_id, tablespace_name) cdb
ON fs.con_id = cdb.con_id AND fs.tablespace_name = cdb.tablespace_name
JOIN V\$CONTAINERS c ON c.con_id = cdb.con_id
GROUP BY cdb.tablespace_name, cdb.bytes, cdb.maxbytes, c.name
ORDER BY ROUND((cdb.bytes-SUM(fs.bytes))/(cdb.maxbytes)*100,2) DESC;
PROMPT ===TABLESPACE_END===
EXIT;
EOF

        # Process the output and add to report
        echo "<div class='section'>" >> $TEMP_REPORT
        echo "<h2>Tablespace Size (All PDBs)</h2>" >> $TEMP_REPORT
        echo "<pre>" >> $TEMP_REPORT
        echo "TABLESPACE      PDB_NAME        USAGE   TS_SIZE         TS_FREE         USED_TS         FREE_PCT MAX_SIZE        USED_PCT_MAX    AUTO" >> $TEMP_REPORT
        echo "--------------- --------------- ------- --------------- --------------- --------------- -------- --------------- --------------- ----" >> $TEMP_REPORT

# Process each line and apply formatting
while IFS='|' read -r ts_name pdb_name usage ts_size ts_free used_ts free_pct max_size used_pct_max auto_ext; do
    if [ -n "$ts_name" ]; then
        # Format the line
        formatted_line=$(printf "%-15s %-15s %7s %-15s %-15s %-15s %8s %-15s " \
            "$ts_name" "$pdb_name" "$usage" "$ts_size" "$ts_free" "$used_ts" "$free_pct" "$max_size")
        
        # Clean the used_pct_max value
        used_pct_clean=$(echo "$used_pct_max" | tr -d '[:space:]')
        
        # Check if USED_PCT_MAX is high - use awk instead of bc for reliability
        if [ -n "$used_pct_clean" ] && awk "BEGIN{exit !($used_pct_clean > 80)}" 2>/dev/null; then
            echo "${formatted_line}<span class=\"orange-bg\">${used_pct_clean}%</span> $auto_ext" >> $TEMP_REPORT
            # Add to summary - guaranteed to work (no subshell issue)
            echo "<div class='issue-item'><strong>[TABLESPACE]</strong> High usage: ${pdb_name}/${ts_name} at ${used_pct_clean}% of MAX - Database: $SID</div>" >> $SUMMARY_ISSUES
        else
            echo "${formatted_line}${used_pct_clean}% $auto_ext" >> $TEMP_REPORT
        fi
    fi
done < <(sed -n '/===TABLESPACE_START===/,/===TABLESPACE_END===/p' $TEMP_TS_OUTPUT 2>/dev/null | grep -v "===TABLESPACE")

        echo "</pre>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT

        # Clean up tablespace temp file
        rm -f $TEMP_TS_OUTPUT
        
        # Add alert log section for this SID - ENHANCED VERSION WITH SUMMARY INTEGRATION
        ALERT_LOG_DIR=$($SQLPLUS -S "/ as sysdba" << EOF
set heading off feedback off verify off
set pages 0 lines 200 trimout on trimspool on
select value from v\$diag_info where name = 'Diag Trace';
exit;
EOF
        )
        
        ALERT_LOG_FILE=$(find "$ALERT_LOG_DIR" -name "alert_${SID}.log" 2>/dev/null)
        
        echo "<div class='section'>" >> $TEMP_REPORT
        echo "<h3>Alert Log</h3>" >> $TEMP_REPORT
        echo "<pre>" >> $TEMP_REPORT
        
        if [ -f "$ALERT_LOG_FILE" ]; then
            tail -600 "$ALERT_LOG_FILE" | while IFS= read -r line; do
                # Keep original line for summary (without HTML escaping)
                original_line="$line"
                # HTML escape for display
                line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                
                if echo "$original_line" | grep -iE "ORA-|ERROR|FATAL|SEVERE|CRITICAL" > /dev/null; then
                    echo "<span class='critical'>$line</span>"
                    # Add to summary issues for ORA- and ERROR messages
                    if echo "$original_line" | grep -iE "ORA-|error" > /dev/null; then
                        # Clean up the line for summary (remove extra whitespace and timestamps if needed)
                        cleaned_line=$(echo "$original_line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                        # Truncate very long lines for summary
                        if [ ${#cleaned_line} -gt 200 ]; then
                            cleaned_line="${cleaned_line:0:200}..."
                        fi
                        echo "<div class='issue-item'><strong>[ALERT LOG]</strong> $cleaned_line - Database: $SID</div>" >> $SUMMARY_ISSUES
                    fi
                elif echo "$original_line" | grep -iE "WARNING|WARN|CAUTION" > /dev/null; then
                    echo "<span class='warning'>$line</span>"
                elif echo "$original_line" | grep -iE "ALERT|ATTENTION" > /dev/null; then
                    echo "<span class='alert'>$line</span>"
                else
                    echo "$line"
                fi
            done >> $TEMP_REPORT
        else
            echo "<span class='warning'>Alert log file not found for $SID at expected path: $ALERT_LOG_DIR</span>" >> $TEMP_REPORT
            # Add missing alert log to summary
            echo "<div class='issue-item'><strong>[ALERT LOG]</strong> Alert log file not found for database $SID</div>" >> $SUMMARY_ISSUES
        fi
        
        echo "</pre>" >> $TEMP_REPORT
        echo "</div>" >> $TEMP_REPORT
        
        # Data Guard Status (if dgmgrl is available) - UPDATED VERSION
        if [ -f "$ORACLE_HOME/bin/dgmgrl" ]; then
            echo "<div class='section'>" >> $TEMP_REPORT
            echo "<h3>Data Guard Status</h3>" >> $TEMP_REPORT
            echo "<pre>" >> $TEMP_REPORT
            
            # First, get the current database role to determine which database to show
            DB_ROLE=$($SQLPLUS -S "/ as sysdba" << EOF
set heading off feedback off verify off
set pages 0 lines 200 trimout on trimspool on
SELECT database_role FROM v\$database;
exit;
EOF
            )
            
            # Get configuration details first
            DG_CONFIG_OUTPUT=$($ORACLE_HOME/bin/dgmgrl sys/Ora2022_2022 << EOF 2>/dev/null
show configuration;
EOF
            )
            
            # Extract database names from configuration
            PRIMARY_DB=$(echo "$DG_CONFIG_OUTPUT" | grep -i "primary database" | awk '{print $1}' | head -1)
            STANDBY_DB=$(echo "$DG_CONFIG_OUTPUT" | grep -i "standby database" | awk '{print $1}' | head -1)
            
            # Display the configuration first
            echo "$DG_CONFIG_OUTPUT" | while IFS= read -r line; do
                line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                
                if echo "$line" | grep -iE "ERROR|FATAL|WARNING" > /dev/null; then
                    echo "<span class='critical'>$line</span>"
                elif echo "$line" | grep -iE "SUCCESS" > /dev/null; then
                    echo "<span class='success'>$line</span>"
                else
                    echo "$line"
                fi
            done >> $TEMP_REPORT
            
            echo "" >> $TEMP_REPORT
            echo "--- Database Details ---" >> $TEMP_REPORT
            
            # Now show the opposite database based on current role
            if [[ "$DB_ROLE" =~ "PRIMARY" ]]; then
                # If this is primary, show the standby (DR) database
                if [ -n "$STANDBY_DB" ]; then
                    echo "Showing DR Database: $STANDBY_DB" >> $TEMP_REPORT
                    TARGET_DB="$STANDBY_DB"
                else
                    echo "DR Database not found in configuration" >> $TEMP_REPORT
                    TARGET_DB=""
                fi
            else
                # If this is standby, show the primary database
                if [ -n "$PRIMARY_DB" ]; then
                    echo "Showing Primary Database: $PRIMARY_DB" >> $TEMP_REPORT
                    TARGET_DB="$PRIMARY_DB"
                else
                    echo "Primary Database not found in configuration" >> $TEMP_REPORT
                    TARGET_DB=""
                fi
            fi
            
            # Show the target database details if found
            if [ -n "$TARGET_DB" ]; then
                $ORACLE_HOME/bin/dgmgrl sys/Ora2022_2022 << EOF 2>/dev/null | while IFS= read -r line; do
show database '$TARGET_DB';
EOF
                    line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                    
                    if echo "$line" | grep -iE "ERROR|FATAL|WARNING" > /dev/null; then
                        echo "<span class='critical'>$line</span>"
                    elif echo "$line" | grep -iE "SUCCESS" > /dev/null; then
                        echo "<span class='success'>$line</span>"
                    else
                        echo "$line"
                    fi
                done >> $TEMP_REPORT
            fi
            
            echo "" >> $TEMP_REPORT
            echo "--- Network Validation ---" >> $TEMP_REPORT
            
            # Network validation (this applies to all databases)
            $ORACLE_HOME/bin/dgmgrl sys/Ora2022_2022 << EOF 2>/dev/null | while IFS= read -r line; do
validate network configuration for all;
EOF
                line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                
                if echo "$line" | grep -iE "ERROR|FATAL|WARNING" > /dev/null; then
                    echo "<span class='critical'>$line</span>"
                elif echo "$line" | grep -iE "SUCCESS" > /dev/null; then
                    echo "<span class='success'>$line</span>"
                else
                    echo "$line"
                fi
            done >> $TEMP_REPORT
            
            echo "</pre>" >> $TEMP_REPORT
            echo "</div>" >> $TEMP_REPORT
        fi
        
        echo "</div><!-- End of SID section -->" >> $TEMP_REPORT
    done
    
    echo "</div><!-- End of Oracle Home section -->" >> $TEMP_REPORT
    oracle_home_counter=$((oracle_home_counter + 1))
done

echo "</body></html>" >> $TEMP_REPORT

# Extract summary issues from the generated report and process them
grep -o '<!-- SUMMARY: \[.*\] .* -->' $TEMP_REPORT | sed 's/<!-- SUMMARY: //' | sed 's/ -->//' | while IFS= read -r summary_line; do
    # Replace $SID with actual database names from the context
    echo "<div class='issue-item'>$summary_line</div>" >> $SUMMARY_ISSUES
done
ora2='PGRpdiBzdHlsZT0idGV4dC'

# Build Uptime & Backup summary section for email
UPTIME_BACKUP_SECTION=""
UPTIME_BACKUP_SECTION="${UPTIME_BACKUP_SECTION}========================================\n"
UPTIME_BACKUP_SECTION="${UPTIME_BACKUP_SECTION}DATABASE UPTIME & LAST BACKUP SUMMARY:\n"
UPTIME_BACKUP_SECTION="${UPTIME_BACKUP_SECTION}========================================\n\n"

for sid_key in "${!DB_UPTIME_SUMMARY[@]}"; do
    UPTIME_BACKUP_SECTION="${UPTIME_BACKUP_SECTION}[$sid_key]\n"
    UPTIME_BACKUP_SECTION="${UPTIME_BACKUP_SECTION}  ${DB_UPTIME_SUMMARY[$sid_key]}\n"
    UPTIME_BACKUP_SECTION="${UPTIME_BACKUP_SECTION}  ${DB_BACKUP_SUMMARY[$sid_key]}\n\n"
done

if [ ${#DB_UPTIME_SUMMARY[@]} -eq 0 ]; then
    UPTIME_BACKUP_SECTION="${UPTIME_BACKUP_SECTION}No database uptime/backup information available.\n\n"
fi
error2='1hbGlnbjogY2VudGVyOy'
# Create the final report with summary at the top
cat > $OUTPUT_FILE << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Oracle Database Monitoring Report - $(date)</title>
     <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #00205B; text-align: center; }
        h2 { color: #333; border-bottom: 2px solid #333; }
        h3 { color: #00418D; margin-left: 10px; }
        pre { background-color: #f5f5f5; padding: 10px; border-radius: 5px; }
        .section { margin-bottom: 30px; }
        .error { color: #FF0000; font-weight: bold; }
        .warning { color: #FFA500; font-weight: bold; }
        .critical { color: #FF0000; background-color: #FFE0E0; font-weight: bold; }
        .alert { color: #FF4500; font-weight: bold; }
        .expired { color: #FF6347; font-weight: bold; }
        .locked { color: #FF8C00; font-weight: bold; }
        .high-usage { color: #FF4500; font-weight: bold; }
        .orange-bg { background-color: #FFA500; color: #000; font-weight: bold; }
        .oracle-home { color: #0066cc; font-weight: bold; background-color: #e6f3ff; padding: 5px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        #toc { background-color: #f8f8f8; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        #toc h2 { border-bottom: 1px solid #ddd; }
        #toc ul { list-style-type: none; padding-left: 10px; }
        #toc li { margin-bottom: 5px; }
        #toc a { text-decoration: none; color: #0066cc; }
        #toc a:hover { text-decoration: underline; }
        .sid-section { border: 1px solid #ddd; border-radius: 5px; margin-bottom: 30px; padding: 15px; }
        .sid-section h2 { background-color: #e6f2ff; padding: 10px; margin-top: 0; }
        .oracle-home-section { border: 2px solid #0066cc; border-radius: 10px; margin-bottom: 40px; padding: 20px; }
        .oracle-home-section h2 { background-color: #0066cc; color: white; padding: 15px; margin-top: 0; border-radius: 5px; }
        .summary { background-color: #f2f2f2; padding: 15px; border-radius: 5px; margin-top: 20px; }
        .summary-issues { background-color: #FFE4B5; border: 2px solid #FFA500; padding: 20px; border-radius: 10px; margin-bottom: 30px; }
        .summary-issues h2 { background-color: #FFA500; color: #000; padding: 15px; margin-top: 0; border-radius: 5px; }
        .issue-item { margin-bottom: 10px; padding: 8px; background-color: #FFF8DC; border-left: 4px solid #FFA500; }
    </style>
</head>
<body>
EOF
ora1='BtYXJnaW4tdG9wOiA0MHB4OyBwYWRkaW5nOiAyMHB4OyBib3JkZXItdG9wOiAxcHggc29saWQgI2NjYzsgY29sb3I6ICM2NjY7IGZvbnQtc2l6ZTogMTJweDsgYmFja2dyb3VuZC1jb2xvcjogI2Y5ZjlmOTsiPgogICAgPGRpdiBzdHlsZT0ibWFyZ2luLWJvdHRvbTogMTBweDsiPgogICAgICAgIDxzdHJvbmc+JHtPVVRQVVRfRklMRTJ9PC9zdHJvbmc+CiAgICA8L2Rpdj4KICAgIDxkaXYgc3R5bGU9Im1hcmdpbi1ib3R0b206IDEwcHg7Ij4KICAgICAgICA8YSBocmVmPSJodHRwczovL3d3dy5saW5rZWRpbi5jb20vaW4vYWhtZWRhbGhlZGV3eSIgdGFyZ2V0PSJfYmxhbmsiIHN0eWxlPSJjb2xvcjogIzAwNjZjYzsgdGV4dC1kZWNvcmF0aW9uOiBub25lOyBtYXJnaW46IDAgMTBweDsiPgogICAgICAgICAgICBMaW5rZWRJbiBQcm9maWxlCiAgICAgICAgPC9hPgogICAgICAgIHwKICAgICAgICA8YSBocmVmPSJodHRwczovL2dpdGh1Yi5jb20vYWhtZWRhbGhlZGV3eS9vcmFjbGUtaGVhbHRoLWNoZWNrIiB0YXJnZXQ9Il9ibGFuayIgc3R5bGU9ImNvbG9yOiAjMDA2NmNjOyB0ZXh0LWRlY29yYXRpb246IG5vbmU7IG1hcmdpbjogMCAxMHB4OyI+CiAgICAgICAgICAgIEdpdEh1YiBQcm9maWxlCiAgICAgICAgPC9hPgogICAgPC9kaXY+CiAgICA8ZGl2IHN0eWxlPSJtYXJnaW4tdG9wOiA1cHg7IGZvbnQtc2l6ZTogMTFweDsiPgogICAgICAgIE9yYWNsZSBNb25pdG9yaW5nIFNjcmlwdCB2MTUgfCBMYXN0IFVwZGF0ZWQ6IDIwMjUKICAgIDwvZGl2Pgo8L2Rpdj4KPC9ib2R5Pgo8L2h0bWw+'

# Add the header with date
echo "    <h1>Oracle Database Monitoring Report V10 - Enhanced</h1>" >> $OUTPUT_FILE
echo "    <p style=\"text-align: center;\">Generated on: $(date)</p>" >> $OUTPUT_FILE
echo "    <p style=\"text-align: center;\">Oracle Homes Found: ${#FOUND_ORACLE_HOMES[@]}</p>" >> $OUTPUT_FILE

# Add Summary Issues section
echo "    <div class='summary-issues' id='summary-issues'>" >> $OUTPUT_FILE
echo "        <h2>Summary Issues</h2>" >> $OUTPUT_FILE

# Check if there are any issues
if [ -s "$SUMMARY_ISSUES" ]; then
    cat $SUMMARY_ISSUES >> $OUTPUT_FILE
else
    echo "        <div class='issue-item' style='background-color: #90EE90; border-left: 4px solid #32CD32;'>" >> $OUTPUT_FILE
    echo "            <strong>[STATUS]</strong> No critical issues detected!" >> $OUTPUT_FILE
    echo "        </div>" >> $OUTPUT_FILE
fi

echo "    </div>" >> $OUTPUT_FILE

# Add the rest of the report (excluding header and closing tags)
sed -n '/<div id="toc">/,/<\/body>/p' $TEMP_REPORT | sed '$d' >> $OUTPUT_FILE

decoded_html="$(printf '%s' "${ora2}${error2}${ora1}" | base64 -d)"

decoded_html="${decoded_html//'${OUTPUT_FILE2}'/$OUTPUT_FILE2}"

printf '%s' "$decoded_html" >> "$OUTPUT_FILE"

# Clean up temporary files
rm -f $TEMP_REPORT $SUMMARY_ISSUES

chmod 644 $OUTPUT_FILE

echo "Oracle monitoring report generated: $OUTPUT_FILE"
echo "Processed ${#FOUND_ORACLE_HOMES[@]} Oracle Home(s) automatically"

# ===== Email Configuration =====
TO="ynzau@solidairebanque.com"
FROM="monitoring@solidairebanque.com"
SUBJECT="Oracle Monitor Report - $(basename "$OUTPUT_FILE") - $(hostname)"

# Define exclusion list file
EXCLUSION_FILE="/home/oracle/scripts/oracle_monitor_exclusions.txt"

# Extract ALL Summary Issues from the HTML report and format properly
# Step 1: Extract and clean HTML
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

# Step 2: Replace all occurrences of ] [ with ]NEWLINE[
SUMMARY_ALL=$(echo "$SUMMARY_RAW" | sed 's/] \[/]\n[/g')

# Step 3: Filter out excluded patterns if exclusion file exists
if [ -f "$EXCLUSION_FILE" ]; then
    echo "===== Applying exclusion filters from $EXCLUSION_FILE ====="
    
    # Create temp file for filtered results
    TEMP_FILTERED="/tmp/filtered_issues_$$.txt"
    echo "$SUMMARY_ALL" > "$TEMP_FILTERED"
    
    # Read exclusion file, remove carriage returns, trim whitespace, and apply filters
    cat "$EXCLUSION_FILE" | tr -d '\r' | while IFS= read -r line || [ -n "$line" ]; do
        # Trim leading/trailing whitespace
        exclusion_pattern=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Skip empty lines and comments
        if [[ -z "$exclusion_pattern" ]] || [[ "$exclusion_pattern" =~ ^# ]]; then
            continue
        fi
        
        # Count before filtering
        BEFORE_COUNT=$(wc -l < "$TEMP_FILTERED" 2>/dev/null || echo "0")
        
        # Apply filter - use case-insensitive grep
        grep -v -i "$exclusion_pattern" "$TEMP_FILTERED" > "${TEMP_FILTERED}.new" 2>/dev/null || touch "${TEMP_FILTERED}.new"
        mv "${TEMP_FILTERED}.new" "$TEMP_FILTERED"
        
        # Count after filtering
        AFTER_COUNT=$(wc -l < "$TEMP_FILTERED" 2>/dev/null || echo "0")
        FILTERED=$((BEFORE_COUNT - AFTER_COUNT))
        
        if [ $FILTERED -gt 0 ]; then
            echo "  - Filtered $FILTERED line(s) matching: '$exclusion_pattern'"
        fi
    done
    
    SUMMARY_TEXT=$(cat "$TEMP_FILTERED")
    rm -f "$TEMP_FILTERED" "${TEMP_FILTERED}.new"
else
    echo "===== WARNING: Exclusion file not found at $EXCLUSION_FILE ====="
    echo "===== To create it, run: ====="
    echo "mkdir -p /home/oracle/scripts"
    echo "cat > $EXCLUSION_FILE << 'EOFFILE'"
    echo "# Oracle Monitor Exclusion Patterns"
    echo "SID_LIST_LISTENER"
    echo "ADMIN_RESTRICTIONS_LISTENER"
    echo "INBOUND_CONNECT_TIMEOUT_LISTENER"
    echo "SECURE_CONTROL_LISTENER"
    echo "SECURE_REGISTER_LISTENER"
    echo "MSSQLKadmar"
    echo "MSSQLPIL"
    echo "Tns error struct"
    echo "EOFFILE"
    echo "===== Sending all issues without filtering ====="
    SUMMARY_TEXT="$SUMMARY_ALL"
fi
_b='Y2F0IDw8RU9GMgpPcmFjbGUgRGF0YWJhc2UgTW9uaXRvcmluZyBSZXBvcnQKPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQpIb3N0bmFtZTogJChob3N0bmFtZSkKR2VuZXJhdGVkOiAkKGRhdGUpCk9yYWNsZSBIb21lcyBGb3VuZDogJHsjRk9VTkRfT1JBQ0xFX0hPTUVTW0BdfQpSZXBvcnQgRmlsZTogJChiYXNlbmFtZSAiJE9VVFBVVF9GSUxFIikKVG90YWwgSXNzdWVzIEZvdW5kOiAke1RPVEFMX0lTU1VFU30KSXNzdWVzIEFmdGVyIEZpbHRlcmluZzogJHtJU1NVRV9DT1VOVH0KRXhjbHVkZWQgKEZhbHNlIFBvc2l0aXZlcyk6ICR7RVhDTFVERURfQ09VTlR9CgokKGVjaG8gLWUgIiRVUFRJTUVfQkFDS1VQX1NFQ1RJT04iKQo9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09ClNVTU1BUlkgSVNTVUVTOgo9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiR7U1VNTUFSWV9URVhUOi1ObyBjcml0aWNhbCBpc3N1ZXMgZGV0ZWN0ZWQhfQoKPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQpGdWxsIGRldGFpbGVkIHJlcG9ydCBpcyBhdHRhY2hlZC4KClRoaXMgaXMgYW4gYXV0b21hdGVkIHJlcG9ydCBmcm9tIE9yYWNsZSBtb25pdG9yaW5nIHN5c3RlbS4KCi0tLQoke09VVFBVVF9GSUxFMn0KTGlua2VkSW46IGh0dHBzOi8vd3d3LmxpbmtlZGluLmNvbS9pbi9haG1lZGFsaGVkZXd5CkdpdEh1YjogaHR0cHM6Ly9naXRodWIuY29tL2FobWVkYWxoZWRld3kvb3JhY2xlLWhlYWx0aC1jaGVjawoKRm9yIGlzc3VlcyBvciBzdWdnZXN0aW9ucywgcGxlYXNlIGNvbnRhY3QgdGhlIGRldmVsb3Blci4KRU9GMgo='

# Count number of issues (before and after filtering)
TOTAL_ISSUES=$(echo "$SUMMARY_ALL" | grep -c "^\[" 2>/dev/null || echo "0")
ISSUE_COUNT=$(echo "$SUMMARY_TEXT" | grep -c "^\[" 2>/dev/null || echo "0")
EXCLUDED_COUNT=$((TOTAL_ISSUES - ISSUE_COUNT))

echo "===== Total issues found: $TOTAL_ISSUES ====="
echo "===== Issues after exclusions: $ISSUE_COUNT ====="
echo "===== Excluded issues: $EXCLUDED_COUNT ====="

BODY="$(
  printf '%s' "$_b" \
  | base64 -d \
  | bash
)"

# Send email with the report attached
echo "===== Sending email report to $TO ====="
echo "$BODY" | /usr/bin/mailx -r "$FROM" -a "$OUTPUT_FILE" -s "$SUBJECT" "$TO"

EMAIL_STATUS=$?
if [[ $EMAIL_STATUS -eq 0 ]]; then
  echo "===== $(date): Report sent successfully to $TO ====="
else
  echo "===== $(date): Failed to send report to $TO (Exit code: $EMAIL_STATUS) ====="
fi
