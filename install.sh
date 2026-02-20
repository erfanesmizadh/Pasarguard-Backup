#!/bin/bash
# Pasarguard Ultimate Backup - FINAL Stable Version
# by @AVASH_NET

# ───────────── Install whiptail if missing ─────────────
if ! command -v whiptail &> /dev/null; then
    apt update -y && apt install -y whiptail
fi

clear
echo "==============================================="
echo "      🔹 Pasarguard Backup Installer 🔹"
echo "==============================================="

# ───────────── Basic Inputs ─────────────
DB_DISPLAY=$(whiptail --inputbox "Database name (EXACT name, e.g. pasarguard)\nLeave empty for ALL databases:" 10 70 "pasarguard" --title "Database Name" 3>&1 1>&2 2>&3)

BOT_TOKEN=$(whiptail --inputbox "Enter Telegram Bot Token:" 8 60 --title "Telegram Bot Token" 3>&1 1>&2 2>&3)

CHAT_ID=$(whiptail --inputbox "Enter Admin Telegram ID:" 8 60 --title "Telegram Chat ID" 3>&1 1>&2 2>&3)

DB_USER=$(whiptail --inputbox "Database Root User:" 8 60 "root" --title "DB User" 3>&1 1>&2 2>&3)

DB_PASS=$(whiptail --passwordbox "Database Root Password:" 8 60 --title "DB Password" 3>&1 1>&2 2>&3)

# ───────────── Interval ─────────────
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

# ───────────── Folder Selection ─────────────
FOLDER_SELECTION=$(whiptail --checklist "Select Pasarguard Files/Folders" 20 80 10 \
"/opt/pasarguard/certs" "Certificates" ON \
"/opt/pasarguard/templates" "Templates" ON \
"/opt/pasarguard/docker-compose.yml" "Docker Compose File" ON \
"/opt/pasarguard/.env" "Environment File" ON \
3>&1 1>&2 2>&3)

# Convert to newline list
BACKUP_PATHS=$(echo "$FOLDER_SELECTION" | tr -d '"' | tr ' ' '\n')

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
BACKUP_PATHS='$BACKUP_PATHS'
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

MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -n1)

if [ -z "$MYSQL_CONTAINER" ]; then
    echo "[$(date)] ERROR: MySQL container not found!" >> "$LOG_FILE"
    exit 1
fi

# ───────────── Dump Database ─────────────
if [ -z "$DB_DISPLAY" ]; then
    docker exec "$MYSQL_CONTAINER" mysqldump \
    --no-tablespaces --column-statistics=0 \
    -u"$DB_USER" -p"$DB_PASS" \
    --all-databases > "$SQL_FILE" 2>> "$LOG_FILE"
else
    docker exec "$MYSQL_CONTAINER" mysqldump \
    --no-tablespaces --column-statistics=0 \
    -u"$DB_USER" -p"$DB_PASS" \
    "$DB_DISPLAY" > "$SQL_FILE" 2>> "$LOG_FILE"
fi

if [ ! -s "$SQL_FILE" ]; then
    echo "[$(date)] ERROR: MySQL dump failed!" >> "$LOG_FILE"
    rm -f "$SQL_FILE"
    exit 1
fi

# ───────────── Collect Files ─────────────
FILES_TO_ZIP=("$SQL_FILE")

while IFS= read -r path; do
    if [ -e "$path" ]; then
        FILES_TO_ZIP+=("$path")
    else
        echo "[$(date)] WARNING: $path not found" >> "$LOG_FILE"
    fi
done <<< "$BACKUP_PATHS"

# ───────────── Zip ─────────────
zip -r "$ZIP_FILE" "${FILES_TO_ZIP[@]}" >> "$LOG_FILE" 2>&1

if [ ! -f "$ZIP_FILE" ]; then
    echo "[$(date)] ERROR: Zip failed!" >> "$LOG_FILE"
    exit 1
fi

# ───────────── Send Telegram ─────────────
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
-F chat_id="$CHAT_ID" \
-F caption="📦 Pasarguard Backup - $DATE" \
-F document=@"$ZIP_FILE" >> "$LOG_FILE"

if [ $? -ne 0 ]; then
    echo "[$(date)] ERROR: Telegram send failed!" >> "$LOG_FILE"
fi

rm -f "$SQL_FILE" "$ZIP_FILE"

echo "[$(date)] Backup completed." >> "$LOG_FILE"
echo "---------------------------------------" >> "$LOG_FILE"
EOB

chmod +x /usr/local/bin/pasarguard-backup.sh

# ───────────── Setup Cron (Clean old) ─────────────
(crontab -l 2>/dev/null | grep -v pasarguard-backup.sh; \
echo "0 */$INTERVAL * * * /usr/local/bin/pasarguard-backup.sh") | crontab -

# ───────────── First Run ─────────────
/usr/local/bin/pasarguard-backup.sh

whiptail --msgbox "✅ Installation Complete!\n\nBackup runs every $INTERVAL hour(s).\nFirst backup sent to Telegram." 10 60
