#!/bin/bash
# =====================================================
# PASARGUARD BACKUP - OPTIMIZED TCP VERSION
# Author: AVASH_NET
# Ultra Simple, TCP MySQL, Telegram Ready, Large Files Safe
# Branding Included
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
DATE=$(date +"%Y-%m-%d_%H-%M")
SQL_FILE="$BACKUP_DIR/db_$DATE.sql"
ZIP_FILE="$BACKUP_DIR/backup_$DATE.zip"

echo "[$(date)] Backup Started" | tee -a "$LOG_FILE"

# ---------------- MySQL Dump ----------------
mysqldump -h "$DB_HOST" -P "$DB_PORT" --user="$DB_USER" --password="$DB_PASS" ${DB_DISPLAY:-"--all-databases"} > "$SQL_FILE" 2>>"$LOG_FILE"

if [ ! -s "$SQL_FILE" ]; then
    echo "[$(date)] ERROR: MySQL dump failed!" | tee -a "$LOG_FILE"
    exit 1
fi

# ---------------- Cleanup Old Backups ----------------
find "$BACKUP_DIR" -type f -name "backup_*.zip" -mtime +7 -delete  # Keep 7 days

# ---------------- Zip Backup ----------------
FILES_TO_ZIP=("$SQL_FILE")
for path in "${BACKUP_PATHS[@]}"; do
    if [ -e "$path" ]; then
        FILES_TO_ZIP+=("$path")
        echo "[$(date)] Adding $path to ZIP" >> "$LOG_FILE"
    else
        echo "[$(date)] WARNING: $path not found!" >> "$LOG_FILE"
    fi
done

zip -r "$ZIP_FILE" "${FILES_TO_ZIP[@]}" >> "$LOG_FILE" 2>&1

# ---------------- Send to Telegram (Branded) ----------------
SIZE=$(stat -c%s "$ZIP_FILE")
BRAND="🔹 Backup by @AVASH_NET 🔹"
DATE_TEXT=$(date +"%Y-%m-%d %H:%M:%S")
FILE_SIZE_HUMAN=$(du -h "$ZIP_FILE" | cut -f1)

send_file() {
    curl -s --max-time 600 --retry 3 -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F caption="$1" \
    -F document=@"$2"
}

if [ "$SIZE" -le "$MAX_SIZE" ]; then
    CAPTION="📦 *Pasarguard Backup Completed*\n$BRAND\n🕒 Date: $DATE_TEXT\n💾 Size: $FILE_SIZE_HUMAN\n📁 Total Files: ${#FILES_TO_ZIP[@]}"
    RESPONSE=$(send_file "$CAPTION" "$ZIP_FILE")
    echo "[$(date)] Telegram Response: $RESPONSE" >> "$LOG_FILE"
else
    echo "[$(date)] Large file detected, splitting..." >> "$LOG_FILE"
    split -b $MAX_SIZE -d "$ZIP_FILE" "${ZIP_FILE}.part"
    PART_NUM=1
    for part in ${ZIP_FILE}.part*; do
        PART_SIZE=$(du -h "$part" | cut -f1)
        CAPTION="📦 *Pasarguard Backup Part $PART_NUM*\n$BRAND\n🕒 Date: $DATE_TEXT\n💾 Size: $PART_SIZE\n📁 Files in this part: $(ls "${part}"* | wc -l)"
        RESPONSE=$(send_file "$CAPTION" "$part")
        echo "[$(date)] Telegram Response Part $PART_NUM: $RESPONSE" >> "$LOG_FILE"
        rm -f "$part"
        ((PART_NUM++))
    done
fi

# ---------------- Cleanup ----------------
rm -f "$SQL_FILE" "$ZIP_FILE"

echo "[$(date)] Backup Completed" >> "$LOG_FILE"
echo "==============================================="
echo "Backup Finished ✅"
