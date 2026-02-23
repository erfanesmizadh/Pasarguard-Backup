#!/bin/bash
# =====================================================
# PASARGUARD BACKUP - SIMPLE TCP READY VERSION
# Author: AVASH_NET
# Simple Bash, TUI Banner, TCP MySQL, Telegram Ready
# =====================================================

# ---------------- Directories ----------------
INSTALL_DIR="/opt/pasarguard-backup"
BACKUP_DIR="/var/lib/pasarguard/backup"
CONFIG_FILE="$INSTALL_DIR/config.env"
LOG_FILE="/var/log/pg-backup.log"
MAX_SIZE=$((45*1024*1024))  # 45MB

mkdir -p $INSTALL_DIR
mkdir -p $BACKUP_DIR
touch $LOG_FILE

# ---------------- Banner ----------------
echo "==============================================="
echo "      🔹 PASARGUARD BACKUP SYSTEM 🔹"
echo "==============================================="
echo "Backup Directory: $BACKUP_DIR"
echo "Log File: $LOG_FILE"
echo "-----------------------------------------------"

# ---------------- Load Config ----------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Config file not found! Create $CONFIG_FILE first."
    exit 1
fi

source $CONFIG_FILE

# ---------------- Start Backup ----------------
DATE=$(date +%F_%H-%M)
SQL_FILE="$BACKUP_DIR/db_$DATE.sql"
ZIP_FILE="$BACKUP_DIR/backup_$DATE.zip"

echo "[$(date)] Backup Started" >> $LOG_FILE

# ---------------- Detect MySQL ----------------
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -n1)

if [ -n "$MYSQL_CONTAINER" ]; then
    echo "[$(date)] Using MySQL Docker container: $MYSQL_CONTAINER" >> $LOG_FILE
    docker exec $MYSQL_CONTAINER mysqldump -h "$DB_HOST" -P "$DB_PORT" --user="$DB_USER" --password="$DB_PASS" ${DB_DISPLAY:-"--all-databases"} > $SQL_FILE 2>>$LOG_FILE
else
    echo "[$(date)] Using Local MySQL TCP" >> $LOG_FILE
    mysqldump -h "$DB_HOST" -P "$DB_PORT" --user="$DB_USER" --password="$DB_PASS" ${DB_DISPLAY:-"--all-databases"} > $SQL_FILE 2>>$LOG_FILE
fi

if [ ! -s "$SQL_FILE" ]; then
    echo "[$(date)] ERROR: MySQL dump failed!" >> $LOG_FILE
    exit 1
fi

# ---------------- Zip Backup ----------------
FILES_TO_ZIP=("$SQL_FILE")
for path in $BACKUP_PATHS; do
    [ -e "$path" ] && FILES_TO_ZIP+=("$path") && echo "[$(date)] Adding $path to ZIP" >> $LOG_FILE
done

zip -r "$ZIP_FILE" "${FILES_TO_ZIP[@]}" >> $LOG_FILE 2>&1

# ---------------- Send to Telegram ----------------
SIZE=$(stat -c%s "$ZIP_FILE")

send_file() {
    curl -s -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F caption="$1" \
    -F document=@"$2"
}

if [ "$SIZE" -le "$MAX_SIZE" ]; then
    CODE=$(send_file "📦 Pasarguard Backup - $DATE" "$ZIP_FILE")
    echo "[$(date)] Telegram Response: $CODE" >> $LOG_FILE
else
    split -b $MAX_SIZE -d "$ZIP_FILE" "${ZIP_FILE}.part"
    for part in ${ZIP_FILE}.part*; do
        CODE=$(send_file "📦 Pasarguard Backup Part: $(basename $part)" "$part")
        echo "[$(date)] Telegram Response Part: $CODE" >> $LOG_FILE
        rm -f "$part"
    done
fi

rm -f "$SQL_FILE" "$ZIP_FILE"

echo "[$(date)] Backup Completed" >> $LOG_FILE
echo "==============================================="
echo "Backup Finished ✅"
