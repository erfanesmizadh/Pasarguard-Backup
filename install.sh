#!/bin/bash
# Pasarguard Backup Installer - Ultimate Interactive Setup
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
╚═╝     ╚═╝  ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝     
       🔹 Ultimate Backup Installer 🔹
       🔹 by @AVASH_NET 🔹
EOF
echo -e "${RESET}"
}

# ───────────── Functions ─────────────
validate_time() {
    [[ "$1" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]
}

select_folders() {
    local choices=("$@")
    local selected=()
    while true; do
        echo -e "${CYAN}Select folders to backup (type numbers separated by space, ENTER to confirm):${RESET}"
        for i in "${!choices[@]}"; do
            echo -e "[$i] ${choices[$i]}"
        done
        read -rp "Your choice: " input
        selected=()
        for index in $input; do
            if [[ $index =~ ^[0-9]+$ ]] && [ $index -ge 0 ] && [ $index -lt ${#choices[@]} ]; then
                selected+=("${choices[$index]}")
            fi
        done
        if [ ${#selected[@]} -gt 0 ]; then
            echo -e "${GREEN}Selected folders:${RESET} ${selected[*]}"
            read -rp "Is this correct? (y/n): " yn
            if [[ "$yn" =~ ^[Yy]$ ]]; then
                echo "${selected[@]}"
                return
            fi
        else
            echo -e "${RED}No valid selection made!${RESET}"
        fi
    done
}

# ───────────── Main Menu ─────────────
install_menu() {
banner
echo -e "${CYAN}Welcome to the Ultimate Pasarguard Backup Installer!${RESET}"

# 1. Database Display Name
read -rp "$(echo -e ${BLUE}1) Database display name for Telegram${RESET} [PasarguardDB]: )" DB_DISPLAY
DB_DISPLAY=${DB_DISPLAY:-PasarguardDB}

# 2. Telegram Bot Token
read -rp "$(echo -e ${BLUE}2) Telegram Bot Token${RESET} []: )" BOT_TOKEN
while [[ -z "$BOT_TOKEN" ]]; do
    echo -e "${RED}Bot Token cannot be empty!${RESET}"
    read -rp "Enter Telegram Bot Token: " BOT_TOKEN
done

# 3. Admin Telegram ID
read -rp "$(echo -e ${BLUE}3) Admin Telegram ID${RESET} []: )" CHAT_ID
while ! [[ "$CHAT_ID" =~ ^[0-9]+$ ]]; do
    echo -e "${RED}Invalid ID! Must be numeric.${RESET}"
    read -rp "Enter Admin Telegram ID: " CHAT_ID
done

# 4. DB Root User
read -rp "$(echo -e ${BLUE}4) Database Root User${RESET} [root]: )" DB_USER
DB_USER=${DB_USER:-root}

# 5. DB Root Password
read -srp "$(echo -e ${BLUE}5) Database Root Password${RESET} []: )" DB_PASS
echo
while [[ -z "$DB_PASS" ]]; do
    echo -e "${RED}Password cannot be empty!${RESET}"
    read -srp "Enter DB Root Password: " DB_PASS
    echo
done

# 6. Cron Time
while true; do
    read -rp "$(echo -e ${BLUE}6) Daily backup time (HH:MM 24h)${RESET} [02:00]: )" CRON_TIME
    CRON_TIME=${CRON_TIME:-02:00}
    if validate_time "$CRON_TIME"; then
        break
    else
        echo -e "${RED}Invalid time format! Use HH:MM (24h).${RESET}"
    fi
done

# 7. Folder Selection (checkbox-style)
DEFAULT_FOLDERS=(
"/var/lib/pasarguard/db-backup"
"/opt/pasarguard/certs"
"/opt/pasarguard/templates"
"/opt/pasarguard/docker-compose.yml"
"/opt/pasarguard/.env"
)
BACKUP_PATHS=$(select_folders "${DEFAULT_FOLDERS[@]}")

# ───────────── Summary ─────────────
echo
echo -e "${MAGENTA}Installation Summary:${RESET}"
echo -e "${GREEN}Database Display Name:${RESET} $DB_DISPLAY"
echo -e "${GREEN}Telegram Bot Token:${RESET} $BOT_TOKEN"
echo -e "${GREEN}Admin Telegram ID:${RESET} $CHAT_ID"
echo -e "${GREEN}DB Root User:${RESET} $DB_USER"
echo -e "${GREEN}Backup Time:${RESET} $CRON_TIME"
echo -e "${GREEN}Backup Folders:${RESET} $BACKUP_PATHS"
echo
read -rp "Proceed with installation? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Installation cancelled.${RESET}"
    exit 1
fi

# ───────────── Setup Backup Directory ─────────────
mkdir -p /var/lib/pasarguard/db-backup

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
BACKUP_DIR="/var/lib/pasarguard/db-backup"
BACKUP_PATHS="$BACKUP_PATHS"
EOF

echo -e "${GREEN}✅ Installation completed!${RESET}"
echo -e "${CYAN}Backup will run daily at $CRON_TIME.${RESET}"
echo -e "${YELLOW}Config saved to $CONFIG_FILE${RESET}"
echo -e "${MAGENTA}Edit /usr/local/bin/pasarguard-backup.sh to use these variables.${RESET}"
}

# ───────────── Run Installer ─────────────
install_menu
