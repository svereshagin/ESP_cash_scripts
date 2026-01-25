#!/bin/bash

# Функция для получения статуса конфига
get_gismt_config_status() {
    local server="$1"
    local user="$2"
    local password="$3"
    local kkt_id="$4"

    local status
    status=$(sshpass -p "$password" ssh -oHostKeyAlgorithms=+ssh-rsa "$user@$server" \
        "CONFIG=\"/etc/esp/esm/um/config_${kkt_id}.yml\"; \
         if [ -f \"\$CONFIG\" ]; then \
             if grep -A5 'gisMT:' \"\$CONFIG\" | grep 'url:' | grep -q 'https\?://'; then \
                 echo '20'; \
             else \
                 echo '10'; \
             fi; \
         else \
             echo '40'; \
         fi" 2>/dev/null)

    echo "$status"
}

# Использование функции
SERVER="10.9.130.187"
USER="tc"
PASSWORD="324012"
KKT_ID="0128245621"

# Получаем статус
CONFIG_STATUS=$(get_gismt_config_status "$SERVER" "$USER" "$PASSWORD" "$KKT_ID")

echo "Статус конфига: $CONFIG_STATUS"

# Обрабатываем
case $CONFIG_STATUS in
    20)
        echo "URL ГИС МТ настроен в конфиге"
        ;;
    10)
        echo "URL ГИС МТ не настроен или пустой"
        ;;
    40)
        echo "Файл конфигурации не найден"
        ;;
    *)
        echo "Не удалось получить статус"
        ;;
esac