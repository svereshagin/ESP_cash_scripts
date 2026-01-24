#!/bin/sh

#Конфигурация ЛМ ЧЗ
LM_CZ_ADDRESS=""
LM_CZ_PORT=""
LM_CZ_LOGIN=""
LM_CZ_PASSWORD=""

GISMT_ADDRESS=""
COMPATIBILITY_MODE=""
ALLOW_REMOTE_CONNECTION=""


# Конфигурация API
API_BASE='http://127.0.0.1:51077'
API_VERSION='api/v1'

# Переменные для данных ККТ
KKT_ID=""
KKT_SERIAL=""
FN_SERIAL=""
KKT_INN=""
KKT_RNM=""
MODEL_NAME=""
DKKT_VERSION=""
DEVELOPER=""
MANUFACTURER=""
SHIFT_STATE=""

# Цвета для вывода (опционально)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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





# Функция для вызова API
call_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local url="$API_BASE/$API_VERSION/$endpoint"
    local response
    local curl_exit_code

    if [ -z "$data" ]; then
        response=$(curl -sS -X "$method" "$url" -w "\n%{http_code}")
        curl_exit_code=$?
    else
        response=$(curl -sS -X "$method" "$url" \
            -H "Content-Type: application/json" \
            -d "$data" -w "\n%{http_code}")
        curl_exit_code=$?
    fi

    # Разделяем ответ и HTTP код
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    debug_log "Код ответа curl: $curl_exit_code"
    debug_log "HTTP код: $http_code"
    debug_log "Тело ответа: $body"

    # Возвращаем тело ответа
    echo "$body"

    # Если curl завершился с ошибкой или HTTP код не 2xx
    if [ $curl_exit_code -ne 0 ] || [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
        return 1
    fi
    return 0
}

# Парсинг JSON ответа с использованием jq (если доступен)
parse_kkt_response() {
    local response="$1"

    # Проверяем наличие jq
    if command -v jq >/dev/null 2>&1; then
        debug_log "Используем jq для парсинга JSON"
        KKT_SERIAL=$(echo "$response" | jq -r '.kktSerial // empty')
        FN_SERIAL=$(echo "$response" | jq -r '.fnSerial // empty')
        KKT_INN=$(echo "$response" | jq -r '.kktInn // empty')
        KKT_RNM=$(echo "$response" | jq -r '.kktRnm // empty')
        MODEL_NAME=$(echo "$response" | jq -r '.modelName // empty')
        DKKT_VERSION=$(echo "$response" | jq -r '.dkktVersion // empty')
        DEVELOPER=$(echo "$response" | jq -r '.developer // empty')
        MANUFACTURER=$(echo "$response" | jq -r '.manufacturer // empty')
        SHIFT_STATE=$(echo "$response" | jq -r '.shiftState // empty')
    else
        debug_log "Используем sed для парсинга JSON"
        # Fallback на sed если jq не установлен
        KKT_SERIAL=$(echo "$response" | sed -n 's/.*"kktSerial":"\([^"]*\)".*/\1/p')
        FN_SERIAL=$(echo "$response" | sed -n 's/.*"fnSerial":"\([^"]*\)".*/\1/p')
        KKT_INN=$(echo "$response" | sed -n 's/.*"kktInn":"\([^"]*\)".*/\1/p')
        KKT_RNM=$(echo "$response" | sed -n 's/.*"kktRnm":"\([^"]*\)".*/\1/p')
        MODEL_NAME=$(echo "$response" | sed -n 's/.*"modelName":"\([^"]*\)".*/\1/p')
        DKKT_VERSION=$(echo "$response" | sed -n 's/.*"dkktVersion":"\([^"]*\)".*/\1/p')
        DEVELOPER=$(echo "$response" | sed -n 's/.*"developer":"\([^"]*\)".*/\1/p')
        MANUFACTURER=$(echo "$response" | sed -n 's/.*"manufacturer":"\([^"]*\)".*/\1/p')
        SHIFT_STATE=$(echo "$response" | sed -n 's/.*"shiftState":"\([^"]*\)".*/\1/p')
    fi

    # ID = серийный номер ККТ
    KKT_ID="${KKT_SERIAL}"

    # Проверяем, что получили данные
    if [ -z "$KKT_SERIAL" ]; then
        log_warning "Не удалось извлечь данные ККТ из ответа"
        return 1
    fi

    # Вывод извлеченных данных
    log_info "=== Извлеченные данные ККТ ==="
    echo "ID: $KKT_ID"
    echo "Серийный номер ККТ: $KKT_SERIAL"
    echo "Серийный номер ФН: $FN_SERIAL"
    echo "ИНН ККТ: $KKT_INN"
    echo "РНМ: $KKT_RNM"
    echo "Модель: $MODEL_NAME"
    echo "Версия ДККТ: $DKKT_VERSION"
    echo "Разработчик: $DEVELOPER"
    echo "Производитель: $MANUFACTURER"
    echo "Статус смены: $SHIFT_STATE"
    echo "=============================="

    return 0
}


