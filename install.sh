#!/bin/bash
# =====================================================
# PASARGUARD BACKUP & MANAGEMENT - PROFESSIONAL BASH
# Author: AVASH_NET
# TCP MySQL, Telegram, Large Files Safe, Full Menu
# =====================================================

# ---------------- Colors ----------------
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; MAGENTA="\e[35m"; CYAN="\e[36m"; RESET="\e[0m"

# ---------------- Directories & Files ----------------
INSTALL_DIR="/opt/pasarguard-backup"
BACKUP_DIR="/var/lib/pasarguard/backup"
CONFIG_FILE="$INSTALL_DIR/config.env"
LOG_FILE="/var/log/pg-backup.log"
MAX_SIZE=$((45*1024*1024))  # 45MB

mkdir -p "$INSTALL_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# ---------------- Banner ----------------
echo -e "${CYAN}==============================================="
echo "      🔹 PASARGUARD BACKUP SYSTEM 🔹"
echo -e "===============================================${RESET}"
echo -e "${YELLOW}Backup Directory:${RESET} $BACKUP_DIR"
echo -e "${YELLOW}Log File:${RESET} $LOG_FILE"
echo -e "-----------------------------------------------"

# ---------------- Pre-install Checks ----------------
echo -e "${BLUE}[INFO] Checking required commands...${RESET}"
for cmd in mysql mysqldump zip curl; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}[ERROR] $cmd is not installed. Installing...${RESET}"
        apt update -y
        if [ "$cmd" = "mysqldump" ] || [ "$cmd" = "mysql" ]; then
            apt install -y mariadb-client
        else
            apt install -y $cmd
        fi
    fi
done

# ---------------- Config Setup ----------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}[INFO] Creating config.env...${RESET}"
    cat > "$CONFIG_FILE" <<EOL
# Pasarguard Backup Configuration
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_USER="root"
DB_PASS="your_mysql_password"
DB_DISPLAY="pasarguard"
BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
BACKUP_PATHS=(
"/opt/pasarguard"
"/opt/pg-node"
"/var/lib/pasarguard"
"/var/www/html/telegram-bot"
)
EOL
    chmod 600 "$CONFIG_FILE"
    echo -e "${GREEN}[INFO] Config file created at $CONFIG_FILE${RESET}"
fi

# ---------------- Load Config ----------------
source "$CONFIG_FILE"

# ---------------- Validate Config ----------------
: "${DB_USER:?DB_USER not set in config.env}"
: "${DB_PASS:?DB_PASS not set in config.env}"
: "${DB_HOST:?DB_HOST not set in config.env}"
: "${DB_PORT:?DB_PORT not set in config.env}"
: "${BOT_TOKEN:?BOT_TOKEN not set in config.env}"
: "${CHAT_ID:?CHAT_ID not set in config.env}"
: "${BACKUP_PATHS[@]:?BACKUP_PATHS not set in config.env}"

# ---------------- Backup Function ----------------
backup_run() {
    DATE=$(date +%F_%H-%M)
    SQL_FILE="$BACKUP_DIR/db_$DATE.sql"
    ZIP_FILE="$BACKUP_DIR/backup_$DATE.zip"

    echo -e "${CYAN}[INFO] Starting Backup - $DATE${RESET}" | tee -a "$LOG_FILE"

    mysqldump -h "$DB_HOST" -P "$DB_PORT" --user="$DB_USER" --password="$DB_PASS" ${DB_DISPLAY:-"--all-databases"} > "$SQL_FILE" 2>>"$LOG_FILE"
    if [ ! -s "$SQL_FILE" ]; then
        echo -e "${RED}[ERROR] MySQL dump failed!${RESET}" | tee -a "$LOG_FILE"
        return 1
    fi

    # Cleanup old backups (>7 days)
    find "$BACKUP_DIR" -type f -name "backup_*.zip" -mtime +7 -delete

    # Zip Backup
    FILES_TO_ZIP=("$SQL_FILE")
    for path in "${BACKUP_PATHS[@]}"; do
        if [ -e "$path" ]; then
            FILES_TO_ZIP+=("$path")
            echo "[$(date)] Adding $path to ZIP" >> "$LOG_FILE"
        fi
    done
    zip -r "$ZIP_FILE" "${FILES_TO_ZIP[@]}" >> "$LOG_FILE" 2>&1

    # Send to Telegram
    SIZE=$(stat -c%s "$ZIP_FILE")
    send_file() {
        curl -s --max-time 600 --retry 3 -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        -F chat_id="$CHAT_ID" \
        -F caption="$1\n\n💠 Backup by @AVASH_NET" \
        -F document=@"$2"
    }

    if [ "$SIZE" -le "$MAX_SIZE" ]; then
        RESPONSE=$(send_file "📦 Pasarguard Backup - $DATE" "$ZIP_FILE")
        echo "[$(date)] Telegram Response: $RESPONSE" >> "$LOG_FILE"
    else
        split -b $MAX_SIZE -d "$ZIP_FILE" "${ZIP_FILE}.part"
        for part in ${ZIP_FILE}.part*; do
            RESPONSE=$(send_file "📦 Pasarguard Backup Part: $(basename $part)" "$part")
            echo "[$(date)] Telegram Response Part: $RESPONSE" >> "$LOG_FILE"
            rm -f "$part"
        done
    fi

    rm -f "$SQL_FILE" "$ZIP_FILE"
    echo -e "${GREEN}[INFO] Backup Completed ✅${RESET}" | tee -a "$LOG_FILE"
}

# ---------------- Remove All Backups ----------------
remove_backups() {
    echo -e "${RED}[WARNING] This will delete ALL backups in $BACKUP_DIR!${RESET}"
    read -p "Are you sure? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        rm -rf "$BACKUP_DIR"/*
        echo -e "${GREEN}[INFO] All backups removed.${RESET}"
    else
        echo -e "${YELLOW}[INFO] Operation cancelled.${RESET}"
    fi
}

# ---------------- Menu ----------------
while true; do
    echo -e "${MAGENTA}"
    echo "==============================================="
    echo "      🔹 PASARGUARD BACKUP MENU 🔹"
    echo "==============================================="
    echo -e "${YELLOW}1.${RESET} Run Backup Now"
    echo -e "${YELLOW}2.${RESET} Show Backup Log"
    echo -e "${YELLOW}3.${RESET} Edit Config"
    echo -e "${YELLOW}4.${RESET} Remove All Backups"
    echo -e "${YELLOW}5.${RESET} Exit"
    echo "-----------------------------------------------"
    read -p "Select option [1-5]: " choice
    case $choice in
        1) backup_run ;;
        2) less "$LOG_FILE" ;;
        3) nano "$CONFIG_FILE" ;;
        4) remove_backups ;;
        5) exit 0 ;;
        *) echo -e "${RED}Invalid option!${RESET}" ;;
    esac
done
