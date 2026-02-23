#!/bin/bash
# =====================================================
# PASARGUARD ENTERPRISE BACKUP MANAGER
# Author: AVASH_NET
# Full Stable + Smart Menu Version
# =====================================================

INSTALL_DIR="/opt/pasarguard-backup"
BACKUP_SCRIPT="/usr/local/bin/pg-backup"
CONFIG_FILE="$INSTALL_DIR/config.env"
LOG_FILE="/var/log/pg-backup.log"
BACKUP_DIR="/var/lib/pasarguard/backup"

mkdir -p $INSTALL_DIR
mkdir -p $BACKUP_DIR
touch $LOG_FILE

install_dependencies() {
apt update -y
apt install -y whiptail curl zip docker.io mysql-client
}

save_config() {

DB_DISPLAY=$(whiptail --inputbox "Database name (empty = ALL)" 8 60 "pasarguard" --title "Database Name" 3>&1 1>&2 2>&3)
BOT_TOKEN=$(whiptail --inputbox "Telegram Bot Token" 8 60 --title "BOT TOKEN" 3>&1 1>&2 2>&3)
CHAT_ID=$(whiptail --inputbox "Telegram Chat ID" 8 60 --title "CHAT ID" 3>&1 1>&2 2>&3)
DB_USER=$(whiptail --inputbox "Database User" 8 60 "root" --title "DB USER" 3>&1 1>&2 2>&3)
DB_PASS=$(whiptail --passwordbox "Database Password" 8 60 --title "DB PASS" 3>&1 1>&2 2>&3)
INTERVAL=$(whiptail --inputbox "Backup Interval (Hours)" 8 60 "6" --title "Interval" 3>&1 1>&2 2>&3)

cat > $CONFIG_FILE <<EOF
DB_DISPLAY="$DB_DISPLAY"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_USER="$DB_USER"
DB_PASS="$DB_PASS"
INTERVAL="$INTERVAL"
BACKUP_PATHS="/opt/pasarguard /opt/pg-node /var/lib/pasarguard /var/lib/pg-node"
EOF

chmod 600 $CONFIG_FILE
}

create_backup_script() {

cat > $BACKUP_SCRIPT <<'EOF'
#!/bin/bash
CONFIG="/opt/pasarguard-backup/config.env"
LOG_FILE="/var/log/pg-backup.log"
BACKUP_DIR="/var/lib/pasarguard/backup"
MAX_SIZE=$((45*1024*1024))

source $CONFIG

DATE=$(date +%F_%H-%M)
SQL_FILE="$BACKUP_DIR/db_$DATE.sql"
ZIP_FILE="$BACKUP_DIR/backup_$DATE.zip"

echo "[$(date)] Backup Started" >> $LOG_FILE

MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -n1)

if [ -n "$MYSQL_CONTAINER" ]; then
docker exec $MYSQL_CONTAINER mysqldump --user="$DB_USER" --password="$DB_PASS" ${DB_DISPLAY:-"--all-databases"} > $SQL_FILE 2>>$LOG_FILE
else
mysqldump --user="$DB_USER" --password="$DB_PASS" ${DB_DISPLAY:-"--all-databases"} > $SQL_FILE 2>>$LOG_FILE
fi

if [ ! -s "$SQL_FILE" ]; then
echo "Dump Failed" >> $LOG_FILE
exit 1
fi

zip -r $ZIP_FILE $SQL_FILE $BACKUP_PATHS >>$LOG_FILE 2>&1

SIZE=$(stat -c%s "$ZIP_FILE")

send_file() {
curl -s -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
-F chat_id="$CHAT_ID" \
-F document=@"$1"
}

if [ "$SIZE" -le "$MAX_SIZE" ]; then
CODE=$(send_file $ZIP_FILE)
echo "Telegram Code: $CODE" >> $LOG_FILE
else
split -b $MAX_SIZE -d $ZIP_FILE ${ZIP_FILE}.part
for part in ${ZIP_FILE}.part*; do
CODE=$(send_file $part)
echo "Telegram Part Code: $CODE" >> $LOG_FILE
rm -f $part
done
fi

rm -f $SQL_FILE $ZIP_FILE
echo "[$(date)] Backup Done" >> $LOG_FILE
EOF

chmod +x $BACKUP_SCRIPT
}

setup_cron() {
(crontab -l 2>/dev/null | grep -v pg-backup; echo "0 */$INTERVAL * * * $BACKUP_SCRIPT") | crontab -
}

remove_cron() {
crontab -l | grep -v pg-backup | crontab -
}

main_menu() {

while true; do
CHOICE=$(whiptail --menu "Pasarguard Backup Manager" 20 60 10 \
"1" "Install / Update Backup System" \
"2" "Run Backup Now" \
"3" "View Last 30 Log Lines" \
"4" "Change Settings" \
"5" "Remove Cron Job" \
"6" "Exit" 3>&1 1>&2 2>&3)

case $CHOICE in
1)
install_dependencies
save_config
create_backup_script
source $CONFIG_FILE
setup_cron
whiptail --msgbox "Installed Successfully" 8 40
;;
2)
$BACKUP_SCRIPT
whiptail --msgbox "Backup Executed" 8 40
;;
3)
tail -30 $LOG_FILE | whiptail --textbox - 20 70
;;
4)
save_config
whiptail --msgbox "Settings Updated" 8 40
;;
5)
remove_cron
whiptail --msgbox "Cron Removed" 8 40
;;
6)
exit
;;
esac
done
}

main_menu
