#!/bin/bash
REPO="/mnt/hdd/immich-backup"
SOURCE="/mnt/immich"
LOG="/var/log/borg-immich.log"
DATE=$(date +%Y-%m-%d)

#Set these values before running or source your .env file
export BORG_PASSPHRASE=$BORG_PASSPHRASE
TELEGRAM_TOKEN=$TELEGRAM_TOKEN
TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID

echo "=== Borg backup started: $(date) ===" >> "$LOG"

# Check source is mounted
if ! mountpoint -q "$SOURCE"; then
    echo "ERROR: $SOURCE is not mounted. Borg backup aborted." >> "$LOG"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="❌ Borg backup FAILED on homelab — /mnt/immich is not mounted." > /dev/null
    exit 1
fi

# Check destination is mounted
if ! mountpoint -q /mnt/hdd; then
    echo "ERROR: /mnt/hdd is not mounted. Borg backup aborted." >> "$LOG"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="❌ Borg backup FAILED on homelab — /mnt/hdd is not mounted." > /dev/null
    exit 1
fi

# Create archive
borg create \
    --compression lz4 \
    --stats \
    "$REPO::$DATE" \
    "$SOURCE" \
    >> "$LOG" 2>&1

BACKUP_EXIT=$?

# Prune old archives
borg prune \
    --keep-daily=7 \
    --keep-weekly=4 \
    --keep-monthly=6 \
    "$REPO" \
    >> "$LOG" 2>&1

# Compact repo to free space from pruned archives
borg compact "$REPO" >> "$LOG" 2>&1

PRUNE_EXIT=$?

if [ $BACKUP_EXIT -ne 0 ] || [ $PRUNE_EXIT -ne 0 ]; then
    echo "ERROR: Borg backup failed on $DATE" >> "$LOG"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="❌ Borg backup FAILED on homelab on ${DATE} — check $LOG" > /dev/null
else
    echo "SUCCESS: Borg backup completed on $DATE" >> "$LOG"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="✅ Borg backup completed successfully on homelab — ${DATE}" > /dev/null
fi

echo "=== Borg backup ended: $(date) ===" >> "$LOG"
