#!/bin/bash
# =====================================================
# PASARGUARD BACKUP - FULL OPTIMIZED TCP VERSION
# Author: AVASH_NET
# Simple Bash, TCP MySQL, Telegram Ready, Large Files Safe
# Supports Custom Files
# =====================================================

# ---------------- Directories ----------------
INSTALL_DIR="/opt/pasarguard-backup"
BACKUP_DIR="/var/lib/pasarguard/backup"
CONFIG_FILE="$INSTALL_DIR/config.env"
LOG_FILE="/var/log/pg-backup.log"
MAX_SIZE=$((45*1024*1024))  # 45MB

mkdir -p "$INSTALL_DIR"
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

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
source "$CONFIG_FILE"

# ---------------- Validate Config ----------------
: "${DB_USER:?DB_USER not set in config.env}"
: "${DB_PASS:?DB_PASS not set in config.env}"
: "${DB_HOST:?DB_HOST not set in config.env}"
: "${DB_PORT:?DB_PORT not set in config.env}"
: "${BOT_TOKEN:?BOT_TOKEN not set in config.env}"
: "${CHAT_ID:?CHAT_ID not set in config.env}"
: "${BACKUP_PATHS[@]:?BACKUP_PATHS not set in config.env}"

# ---------------- Start Backup ----------------
DATE=$(date +%F_%H-%M)
SQL_FILE="$BACKUP_DIR/db_$DATE.sql"
ZIP_FILE="$BACKUP_DIR/backup_$DATE.zip"

echo "[$(date)] Backup Started" | tee -a "$LOG_FILE"

# ---------------- MySQL Dump ----------------
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -n1)

if [ -n "$MYSQL_CONTAINER" ]; then
    echo "[$(date)] Using MySQL Docker container: $MYSQL_CONTAINER" >> "$LOG_FILE"
    docker exec "$MYSQL_CONTAINER" mysqldump -h "$DB_HOST" -P "$DB_PORT" --user="$DB_USER" --password="$DB_PASS" ${DB_DISPLAY:-"--all-databases"} > "$SQL_FILE" 2>>"$LOG_FILE"
else
    echo "[$(date)] Using Local MySQL TCP" >> "$LOG_FILE"
    mysqldump -h "$DB_HOST" -P "$DB_PORT" --user="$DB_USER" --password="$DB_PASS" ${DB_DISPLAY:-"--all-databases"} > "$SQL_FILE" 2>>"$LOG_FILE"
fi

if [ ! -s "$SQL_FILE" ]; then
    echo "[$(date)] ERROR: MySQL dump failed!" | tee -a "$LOG_FILE"
    exit 1
fi

# ---------------- Cleanup Old Backups ----------------
find "$BACKUP_DIR" -type f -name "backup_*.zip" -mtime +7 -delete  # Keep 7 days

# ---------------- Custom Files Copy ----------------
CUSTOM_PATHS=(
"/مسیر/فایل/یا/پوشه/اول"
"/مسیر/فایل/یا/پوشه/دوم"
)
CUSTOM_DIR="$BACKUP_DIR/custom-files"
mkdir -p "$CUSTOM_DIR"

for item in "${CUSTOM_PATHS[@]}"; do
    if [ -e "$item" ]; then
        cp -r "$item" "$CUSTOM_DIR/"
        echo "[$(date)] INFO: Copied $item to $CUSTOM_DIR" >> "$LOG_FILE"
    else
        echo "[$(date)] WARNING: $item not found!" >> "$LOG_FILE"
    fi
done

# ---------------- Zip Backup ----------------
FILES_TO_ZIP=("$SQL_FILE")
for path in "${BACKUP_PATHS[@]}"; do
    [ -e "$path" ] && FILES_TO_ZIP+=("$path") && echo "[$(date)] Adding $path to ZIP" >> "$LOG_FILE"
done

# Include custom files
if [ -d "$CUSTOM_DIR" ]; then
    FILES_TO_ZIP+=("$CUSTOM_DIR")
fi

zip -r "$ZIP_FILE" "${FILES_TO_ZIP[@]}" >> "$LOG_FILE" 2>&1

# ---------------- Send to Telegram ----------------
SIZE=$(stat -c%s "$ZIP_FILE")

send_file() {
    curl -s --max-time 600 --retry 3 -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F caption="$1" \
    -F document=@"$2"
}

TELEGRAM_CAPTION="📦 Pasarguard Backup - $DATE  
Brand: @AVASH_NET  
✅ All data & custom files included"

if [ "$SIZE" -le "$MAX_SIZE" ]; then
    RESPONSE=$(send_file "$TELEGRAM_CAPTION" "$ZIP_FILE")
    echo "[$(date)] Telegram Response: $RESPONSE" >> "$LOG_FILE"
else
    echo "[$(date)] Large file detected, splitting..." >> "$LOG_FILE"
    split -b $MAX_SIZE -d "$ZIP_FILE" "${ZIP_FILE}.part"
    for part in ${ZIP_FILE}.part*; do
        RESPONSE=$(send_file "📦 Pasarguard Backup Part: $(basename $part)  
Brand: @AVASH_NET" "$part")
        echo "[$(date)] Telegram Response Part: $RESPONSE" >> "$LOG_FILE"
        rm -f "$part"
    done
fi

# ---------------- Cleanup ----------------
rm -f "$SQL_FILE" "$ZIP_FILE"

echo "[$(date)] Backup Completed" >> "$LOG_FILE"
echo "==============================================="
echo "Backup Finished ✅"
echo "Brand: @AVASH_NET"