check_service_state() {
    log_info "Проверка состояния сервиса ЕСМ..."

    local endpoint="service/state/$KKT_ID"
    local response

    if ! response=$(call_api "GET" "$endpoint"); then
        log_warning "Не удалось проверить состояние сервиса"
        return 2
    fi

    local service_state
    if command -v jq >/dev/null 2>&1; then
        service_state=$(echo "$response" | jq -r '.serviceState // empty')
    else
        service_state=$(echo "$response" | sed -n 's/.*"serviceState":"\([^"]*\)".*/\1/p')
    fi

    if [ -z "$service_state" ]; then
        log_warning "Не удалось определить состояние сервиса из ответа"
        return 2
    fi

    log_info "Состояние сервиса ЕСМ: $service_state"

    case "$service_state" in
        "Работает"|"Работает нормально"|"Active"|"Running")
            log_success "Сервис ЕСМ уже запущен"
            return 0
            ;;
        "Остановлен"|"Не работает"|"Stopped"|"Inactive")
            log_warning "Сервис ЕСМ остановлен"
            return 1
            ;;
        *)
            log_warning "Неизвестное состояние сервиса: $service_state"
            return 2
            ;;
    esac
}




# Получение списка ККТ
get_dkkt_list() {

    local response
    if ! response=$(call_api "GET" "dkktList"); then
        log_error "Ошибка при получении списка ККТ"
        return 1
    fi

    if [ -z "$response" ]; then
        log_error "Получен пустой ответ от API"
        return 1
    fi

    log_success "Список ККТ получен"
    debug_log "Сырой ответ: $response"

    # Парсим поля
    parse_kkt_response "$response"
    return $?
}





# Создание экземпляра ТСП ИОТ
create_tspiot_instance() {


    log_info "Создание экземпляра ТСП ИОТ..."
    local url="$API_BASE/$API_VERSION/tspiot"
    local data="{\"id\": \"$KKT_ID\"}"

    log_info "curl -X POST '$url' -H 'Content-Type: application/json' -d '$data'"

    response=$(curl -sS -w "\n%{http_code}" \
        -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$data")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    log_info "HTTP код: $http_code"
    log_info "Ответ: $body"

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        return 0
    elif [ "$http_code" -eq 400 ]; then
        return 2  # Возвращаем код 1010
    fi
}


# Настройка GISMT
configure_gismt() {
    log_info "Настройка GISMT..."

    local data='{
        "compatibilityMode": false,
        "allowRemoteConnection": true,
        "gismtAddress": "https://194.0.209.194:19101"
    }'
    local response

    if ! response=$(call_api "PUT" "settings/$KKT_ID" "$data"); then
        log_error "Ошибка при настройке GISMT"
        return 1
    fi

    log_success "GISMT настроен"
    return 0
}

# Проверка статуса смены
check_shift_state() {
    case "$SHIFT_STATE" in
        "Работает"|"Открыта")
            log_success "Смена активна. Можно продолжать работу"
            return 0
            ;;
        "Истекла"|"Закрыта")
            log_error "Смена закрыта. Откройте смену на кассе"
            return 1
            ;;
        "")
            log_warning "Статус смены не определен"
            return 2
            ;;
        *)
            log_warning "Неизвестный статус смены: $SHIFT_STATE"
            return 2
            ;;
    esac
}

