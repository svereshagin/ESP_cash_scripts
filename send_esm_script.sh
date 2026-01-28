#!/bin/bash

SERVER="10.9.130.187"
USER="tc"
PASSWORD="324012"
FILE="setup.sh"
REMOTE_PATH="/home/tc/"

# Опции SSH для старых серверов
SSH_OPTIONS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"


if sshpass -p "$PASSWORD" scp -O $SSH_OPTIONS "$FILE" "$USER@$SERVER:$REMOTE_PATH" 2>&1; then
    echo "Скрипт успешно скопирован на сервер"
else
    echo "Ошибка при копировании скрипта"
    exit 1
fi

