#!/bin/bash
# Pasarguard Backup Installer - Interactive Setup
# by @AVASH_NET

# ───────────── Colors ─────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
RESET='\033[0m'

# ───────────── Banner ─────────────
banner() {
clear
echo -e "${MAGENTA}"
cat << "EOF"
██████╗  █████╗ ███████╗██████╗  █████╗ ██████╗ 
██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝███████║███████╗██████╔╝███████║██████╔╝
██╔═══╝ ██╔══██║╚════██║██╔═══╝ ██╔══██║██╔═══╝ 
██║     ██║  ██║███████║██║     ██║  ██║██║     
╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝     
       🔹 Backup Installer 🔹
       🔹 by @AVASH_NET 🔹
EOF
echo -e "${RESET}"
}

# ───────────── Main Menu ─────────────
install_menu() {
banner
echo -e "${CYAN}Welcome to Pasarguard Backup Installer!${RESET}"
echo
echo -e "${YELLOW}Please enter the following details:${RESET}"

# 1. Database Display Name
read -rp "1) Enter database display name (for Telegram): " DB_DISPLAY

# 2. Telegram Bot Token
read -rp "2) Enter Telegram Bot Token: " BOT_TOKEN

# 3. Admin Telegram ID
read -rp "3) Enter Admin Telegram ID: " CHAT_ID

# 4. Database Root User
read -rp "4) Enter DB Root User: " DB_USER

# 5. Database Root Password
read -srp "5) Enter DB Root Password: " DB_PASS
echo

# 6. Cron Time (e.g., 02:00)
read -rp "6) Enter daily backup time (HH:MM, 24h format): " CRON_TIME

# 7. Backup Paths (space separated)
echo -e "${GREEN}7) Enter folders to backup (space separated, full path):${RESET}"
echo -e "${CYAN}Include any custom folders and default ones you want.${RESET}"
read -rp "Paths: " BACKUP_PATHS

# Confirm
echo
echo -e "${MAGENTA}Summary:${RESET}"
echo -e "Database Display Name: ${GREEN}$DB_DISPLAY${RESET}"
echo -e "Telegram Bot Token: ${GREEN}$BOT_TOKEN${RESET}"
echo -e "Admin Telegram ID: ${GREEN}$CHAT_ID${RESET}"
echo -e "DB Root User: ${GREEN}$DB_USER${RESET}"
echo -e "Backup Time: ${GREEN}$CRON_TIME${RESET}"
echo -e "Backup Paths: ${GREEN}$BACKUP_PATHS${RESET}"
echo
read -rp "Is this information correct? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${RED}Installation cancelled.${RESET}"
    exit 1
fi

# ───────────── Create Backup Directory ─────────────
BACKUP_DIR="/var/lib/pasarguard/db-backup"
mkdir -p "$BACKUP_DIR"

# ───────────── Setup Cron ─────────────
CRON_HOUR=$(echo "$CRON_TIME" | cut -d: -f1)
CRON_MIN=$(echo "$CRON_TIME" | cut -d: -f2)
(crontab -l 2>/dev/null; echo "$CRON_MIN $CRON_HOUR * * * /usr/local/bin/pasarguard-backup.sh") | crontab -

# ───────────── Save Config ─────────────
CONFIG_FILE="/opt/pasarguard/backup-config.env"
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" <<EOF
DB_DISPLAY="$DB_DISPLAY"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_USER="$DB_USER"
DB_PASS="$DB_PASS"
BACKUP_DIR="$BACKUP_DIR"
BACKUP_PATHS="$BACKUP_PATHS"
EOF

echo -e "${GREEN}✅ Installation completed! Backup script is ready.${RESET}"
echo -e "${CYAN}Backup will run daily at $CRON_TIME.${RESET}"
echo -e "${YELLOW}Config saved to: $CONFIG_FILE${RESET}"
echo -e "${MAGENTA}You can now edit /usr/local/bin/pasarguard-backup.sh to use these variables.${RESET}"
}

# ───────────── Run Installer ─────────────
install_menu
