#!/bin/bash
# Pasarguard Ultimate Backup Installer - Final Version
# by @AVASH_NET (Full Smart Version)

# ───────────── Dependencies ─────────────
if ! command -v whiptail &> /dev/null; then
    apt update -y && apt install -y whiptail zip curl docker.io
fi

clear
echo "==============================================="
echo "      🔹 Pasarguard Backup Installer 🔹"
echo "==============================================="

# ───────────── Basic Inputs ─────────────
DB_DISPLAY=$(whiptail --inputbox "Database name (leave empty for ALL databases):" 8 60 "pasarguard" --title "Database Name" 3>&1 1>&2 2>&3)
BOT_TOKEN=$(whiptail --inputbox "Enter Telegram Bot Token:" 8 60 --title "Telegram Bot Token" 3>&1 1>&2 2>&3)
CHAT_ID=$(whiptail --inputbox "Enter Admin Telegram ID:" 8 60 --title "Telegram Chat ID" 3>&1 1>&2 2>&3)
DB_USER=$(whiptail --inputbox "Database Root User:" 8 60 "root" --title "DB User" 3>&1 1>&2 2>&3)
DB_PASS=$(whiptail --passwordbox "Database Root Password:" 8 60 --title "DB Password" 3>&1 1>&2 2>&3)

# ───────────── Interval Selection ─────────────
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

# ───────────── Paths to Backup ─────────────
BACKUP_PATHS=(
"/opt/pasarguard"
"/opt/pg-node"
"/var/lib/pasarguard"
"/var/lib/pg-node"
)

# ───────────── Save Config ─────────────
CONFIG_FILE="/opt/pasarguard/backup-config.env"
mkdir -p /opt/pasarguard
mkdir -p /var/lib/pasarguard/db-backup
touch /var/log/pasarguard-backup.log

cat > "$CONFIG_FILE" <<EOF
DB_DISPLAY="$DB_DISPLAY"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_USER="$DB_USER"
DB_PASS="$DB_PASS"
INTERVAL="$INTERVAL"
BACKUP_PATHS="${BACKUP_PATHS[*]}"
BACKUP_DIR="/var/lib/pasarguard/db-backup"
EOF

# ───────────── Install Backup Script ─────────────
cat > /usr/local/bin/pasarguard-backup.sh <<'EOB'
#!/bin/bash
LOG_FILE="/var/log/pasarguard-backup.log"
source /opt/pasarguard/backup-config.env

DATE=$(date +%F_%H-%M)
SQL_FILE="$BACKUP_DIR/${DB_DISPLAY:-all}_$DATE.sql"
ZIP_FILE="/root/pasarguard-backup-$DATE.zip"

echo "[$(date)] Starting backup..." >> "$LOG_FILE"

# Delete old backups
echo "[$(date)] Cleaning old backups..." >> "$LOG_FILE"
rm -f /root/pasarguard-backup-*.zip
rm -f "$BACKUP_DIR"/*.sql

# Detect MySQL container
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -n1)
if [ -z "$MYSQL_CONTAINER" ]; then
    echo "[$(date)] ERROR: MySQL container not found!" >> "$LOG_FILE"
    exit 1
fi

# Dump Database
if [ -z "$DB_DISPLAY" ]; then
    docker exec "$MYSQL_CONTAINER" mysqldump --no-tablespaces --column-statistics=0 --user="$DB_USER" --password="$DB_PASS" --all-databases > "$SQL_FILE" 2>> "$LOG_FILE"
else
    docker exec "$MYSQL_CONTAINER" mysqldump --no-tablespaces --column-statistics=0 --user="$DB_USER" --password="$DB_PASS" "$DB_DISPLAY" > "$SQL_FILE" 2>> "$LOG_FILE"
fi

if [ ! -s "$SQL_FILE" ]; then
    echo "[$(date)] ERROR: MySQL dump failed!" >> "$LOG_FILE"
    rm -f "$SQL_FILE"
    exit 1
fi

FILES_TO_ZIP=("$SQL_FILE")

# Add backup paths
for path in $BACKUP_PATHS; do
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
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
-F chat_id="$CHAT_ID" \
-F caption="📦 Pasarguard + PG-Node Backup - $DATE" \
-F document=@"$ZIP_FILE" >> "$LOG_FILE"

# Clean local backup files
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
