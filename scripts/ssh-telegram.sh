#!/bin/bash

BOT_TOKEN=$TELEGRAM_TOKEN
CHAT_ID=$TELEGRAM_CHAT_ID

USER="$PAM_USER"
RHOST="$PAM_RHOST"
HOSTNAME="$(hostname)"
TIME="$(date)"

if [[ "$PAM_TYPE" == "open_session" ]]; then
    MESSAGE="🔐 SSH login
User: $USER
From: $RHOST
Host: $HOSTNAME
Time: $TIME"

elif [[ "$PAM_TYPE" == "close_session" ]]; then
    MESSAGE="🔓 SSH logout
User: $USER
From: $RHOST
Host: $HOSTNAME
Time: $TIME"

else
    exit 0
fi

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  --data-urlencode text="${MESSAGE}" \
  > /dev/null 2>&1
