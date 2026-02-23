#!/bin/bash
# ==============================================
# Pasarguard Ultimate Backup Installer - Pro Version
# Author: @AVASH_NET
# Supports MySQL root & Pasarguard user
# ==============================================

# ───────────── Dependencies ─────────────
if ! command -v whiptail &> /dev/null; then
    apt update -y && apt install -y whiptail zip curl docker.io
fi

clear
echo "==============================================="
echo "      🔹 Pasarguard Backup Installer 🔹"
echo "==============================================="

# ───────────── User Inputs ─────────────
DB_DISPLAY=$(whiptail --inputbox "Database name (leave empty for ALL databases):" 8 60 "pasarguard" --title "Database Name" 3>&1 1>&2 2>&3)
BOT_TOKEN=$(whiptail --inputbox "Enter Telegram Bot Token:" 8 60 --title "Telegram Bot Token" 3>&1 1>&2 2>&3)
CHAT_ID=$(whiptail --inputbox "Enter Admin Telegram ID:" 8 60 --title "Telegram Chat ID" 3>&1 1>&2 2>&3)
DB_USER=$(whiptail --inputbox "Database User:" 8 60 "root" --title "DB User" 3>&1 1>&2 2>&3)
DB_PASS=$(whiptail --passwordbox "Database Password:" 8 60 --title "DB Password" 3>&1 1>&2 2>&3)

INTERVAL=$(whiptail --menu "Select Backup Interval (Every X Hours)" 20 60 10 \
"1"  "Every 1 Hour" \
"2"  "Every 2 Hours" \
"3"  "Every 3 Hours" \
"4"  "Every 4 Hours" \
"6"  "Every 6 Hours" \
"8"  "Every 8 Hours" \
"12" "Every 12 Hours" \
"24" "Every 24 Hours" \
3>&1 1>&2 2>&3)

# ───────────── Backup Paths ─────────────
BACKUP_PATHS=(
"/opt/pasarguard"
"/opt/pg-node"
"/var/lib/pasarguard"
"/var/lib/pg-node"
)

BACKUP_DIR="/var/lib/pasarguard/tmp"
mkdir -p "$BACKUP_DIR"
touch /var/log/pasarguard-backup.log
chmod 644 /var/log/pasarguard-backup.log

# ───────────── Save Config ─────────────
CONFIG_FILE="/opt/pasarguard/backup-config.env"
mkdir -p /opt/pasarguard
cat > "$CONFIG_FILE" <<EOF
DB_DISPLAY="$DB_DISPLAY"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_USER="$DB_USER"
DB_PASS="$DB_PASS"
INTERVAL="$INTERVAL"
BACKUP_PATHS=("${BACKUP_PATHS[@]}")
BACKUP_DIR="$BACKUP_DIR"
EOF
chmod 600 "$CONFIG_FILE"

# ───────────── Backup Script ─────────────
cat > /usr/local/bin/pasarguard-backup.sh <<'EOB'
#!/bin/bash
LOG_FILE="/var/log/pasarguard-backup.log"
source /opt/pasarguard/backup-config.env

DATE=$(date +%F_%H-%M)
SQL_FILE="$BACKUP_DIR/${DB_DISPLAY:-all}_$DATE.sql"
ZIP_FILE="$BACKUP_DIR/pasarguard-backup-$DATE.zip"

echo "[$(date)] Starting backup..." >> "$LOG_FILE"

# Cleanup old backups
echo "[$(date)] Cleaning old backups..." >> "$LOG_FILE"
rm -f "$BACKUP_DIR"/*.zip
rm -f "$BACKUP_DIR"/*.sql

# Detect MySQL container
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -n1)

if [ -n "$MYSQL_CONTAINER" ]; then
    echo "[$(date)] MySQL container found: $MYSQL_CONTAINER" >> "$LOG_FILE"
    if [ -z "$DB_DISPLAY" ]; then
        docker exec "$MYSQL_CONTAINER" mysqldump --no-tablespaces --column-statistics=0 --user="$DB_USER" --password="$DB_PASS" --all-databases > "$SQL_FILE" 2>> "$LOG_FILE"
    else
        docker exec "$MYSQL_CONTAINER" mysqldump --no-tablespaces --column-statistics=0 --user="$DB_USER" --password="$DB_PASS" "$DB_DISPLAY" > "$SQL_FILE" 2>> "$LOG_FILE"
    fi
else
    echo "[$(date)] No MySQL container, using local MySQL..." >> "$LOG_FILE"
    if [ -z "$DB_DISPLAY" ]; then
        mysqldump --user="$DB_USER" --password="$DB_PASS" --all-databases > "$SQL_FILE" 2>> "$LOG_FILE"
    else
        mysqldump --user="$DB_USER" --password="$DB_PASS" "$DB_DISPLAY" > "$SQL_FILE" 2>> "$LOG_FILE"
    fi
fi

if [ ! -s "$SQL_FILE" ]; then
    echo "[$(date)] ERROR: MySQL dump failed!" >> "$LOG_FILE"
    rm -f "$SQL_FILE"
    exit 1
fi

FILES_TO_ZIP=("$SQL_FILE")

# Add backup paths
for path in "${BACKUP_PATHS[@]}"; do
    if [ -e "$path" ]; then
        FILES_TO_ZIP+=("$path")
        echo "[$(date)] INFO: Adding $path to backup" >> "$LOG_FILE"
    else
        echo "[$(date)] WARNING: $path not found!" >> "$LOG_FILE"
    fi
done

# Create zip
zip -r "$ZIP_FILE" "${FILES_TO_ZIP[@]}" >> "$LOG_FILE" 2>&1
if [ ! -f "$ZIP_FILE" ]; then
    echo "[$(date)] ERROR: Zip creation failed!" >> "$LOG_FILE"
    exit 1
fi

# Send to Telegram
response=$(curl -s -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
-F chat_id="$CHAT_ID" \
-F caption="📦 Pasarguard + PG-Node Backup - $DATE" \
-F document=@"$ZIP_FILE")

echo "[$(date)] Telegram response: $response" >> "$LOG_FILE"

# Cleanup
rm -f "$SQL_FILE" "$ZIP_FILE"

echo "[$(date)] Backup completed." >> "$LOG_FILE"
echo "---------------------------------------" >> "$LOG_FILE"
EOB

chmod +x /usr/local/bin/pasarguard-backup.sh

# ───────────── Setup Cron ─────────────
(crontab -l 2>/dev/null | grep -v pasarguard-backup.sh; \
echo "0 */$INTERVAL * * * /usr/local/bin/pasarguard-backup.sh") | crontab -

# ───────────── First Backup ─────────────
/usr/local/bin/pasarguard-backup.sh

whiptail --msgbox "✅ Installation Complete!\n\nBackup runs every $INTERVAL hour(s).\nFirst backup sent to Telegram." 12 60
