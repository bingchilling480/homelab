#!/bin/bash

BOT_TOKEN=$TELEGRAM_TOKEN
CHAT_ID=$TELEGRAM_CHAT_ID

MESSAGE="🚨 SMART ALERT on $(hostname)

Disk: $SMARTD_DEVICE
Problem: $SMARTD_MESSAGE
Time: $(date)"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="${MESSAGE}"