start_tspiot_instance() {
    local url="$API_BASE/$API_VERSION/service/start/$KKT_ID"
    log_warning "=== Запускаем уже существующий экземпляр сервиса ЕСМ ==="
    response=$(curl -sS -w "\n%{http_code}" \
        --location \
        --request POST "$url" \
        -H "Content-Type: application/json")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    log_warning "HTTP код: $http_code"
    log_warning "Ответ: $body"
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
      local service_state=""
      local port=""
      local response_id=""
      response_id=$(echo "$body" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
      service_state=$(echo "$body" | sed -n 's/.*"serviceState":"\([^"]*\)".*/\1/p')
      port=$(echo "$body" | sed -n 's/.*"port":\([0-9]*\).*/\1/p')
      if [ "$service_state" = "Работает" ]; then
        log_success "Сервис ЕСМ успешно запущен"
        if [ -n "$port" ]; then
          log_info "Порт сервиса: $port"
        fi
          if [ -n "$response_id" ] && [ "$response_id" = "$KKT_ID" ]; then
            log_info "ID сервиса: $response_id"
          fi
          return 0
        else
            log_warning "Сервис запущен, но состояние: $service_state"
            return 0  # Все равно считаем успехом
        fi
    else
        log_error "Ошибка при запуске сервиса ЕСМ"
        return 1
    fi
}


manage_tspiot() {
    log_info "=== Управление экземпляром ТСП ИОТ ==="

    # Вызываем функцию создания экземпляра
    create_tspiot_instance
    local result_code=$?  # Получаем код возврата функции

    log_info "Код возврата create_tspiot_instance: $result_code"

    case $result_code in
        0)
            log_success "Экземпляр ТСП ИОТ создан успешно"
            ;;
        2) # Возвращается, если экземпляр уже есть, тогда
            log_warning "Экземпляр уже существует (код 1010)"
            log_info "Продолжаем работу с существующим экземпляром"
            start_tspiot_instance # запускаем функцию для старта экземпляра
            ;;
        *)
            log_error "Неизвестный код ошибки: $result_code"
            return 1
            ;;
    esac

    return 0
}

# Выполнить запрос регистрации сервиса ЕСМ с данными из запроса списка подключенных ДККТ
register_tspiot() {
    log_info "Регистрация ЭСМ..."

    local url="$API_BASE/$API_VERSION/tspiot"
    local data="{\"id\": \"$KKT_ID\", \"kktSerial\": \"$KKT_SERIAL\", \"fnSerial\": \"$FN_SERIAL\", \"kktInn\": \"$KKT_INN\"}"

    log_info "URL: PUT $url"
    log_info "Данные: $data"

    response=$(curl -sS -w "\n%{http_code}" \
        --location \
        --request PUT "$url" \
        --header 'Content-Type: application/json' \
        --data "$data")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    log_info "HTTP код: $http_code"
    log_info "Ответ: $body"

    # Проверяем успешный HTTP код
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        # Извлекаем tspiotId
        local tspiot_id=$(echo "$body" | sed -n 's/.*"tspiotId":"\([^"]*\)".*/\1/p')

        # Проверяем, что tspiotId не пустой
        if [ -n "$tspiot_id" ]; then
            log_success "Экземпляр ТСП ИОТ успешно создан, ID: $tspiot_id"
            return 0
        fi
    fi
    # Если дошли сюда - ошибка
    log_error "Ошибка регистрации ЭСМ"
    return 1
}


configure_lm_cz() {
    log_info "=== Настройка ЛМ ЧЗ ==="

    local url="$API_BASE/$API_VERSION/settings/lm/$KKT_ID"

    # Используем предустановленные значения или запрашиваем
    local address="${LM_CZ_ADDRESS:-}"
    local port="${LM_CZ_PORT:-50063}"
    local login="${LM_CZ_LOGIN:-admin}"
    local password="${LM_CZ_PASSWORD:-admin}"

    # Если адрес не задан, запрашиваем
    if [ -z "$address" ]; then
        while true; do
            read -p "Введите IPv4 адрес ЛМ ЧЗ: " address
            if [ -z "$address" ]; then
                log_error "Адрес не может быть пустым!"
                continue
            fi

            if echo "$address" | grep -q '\.' && echo "$address" | grep -q '[0-9]'; then
                break
            else
                log_error "Неверный формат IP адреса!"
            fi
        done
        # Логин
        read -p "Введите логин для ЛМ ЧЗ (по умолчанию admin): " login_input
        login="${login_input:-admin}"

        # Пароль
        read -p "Введите пароль для ЛМ ЧЗ (по умолчанию admin): " password_input
        password="${password_input:-admin}"
    else
        log_info "Используется предустановленный адрес: $address"
    fi

    log_info "Параметры ЛМ ЧЗ:"
    log_info "  Адрес: $address"
    log_info "  Порт: $port"
    log_info "  Логин: $login"
    log_info "  Пароль: $password"

    local data="{\"address\":\"$address\",\"port\":$port,\"login\":\"$login\",\"password\":\"$password\"}"

    log_info "Отправляю запрос..."

    response=$(curl -sS -w "\n%{http_code}" \
        --location \
        --request PUT "$url" \
        --header 'Content-Type: application/json' \
        --data "$data")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    log_info "Ответ: $body (HTTP $http_code)"

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        log_success "ЛМ ЧЗ настроен успешно"
        return 0
    else
        log_error "Ошибка настройки ЛМ ЧЗ"
        return 1
    fi
}


