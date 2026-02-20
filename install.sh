#!/bin/bash
# Pasarguard Ultimate Backup - TUI Version
# by @AVASH_NET

# Auto install whiptail if missing
if ! command -v whiptail &> /dev/null; then
    apt update -y && apt install -y whiptail
fi

# ───────────── Banner ─────────────
clear
echo "==============================================="
echo "      🔹 Pasarguard Backup Installer 🔹"
echo "==============================================="

# ───────────── Basic Inputs ─────────────
DB_DISPLAY=$(whiptail --inputbox "Database name for Telegram display:" 8 60 "PasarguardDB" --title "Database Name" 3>&1 1>&2 2>&3)

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

# ───────────── Folder Multi Select ─────────────
FOLDER_SELECTION=$(whiptail --checklist "Select Folders to Backup (Use SPACE to select)" 20 80 10 \
"/var/lib/pasarguard/db-backup" "Database Backup Folder" ON \
"/opt/pasarguard/certs" "Certificates" ON \
"/opt/pasarguard/templates" "Templates" OFF \
"/opt/pasarguard/docker-compose.yml" "Docker Compose File" ON \
"/opt/pasarguard/.env" "Environment File" ON \
3>&1 1>&2 2>&3)

# Remove quotes
BACKUP_PATHS=$(echo $FOLDER_SELECTION | tr -d '"')

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
BACKUP_PATHS="$BACKUP_PATHS"
BACKUP_DIR="/var/lib/pasarguard/db-backup"
EOF

# ───────────── Install Backup Script ─────────────
cat > /usr/local/bin/pasarguard-backup.sh <<'EOB'
#!/bin/bash
LOG_FILE="/var/log/pasarguard-backup.log"
source /opt/pasarguard/backup-config.env

DATE=$(date +%F_%H-%M)
SQL_FILE="$BACKUP_DIR/${DB_DISPLAY}_$DATE.sql"
ZIP_FILE="/root/pasarguard-backup-$DATE.zip"

echo "[$(date)] Starting backup..." >> "$LOG_FILE"

/usr/bin/docker exec pasarguard-mysql-1 mysqldump --force --column-statistics=0 --user="$DB_USER" --password="$DB_PASS" "$DB_DISPLAY" > "$SQL_FILE" 2>> "$LOG_FILE"

FILES_TO_ZIP=("$SQL_FILE")

for path in $BACKUP_PATHS; do
    [ -e "$path" ] && FILES_TO_ZIP+=("$path")
done

/usr/bin/zip -r "$ZIP_FILE" "${FILES_TO_ZIP[@]}" >/dev/null 2>&1

TG_URL="https://api.telegram.org/bot$BOT_TOKEN/sendDocument"

curl -s -X POST "$TG_URL" \
-F chat_id="$CHAT_ID" \
-F caption="📦 Pasarguard Backup - $DATE" \
-F document=@"$ZIP_FILE" >> "$LOG_FILE"

rm -f "$SQL_FILE" "$ZIP_FILE"

echo "[$(date)] Backup completed." >> "$LOG_FILE"
echo "---------------------------------------" >> "$LOG_FILE"
EOB

chmod +x /usr/local/bin/pasarguard-backup.sh

# ───────────── Setup Cron ─────────────
(crontab -l 2>/dev/null; echo "0 */$INTERVAL * * * /usr/local/bin/pasarguard-backup.sh") | crontab -

# ───────────── First Backup ─────────────
/usr/local/bin/pasarguard-backup.sh

whiptail --msgbox "✅ Installation Complete!\n\nBackup runs every $INTERVAL hour(s).\nFirst backup sent to Telegram." 10 60
