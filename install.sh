#!/bin/bash
# =====================================================
# PASARGUARD BACKUP & MANAGEMENT - FINAL STABLE
# Author: AVASH_NET
# MySQL TCP • Telegram • Cron • Full Remove • Secure
# =====================================================

# ---------------- Root Check ----------------
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

# ---------------- Colors ----------------
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"
BLUE="\e[34m"; MAGENTA="\e[35m"; CYAN="\e[36m"; RESET="\e[0m"

# ---------------- Paths ----------------
INSTALL_DIR="/opt/pasarguard-backup"
BACKUP_DIR="/var/lib/pasarguard/backup"
CONFIG_FILE="$INSTALL_DIR/config.env"
LOG_FILE="/var/log/pg-backup.log"
CRON_FILE="/etc/cron.d/pasarguard-backup"
MAX_SIZE=$((45*1024*1024))

mkdir -p "$INSTALL_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# ---------------- Install Requirements ----------------
install_deps() {
apt update -y >/dev/null 2>&1
apt install -y mariadb-client zip curl nano cron >/dev/null 2>&1
}

# ---------------- Setup Wizard ----------------
setup_config() {

clear
echo -e "${CYAN}"
echo "================================================="
echo "        🔧 PASARGUARD BACKUP CONFIG SETUP"
echo "================================================="
echo -e "${RESET}"

mkdir -p "$INSTALL_DIR"

read -p "Database Host (default 127.0.0.1): " DB_HOST
DB_HOST=${DB_HOST:-127.0.0.1}

read -p "Database Port (default 3306): " DB_PORT
DB_PORT=${DB_PORT:-3306}

read -p "Database Username: " DB_USER

read -s -p "Database Password: " DB_PASS
echo

read -p "Database Name (or type ALL): " DB_NAME
if [[ "$DB_NAME" == "ALL" || "$DB_NAME" == "all" ]]; then
    DB_DISPLAY="--all-databases"
else
    DB_DISPLAY="$DB_NAME"
fi

read -p "Telegram Bot Token: " BOT_TOKEN
read -p "Telegram Numeric Chat ID: " CHAT_ID

read -p "Paths to Backup (space separated, default: /opt/pasarguard /var/www/html): " BACKUP_PATHS
BACKUP_PATHS=${BACKUP_PATHS:-"/opt/pasarguard /var/www/html"}

cat > "$CONFIG_FILE" <<EOF
DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"
DB_USER="$DB_USER"
DB_PASS="$DB_PASS"
DB_DISPLAY="$DB_DISPLAY"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
BACKUP_PATHS="$BACKUP_PATHS"
EOF

chmod 600 "$CONFIG_FILE"

echo -e "${GREEN}Config saved successfully ✅${RESET}"
sleep 2
}

# ---------------- Load Config ----------------
load_config() {
if [ ! -f "$CONFIG_FILE" ]; then
echo -e "${RED}Config not found! Run Setup first.${RESET}"
return 1
fi
source "$CONFIG_FILE"
}

# ---------------- Test MySQL ----------------
test_mysql() {
load_config || return
mysql -h "$DB_HOST" -P "$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -e "exit" >/dev/null 2>&1
if [ $? -eq 0 ]; then
echo -e "${GREEN}MySQL Connection OK ✅${RESET}"
else
echo -e "${RED}MySQL Connection Failed ❌${RESET}"
fi
}

# ---------------- Test Telegram ----------------
test_telegram() {
load_config || return
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
-d chat_id="$CHAT_ID" \
-d text="✅ Pasarguard Backup Test Message" >/dev/null
echo -e "${GREEN}Test message sent (check Telegram)${RESET}"
}

# ---------------- Run Backup ----------------
run_backup() {

load_config || return

DATE=$(date +%F_%H-%M)
SQL_FILE="$BACKUP_DIR/db_$DATE.sql"
ZIP_FILE="$BACKUP_DIR/backup_$DATE.zip"

echo "[START] $DATE" >> "$LOG_FILE"

mysqldump -h "$DB_HOST" -P "$DB_PORT" -u"$DB_USER" -p"$DB_PASS" $DB_DISPLAY > "$SQL_FILE" 2>>"$LOG_FILE"

if [ ! -s "$SQL_FILE" ]; then
echo -e "${RED}Database dump failed!${RESET}"
return
fi

zip -r "$ZIP_FILE" "$SQL_FILE" $BACKUP_PATHS >> "$LOG_FILE" 2>&1

SIZE=$(stat -c%s "$ZIP_FILE")

send_file() {
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
-F chat_id="$CHAT_ID" \
-F document=@"$1" >/dev/null
}

if [ "$SIZE" -le "$MAX_SIZE" ]; then
send_file "$ZIP_FILE"
else
split -b $MAX_SIZE "$ZIP_FILE" "${ZIP_FILE}.part"
for part in ${ZIP_FILE}.part*; do
send_file "$part"
rm -f "$part"
done
fi

rm -f "$SQL_FILE" "$ZIP_FILE"
echo "[DONE] $DATE" >> "$LOG_FILE"
echo -e "${GREEN}Backup Completed Successfully ✅${RESET}"
}

# ---------------- Setup Cron ----------------
setup_cron() {
echo "0 3 * * * root bash $0 --auto" > "$CRON_FILE"
systemctl restart cron
echo -e "${GREEN}Daily backup scheduled at 03:00 AM ✅${RESET}"
}

# ---------------- Remove Backup Files ----------------
remove_files() {
rm -rf "$BACKUP_DIR"/*
echo -e "${GREEN}All backup files removed.${RESET}"
}

# ---------------- Uninstall ----------------
uninstall_all() {
echo -e "${RED}This will completely remove Backup System!${RESET}"
read -p "Type YES to confirm: " confirm
if [ "$confirm" == "YES" ]; then
rm -rf "$INSTALL_DIR"
rm -rf "$BACKUP_DIR"
rm -f "$LOG_FILE"
rm -f "$CRON_FILE"
echo -e "${GREEN}System Removed Completely ✅${RESET}"
exit 0
fi
}

# ---------------- Auto Mode ----------------
if [ "$1" == "--auto" ]; then
run_backup
exit 0
fi

# ---------------- Start ----------------
install_deps

# ---------------- Main Menu ----------------
while true; do
clear
echo -e "${MAGENTA}"
echo "================================================="
echo "          🔹 PASARGUARD BACKUP PANEL 🔹"
echo "================================================="
echo -e "${RESET}"
echo -e "${YELLOW}1)${RESET} Setup / Configure Backup"
echo -e "${YELLOW}2)${RESET} Test MySQL Connection"
echo -e "${YELLOW}3)${RESET} Test Telegram"
echo -e "${YELLOW}4)${RESET} Run Backup Now"
echo -e "${YELLOW}5)${RESET} Setup Daily Auto Backup (03:00 AM)"
echo -e "${YELLOW}6)${RESET} Show Log"
echo -e "${YELLOW}7)${RESET} Remove All Backup Files"
echo -e "${YELLOW}8)${RESET} Uninstall Backup System"
echo -e "${YELLOW}0)${RESET} Exit"
echo "-------------------------------------------------"
read -p "Select option: " opt

case $opt in
1) setup_config ;;
2) test_mysql ;;
3) test_telegram ;;
4) run_backup ;;
5) setup_cron ;;
6) less "$LOG_FILE" ;;
7) remove_files ;;
8) uninstall_all ;;
0) exit ;;
*) echo "Invalid option"; sleep 1 ;;
esac
done