setupGismtAddress() {
    log_info "=== Настройка ГИС МТ ==="

    local url="$API_BASE/$API_VERSION/settings/$KKT_ID"

    # Используем предустановленные значения или стандартные
    local gismt_address="${GISMT_ADDRESS:-https://tsp-test.crpt.ru:19101}"
    local compatibility_mode="${COMPATIBILITY_MODE:-false}"
    local allow_remote="${ALLOW_REMOTE_CONNECTION:-true}"

    log_info "Параметры ГИС МТ:"
    log_info "  Режим совместимости: $compatibility_mode"
    log_info "  Удаленное подключение: $allow_remote"
    log_info "  Адрес ГИС МТ: $gismt_address"

    echo ""
    log_info "Изменить параметры? (y/n): "
#    read -r change

#    if [ "$change" = "y" ] || [ "$change" = "Y" ]; then
#        # Адрес
#        read -p "Адрес ГИС МТ [$gismt_address]: " address_input
#        [ -n "$address_input" ] && gismt_address="$address_input"
#
#        # Режим совместимости
#        echo "Режим совместимости (true/false) [$compatibility_mode]: "
#        read -r compat_input
#        [ -n "$compat_input" ] && compatibility_mode="$compat_input"
#
#        # Удаленное подключение
#        echo "Удаленное подключение (true/false) [$allow_remote]: "
#        read -r remote_input
#        [ -n "$remote_input" ] && allow_remote="$remote_input"
#    fi

    local data="{\"compatibilityMode\":$compatibility_mode,\"allowRemoteConnection\":$allow_remote,\"gismtAddress\":\"$gismt_address\"}"

    log_info "Отправляю запрос..."

    response=$(curl -sS -w "\n%{http_code}" \
        --location \
        --request PUT "$url" \
        --header 'Content-Type: application/json' \
        --data "$data")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    log_info "Ответ: $body (HTTP $http_code)"

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ] || [ "$http_code" -eq 204 ]; then
        log_success "Настройки ГИС МТ применены успешно"
        return 0
    else
        log_error "Ошибка настройки ГИС МТ"
        return 1
    fi
}



main() {
    echo "==================================="
    echo "Работа с API ТСП ИОТ"
    echo "==================================="


    echo "Отсылаем стандартные данные для настроек ЛМ ЧЗ, ГИС МТ"
    export COMPATIBILITY_MODE="false"
    export ALLOW_REMOTE_CONNECTION="true"
    export LM_CZ_ADDRESS="10.9.130.12"
    export LM_CZ_PORT="50063"
    export LM_CZ_LOGIN="admin"
    export LM_CZ_PASSWORD="admin"



    log_info "Получение списка ККТ..."
    # 1. Получаем список ККТ
    if ! get_dkkt_list; then
        log_error "Не удалось получить данные ККТ"
        return 1
    fi


    # 2. Проверяем, что смена открыта на кассе, если нет - alert
    if ! check_shift_state; then
        return 1
    fi


    # 3. Создаём инстанс tspiot
    if ! manage_tspiot; then
      log_error "==================================="
      log_error "При создании экзмепляра tspiot возникла ошибка (код: $?)"
      log_error "Обратитесь к инструкции по развёртыванию или свяжитесь с поддержкой tspiot"
      log_error "==================================="
      exit 1
    fi

    if ! register_tspiot; then
      log_error "Ошибка Регистрации (Неверные адреса для регистрации / проблемы с сетью / проблема с лицензией) : tspiotId пуст после успешного создания"
      exit 1
    fi

    if ! configure_lm_cz; then
      log_error "Ошибка на этапе подключения к экземпляру локального модуля для ЛМ ЧЗ"
      log_error "Проверьте, что сервер имеет доступ к серверу, где расположен локальный модуль"
      log_error "Если у вас не получается решить проблему - дайте логи работы controlmodule и логи с сервера из папки локального модуля lmcontroller"
      exit 1
    fi

    if ! setupGismtAddress; then
      log_error "Ошибка на этапе подключения к экземпляру локального модуля для ЛМ ЧЗ"
      exit 1
    fi

    echo "==================================="
    log_success "Все операции выполнены успешно!"
    echo "==================================="
    return 0
}

# Запуск основной функции
main "$@"
exit $?