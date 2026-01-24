#!/bin/bash
#Configuration
#need to have ssh-pass to connect to the server
#brew install hudochenkov/sshpass/sshpass for macos
TINYCORE_SERVER_IP="10.9.130.187"
TINYCORE_USERNAME="tc"
PASSWORD="324012"
pattern="tinycore8.run"

SSH_OPTIONS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"

tinycore_file_name=""

connect_to_server() {
  sshpass -p "$PASSWORD" ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP"
}


deploy_executable_file_on_server() {
    local tinycore_home_dir='/home/tc/'

    # 1. Поиск файла
    echo "Поиск файла установки..."
    shopt -s nullglob
    local files=( esm_*_tinycore8.run )
    shopt -u nullglob

    if [ ${#files[@]} -eq 0 ]; then
        echo "Файл не найден"
        echo "Текущая папка: $(pwd)"
        ls -la
        return 1
    fi

    local tinycore_file_name="${files[0]}"
    echo "Найден: $tinycore_file_name"

    # 2. Проверка файла
    if [ ! -f "$tinycore_file_name" ]; then
        echo "Файл '$tinycore_file_name' не существует"
        return 1
    fi

    echo "✓ Размер: $(stat -f%z "$tinycore_file_name" 2>/dev/null || stat -c%s "$tinycore_file_name") байт"

    # 3. Копирование
    echo "Копирование на сервер..."

    # Создаем временный файл для логов
    local temp_log=$(mktemp)

    # Выполняем scp с подробным выводом
    if sshpass -p "$PASSWORD" scp -v -O $SSH_OPTIONS "$tinycore_file_name" \
        "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP:$tinycore_home_dir" 2>&1 | tee "$temp_log"; then
        echo "Успешно"
        rm -f "$temp_log"
        return 0
    else
        echo "Ошибка"
        echo "Детали ошибки:"
        grep -E "(error|Error|ERROR|fail|Fail|FAIL|denied|refused|unreachable)" "$temp_log" || cat "$temp_log"
        rm -f "$temp_log"
        return 1
    fi
}

add_to_onboot_lst() {
    local path="/etc/sysconfig/tcedir/onboot.lst"
    local modules=("esm-csi-dkkt.tcs" "esm.tcs")

    echo "Настройка автозагрузки модулей..."


    if [ ! -f "$path" ]; then # Создаем файл если не существует
        echo "Создаю файл $path"
        touch "$path" || {
            echo "Ошибка: не удалось создать файл" >&2
            return 1
        }
    fi

    for module in "${modules[@]}"; do  # Добавляем модули
        if ! grep -q "^${module}$" "$path" 2>/dev/null; then
            echo "Добавляю: $module"
            echo "$module" >> "$path"
        else
            echo "Уже есть: $module"
        fi
    done

    echo "Готово!"
    return 0
}

execute_script() {
    local remote_cmd="
        set -e  # Прерывать выполнение при любой ошибке

        echo 'Текущая директория: \$(pwd)'
        echo 'Файлы в директории:'
        ls -la
        echo ''

        echo 'Ищу файл установки...'
        INSTALL_FILE=\$(ls esm_*_tinycore8.run 2>/dev/null | head -1)
        if [ -z \"\$INSTALL_FILE\" ]; then
            echo 'ОШИБКА: Файл установки esm_*_tinycore8.run не найден на сервере'
            exit 1
        fi

        echo 'Найден файл: \$INSTALL_FILE'
        sudo chmod +x \"\$INSTALL_FILE\"
        echo 'Запуск установщика...'
        sudo ./\"\$INSTALL_FILE\"
        echo 'Установка завершена'

        # Настройка автозагрузки
        ONBOOT_FILE='/etc/sysconfig/tcedir/onboot.lst'
        echo 'Проверка файла автозагрузки: \$ONBOOT_FILE'
        if [ ! -f \"\$ONBOOT_FILE\" ]; then
            sudo touch \"\$ONBOOT_FILE\"
            sudo chmod 644 \"\$ONBOOT_FILE\"
            echo 'Создан файл автозагрузки'
        fi

        for m in esm-csi-dkkt.tcz esm.tcz; do
            if ! grep -q \"^\$m\$\" \"\$ONBOOT_FILE\" 2>/dev/null; then
                echo \"\$m\" | sudo tee -a \"\$ONBOOT_FILE\" > /dev/null
                echo 'Добавлен модуль в автозагрузку: \$m'
            else
                echo 'Модуль уже есть в автозагрузке: \$m'
            fi
        done

        echo 'Содержимое onboot.lst после изменений:'
        cat \"\$ONBOOT_FILE\"

        echo 'Инициирую перезагрузку сервера...'
        cash reboot > /dev/null 2>&1 &
        exit 0
        "

    echo 'Подключаюсь к серверу и выполняю установку...'
    sshpass -p "$PASSWORD" ssh $SSH_OPTIONS "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP" "$remote_cmd"
}

wait_for_server_to_reboot() {
    local max_attempts=30
    local current_attempt=1
    local base_wait_time=120  # 2 минуты
    local seconds_to_wait=10

    echo "Ждем перезагрузку сервера ($base_wait_time сек начальное ожидание)..."
    sleep $base_wait_time

    while [ $current_attempt -le $max_attempts ]; do
        echo "Попытка $current_attempt/$max_attempts - жду ${seconds_to_wait}сек..."

        # Проверяем ping
        if ping -c 1 -W 2 "$TINYCORE_SERVER_IP" > /dev/null 2>&1; then
            echo "Сервер отвечает на ping"

            # Дополнительно проверяем SSH
            if sshpass -p "$PASSWORD" ssh $SSH_OPTIONS -o ConnectTimeout=5 \
               "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP" "exit" > /dev/null 2>&1; then
                echo "SSH подключение восстановлено"
                echo "Сервер успешно перезагрузился"
                return 0
            else
                echo "SSH еще не готов..."
            fi
        else
            echo "Сервер еще не доступен..."
        fi

        current_attempt=$((current_attempt + 1))
        sleep $seconds_to_wait
    done

    echo "Сервер не ответил после $max_attempts попыток"
    return 1
}


main() {

    if sshpass -p "$PASSWORD" ssh $SSH_OPTIONS -o ConnectTimeout=5 \
                   "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP" "exit";
    then
      echo "Подключение успешно установлено, сервер доступен"
    fi

    echo "=== Развертывание ESM на TinyCore Linux ==="
    echo "Сервер: $TINYCORE_USERNAME@$TINYCORE_SERVER_IP"
    echo "==========================================="
    if ! deploy_executable_file_on_server; then
      exit 1
    fi

    if ! execute_script; then
      exit 1
    fi

    wait_for_server_to_reboot
    connect_to_server
}

main

