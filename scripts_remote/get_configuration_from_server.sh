#!/bin/bash

# Конфигурация
SERVER="10.9.130.187"
USER="tc"
PASSWORD="324012"
REMOTE_DIR="/etc/esp/esm/um"


LOCAL_BASE_DIR="$HOME/Downloads/esm_logs"
LOCAL_DIR="${LOCAL_BASE_DIR}_$(date +%Y%m%d_%H%M%S)"


echo "Начинаю рекурсивное скачивание директории..."
echo "📁 Удаленная директория: $REMOTE_DIR"
echo "📁 Локальная директория: $LOCAL_DIR"
echo ""

mkdir -p "$LOCAL_DIR"

echo "Вариант 1: Использую scp -r..."
if sshpass -p "$PASSWORD" scp -r -O -oHostKeyAlgorithms=+ssh-rsa \
    "$USER@$SERVER:$REMOTE_DIR" "$LOCAL_DIR/" 2>&1 | grep -v "debug1:"; then
    echo "Директория успешно скачана через scp -r"
else
    echo "scp -r не сработал, пробую другие методы..."
fi



