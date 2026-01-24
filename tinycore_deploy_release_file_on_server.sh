#!/bin/bash

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

debug_log() {
    if [ -n "$DEBUG" ]; then
        echo -e "[DEBUG] $1" >&2
    fi
}

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
  log_info "Подключение к серверу $TINYCORE_SERVER_IP..."
  sshpass -p "$PASSWORD" ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP"
}


deploy_executable_file_on_server() {
    local tinycore_home_dir='/home/tc/'

    # 1. Поиск файла
    log_info "Поиск файла установки..."
    shopt -s nullglob
    local files=( esm_*_tinycore8.run )
    shopt -u nullglob

    if [ ${#files[@]} -eq 0 ]; then
        log_error "Файл установки не найден"
        log_info "Текущая папка: $(pwd)"
        ls -la
        return 1
    fi

    local tinycore_file_name="${files[0]}"
    log_success "Найден файл установки: $tinycore_file_name"

    # 2. Проверка файла
    if [ ! -f "$tinycore_file_name" ]; then
        log_error "Файл '$tinycore_file_name' не существует"
        return 1
    fi

    # Создаем временный файл для логов
    local temp_log=$(mktemp)

    # Выполняем scp с подробным выводом
    log_info "Копирование файла на сервер..."
    if sshpass -p "$PASSWORD" scp -q -O $SSH_OPTIONS "$tinycore_file_name" \
        "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP:$tinycore_home_dir" 2>/dev/null; then
        log_success "Файл успешно скопирован на сервер"
        return 0
    else
        log_error "Ошибка при копировании файла на сервер"
        # Получим детальную ошибку без verbose вывода
        if ! sshpass -p "$PASSWORD" scp -O $SSH_OPTIONS "$tinycore_file_name" \
            "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP:$tinycore_home_dir" 2>&1 | tail -20; then
            log_warning "Не удалось получить детали ошибки"
        fi
        return 1
    fi
}

add_to_onboot_lst() {
    local path="/etc/sysconfig/tcedir/onboot.lst"
    local modules=("esm-csi-dkkt.tcs" "esm.tcs")

    log_info "Настройка автозагрузки модулей..."

    if [ ! -f "$path" ]; then # Создаем файл если не существует
        log_info "Создаю файл $path"
        touch "$path" || {
            log_error "Не удалось создать файл $path"
            return 1
        }
    fi

    for module in "${modules[@]}"; do  # Добавляем модули
        if ! grep -q "^${module}$" "$path" 2>/dev/null; then
            log_info "Добавляю модуль в автозагрузку: $module"
            echo "$module" >> "$path"
        else
            log_info "Модуль уже есть в автозагрузке: $module"
        fi
    done

    log_success "Настройка автозагрузки завершена!"
    return 0
}

execute_script() {
    local remote_cmd="
        set -e  # Прерывать выполнение при любой ошибке

        echo '[INFO] Текущая директория: \$(pwd)'
        echo '[INFO] Файлы в директории:'
        ls -la
        echo ''

        echo '[INFO] Ищу файл установки...'
        INSTALL_FILE=\$(ls esm_*_tinycore8.run 2>/dev/null | head -1)
        if [ -z \"\$INSTALL_FILE\" ]; then
            echo '[ERROR] Файл установки esm_*_tinycore8.run не найден на сервере'
            exit 1
        fi

        echo '[SUCCESS] Найден файл: \$INSTALL_FILE'
        sudo chmod +x \"\$INSTALL_FILE\"
        echo '[INFO] Запуск установщика...'
        sudo ./\"\$INSTALL_FILE\"
        echo '[SUCCESS] Установка завершена'

        # Настройка автозагрузки
        ONBOOT_FILE='/etc/sysconfig/tcedir/onboot.lst'
        echo '[INFO] Проверка файла автозагрузки: \$ONBOOT_FILE'
        if [ ! -f \"\$ONBOOT_FILE\" ]; then
            sudo touch \"\$ONBOOT_FILE\"
            sudo chmod 644 \"\$ONBOOT_FILE\"
            echo '[INFO] Создан файл автозагрузки'
        fi

        for m in esm-csi-dkkt.tcz esm.tcz; do
            if ! grep -q \"^\$m\$\" \"\$ONBOOT_FILE\" 2>/dev/null; then
                echo \"\$m\" | sudo tee -a \"\$ONBOOT_FILE\" > /dev/null
                echo '[INFO] Добавлен модуль в автозагрузку: \$m'
            else
                echo '[INFO] Модуль уже есть в автозагрузке: \$m'
            fi
        done

        echo '[INFO] Содержимое onboot.lst после изменений:'
        cat \"\$ONBOOT_FILE\"

        echo '[INFO] Инициирую перезагрузку сервера...'
        cash reboot > /dev/null 2>&1 &
        exit 0
        "

    log_info "Подключаюсь к серверу и выполняю установку..."
    sshpass -p "$PASSWORD" ssh $SSH_OPTIONS "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP" "$remote_cmd"
}

wait_for_server_to_reboot() {
    local max_attempts=30
    local current_attempt=1
    local base_wait_time=120  # 2 минуты
    local seconds_to_wait=10

    log_info "Ожидание перезагрузки сервера (начальное ожидание $base_wait_time сек)..."
    sleep $base_wait_time

    while [ $current_attempt -le $max_attempts ]; do
        log_info "Попытка подключения $current_attempt/$max_attempts - ожидание ${seconds_to_wait}сек..."

        # Проверяем ping
        if ping -c 1 -W 2 "$TINYCORE_SERVER_IP" > /dev/null 2>&1; then
            log_success "Сервер отвечает на ping"

            # Дополнительно проверяем SSH
            if sshpass -p "$PASSWORD" ssh $SSH_OPTIONS -o ConnectTimeout=5 \
               "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP" "exit" > /dev/null 2>&1; then
                log_success "SSH подключение восстановлено"
                log_success "Сервер успешно перезагрузился"
                return 0
            else
                log_warning "SSH подключение еще не готово..."
            fi
        else
            log_warning "Сервер еще не доступен (ping не отвечает)..."
        fi

        current_attempt=$((current_attempt + 1))
        sleep $seconds_to_wait
    done

    log_error "Сервер не ответил после $max_attempts попыток ожидания"
    return 1
}

main() {
    log_success "=== Развертывание ESM на TinyCore Linux ==="
    log_info "Сервер: $TINYCORE_USERNAME@$TINYCORE_SERVER_IP"
    log_info "==========================================="

    # Проверка подключения к серверу
    if sshpass -p "$PASSWORD" ssh $SSH_OPTIONS -o ConnectTimeout=5 \
               "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP" "exit"; then
        log_success "Подключение успешно установлено, сервер доступен"
    else
        log_error "Не удалось подключиться к серверу"
        exit 1
    fi

    if ! deploy_executable_file_on_server; then
        log_error "Ошибка при развертывании файла на сервере"
        exit 1
    fi

    if ! execute_script; then
        log_error "Ошибка при выполнении скрипта на сервере"
        exit 1
    fi

    if wait_for_server_to_reboot; then
        log_success "Сервер успешно перезагружен, начинаю подключение..."
        connect_to_server
    else
        log_error "Не удалось дождаться перезагрузки сервера"
        exit 1
    fi

}

main