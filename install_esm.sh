#!/bin/sh

#Конфигурация ЛМ ЧЗ
LM_CZ_ADDRESS=""
LM_CZ_PORT=""
LM_CZ_LOGIN=""
LM_CZ_PASSWORD=""

GISMT_ADDRESS=""
COMPATIBILITY_MODE=""
ALLOW_REMOTE_CONNECTION=""

INTERACTIVE_MODE=false
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

parse_kkt_response() {
    local response="$1"

    debug_log "Используем sed для парсинга JSON"
    # Fallback на sed если jq не установлен
    KKT_SERIAL=$(echo "$response" | sed -n 's/.*"kktSerial":"\([^"]*\)".*/\1/p')
    FN_SERIAKKT_ID=""L=$(echo "$response" | sed -n 's/.*"fnSerial":"\([^"]*\)".*/\1/p')
    KKT_INN=$(echo "$response" | sed -n 's/.*"kktInn":"\([^"]*\)".*/\1/p')
    KKT_RNM=$(echo "$response" | sed -n 's/.*"kktRnm":"\([^"]*\)".*/\1/p')
    MODEL_NAME=$(echo "$response" | sed -n 's/.*"modelName":"\([^"]*\)".*/\1/p')
    DKKT_VERSION=$(echo "$response" | sed -n 's/.*"dkktVersion":"\([^"]*\)".*/\1/p')
    DEVELOPER=$(echo "$response" | sed -n 's/.*"developer":"\([^"]*\)".*/\1/p')
    MANUFACTURER=$(echo "$response" | sed -n 's/.*"manufacturer":"\([^"]*\)".*/\1/p')
    SHIFT_STATE=$(echo "$response" | sed -n 's/.*"shiftState":"\([^"]*\)".*/\1/p')

    # ID = серийный номер ККТ
    KKT_ID="${KKT_SERIAL}"

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


check_existance_in_config_tspiotid() {
  log_info "Проверка наличия esmID в файле: $config_file"
    local config_file="/etc/esp/esm/um/config_${KKT_ID}.yml"

    # Проверяем существование файла
    if [ ! -f "$config_file" ]; then
        log_error "Файл конфигурации не найден: $config_file"
        return 1
    fi

    # Ищем строку с esmID: используя grep
    local esm_line=$(grep -E '^\s*esmID:' "$config_file" | head -1)

    if [ -z "$esm_line" ]; then
        log_error "Поле esmID не найдено в файле"
        return 1
    fi

    # Извлекаем значение после двоеточия
    # Убираем начальные пробелы и "esmID:"
    local value=$(echo "$esm_line" | sed -n 's/^[[:space:]]*esmID:[[:space:]]*//p')

    # Убираем кавычки если есть
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"

    # Убираем возможные комментарии в конце строки
    value="${value%%#*}"  # Убираем все после #
    value="${value%"${value##*[![:space:]]}"}"  # Убираем конечные пробелы

    if [ -z "$value" ]; then
        log_error "Поле esmID пустое"
        return 1
    fi

    log_success "Поле esmID найдено: $value"
    echo "$value"
    return 0
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

    local max_retries=4
    local timeout=20
    local retry_count=0

    local url="$API_BASE/$API_VERSION/tspiot"
    local data="{\"id\": \"$KKT_ID\", \"kktSerial\": \"$KKT_SERIAL\", \"fnSerial\": \"$FN_SERIAL\", \"kktInn\": \"$KKT_INN\"}"

    log_info "URL: PUT $url"
    log_info "Данные: $data"

    while [ $retry_count -lt $max_retries ]; do
        retry_count=$((retry_count + 1))

        log_info "Попытка $retry_count из $max_retries"

        # ВАЖНО: Добавляем timeout перед curl
        response=$(curl -sS -w "\n%{http_code}" \
                --location \
                --request PUT "$url" \
                --header 'Content-Type: application/json' \
                --data "$data" \
                --connect-timeout 10 \
                --max-time 20 \
                --retry 0 2>&1)  # Перенаправляем stderr в stdout

        local curl_exit_code=$?

        log_warning "[DEBUG] curl exit code: $curl_exit_code"

        # Проверяем таймаут команды timeout (124) или curl (28)
        if [ $curl_exit_code -eq 124 ] || [ $curl_exit_code -eq 28 ]; then
            log_warning "Вышло время на подключение к серверу для получения tspiot_id ($timeout сек) при попытке $retry_count/$max_retries"
            if [ $retry_count -lt $max_retries ]; then
                sleep 2
            fi
            continue
        elif [ $curl_exit_code -ne 0 ]; then
            log_warning "Ошибка curl (код: $curl_exit_code) при попытке $retry_count"
            if [ $retry_count -lt $max_retries ]; then
                sleep 2
            fi
            continue
        fi

        # Получаем HTTP код и тело ответа
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
                log_success "Экземпляр ТСПИОТ успешно создан, ID: $tspiot_id"
                return 0
            else
                log_warning "Успешный HTTP код, но tspiotId не найден в ответе"
                if [ $retry_count -lt $max_retries ]; then
                    sleep 2
                    continue
                fi
            fi
        else
            log_warning "Неуспешный HTTP код: $http_code"
            if [ $retry_count -lt $max_retries ]; then
                sleep 2
                continue
            fi
        fi
    done

    log_error "Ошибка регистрации tspiot_id после $max_retries попыток"
    if [ -n "$http_code" ]; then
        log_error "Последний HTTP код: $http_code"
    fi
    if [ -n "$body" ]; then
        log_error "Последний ответ: $body"
    fi

    check_existance_in_config_tspiotid > /dev/null  #возврат значения функции
    if [ $? -eq 0 ]; then
        log_warning "Результат регистрации вернул ошибку, когда уже есть значение в esmID"
        return 0
    fi
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



resolveGismtStatusResponse() {
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | sed '$d' 2>/dev/null || echo "")
  log_info "resolveGismtStatusResponse Ответ: $body (HTTP $http_code)"
  case "$http_code" in
      000)
        log_error "Ошибка сети/таймаут - нет соединения с сервером"
        return 2  # Специальный код для повторной попытки
        ;;
      200|201|204)
        log_success "Настройки ГИС МТ успешно применены"
        ;;
      400)
        log_error "Ошибка 400: Неверный запрос. Проверьте данные JSON"
        log_info "Отправленные данные: $data"
        return 1
        ;;
      401|403)
        log_error "Ошибка $http_code: Проблемы с аутентификацией/авторизацией"
        return 1
        ;;
      404)
        log_error "Ошибка 404: Ресурс не найден. Проверьте KKT_ID: $KKT_ID"
        return 1
        ;;
      500|502|503|504)
        log_warning "Ошибка $http_code: Проблемы на стороне сервера, пробуем снова"
        return 2  # Повторная попытка
        ;;
      28) # curl timeout
        log_error "Таймаут подключения к серверу"
        return 2
        ;;
      7) # curl couldn't connect
        log_error "Не удалось подключиться к серверу"
        return 2
        ;;
      *)
        log_warning "Непредвиденный ответ HTTP $http_code"
        if [ -n "$body" ]; then
          log_info "Тело ответа: $body"
        fi
        return 2  # Пробуем снова
        ;;
    esac
}

setupGismtAddress() {
    log_info "=== Настройка ГИС МТ ==="

    # retry логика программы
    local max_attempts=6           # Максимум 6 попыток
    local attempt_timeout=30       # Таймаут одной попытки (сек)
    local total_timeout=300        # Общий таймаут 5 минут
    local retry_delay=10           # Задержка между попытками
    local start_time=$(date +%s)

    local url="$API_BASE/$API_VERSION/settings/$KKT_ID"

    local gismt_address=""
    local compatibility_mode=""
    local allow_remote=""
    if [ -z "$GISMT_ADDRESS"]; then
      log_info "Адрес GISMT не указан"    # Исправленный блок ввода адреса
      while true; do
          read -p "Введите адрес для GISMT (дефолтный: https://ts-reg.crpt.ru:19100) : " gismt_address

          # Проверка на пустую строку
          if [ -z "$gismt_address" ]; then
              log_error "Адрес не может быть пустым!"
              continue
          fi

          # Устанавливаем дефолтное значение если введена пустая строка
          if [ -z "$gismt_address" ]; then
              gismt_address="https://ts-reg.crpt.ru:19100"
          fi

          # Проверяем, начинается ли строка с https://
          case "$gismt_address" in
              https://*)
                  # Извлекаем часть после протокола
                  address_without_protocol="${gismt_address#https://}"

                  # Проверяем, что после протокола что-то есть
                  if [ -z "$address_without_protocol" ]; then
                      log_error "После https:// должен быть указан адрес!"
                      continue
                  fi

                  # Упрощенная проверка формата (без regex)
                  if echo "$address_without_protocol" | grep -q -E '^([a-zA-Z0-9.-]+|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(:[0-9]+)?(/.*)?$'; then
                      log_info "Адрес GISMT корректен: $gismt_address"
                      break
                  else
                      log_error "Неверный формат адреса после https://!"
                      log_error "Пример правильного формата: https://tsp-test.crpt.ru:19101"
                  fi
                  ;;
              *)
                  log_error "Адрес должен начинаться с https://"
                  ;;
          esac
      done
    else
      gismt_address$GISMT_ADDRESS
    fi

   if [ -z "COMPATIBILITY_MODE"]; then
      log_info "COMPATIBILITY_MODE не указан"    #
      while true; do
          read -p "Режим совместимости? (true/false) [false]: " compatibility_mode
          compatibility_mode=${compatibility_mode:-false}
          compatibility_mode=$(echo "$compatibility_mode" | tr '[:upper:]' '[:lower:]')

          case "$compatibility_mode" in
              true|yes|y|1)
                  compatibility_mode="true"
                  break
                  ;;
              false|no|n|0)
                  compatibility_mode="false"
                  break
                  ;;
              *)
                  log_error "Введите true или false"
                  ;;
          esac
      done
     else
       compatibility_mode=$COMPATIBILITY_MODE
    fi

    if [ -z "$ALLOW_REMOTE_CONNECTION"]; then
        log_info "ALLOW_REMOTE_CONNECTION не указан"
      while true; do
          read -p "Разрешить удаленные подключения? (true/false) [true]: " allow_remote
          allow_remote=${allow_remote:-true}
          allow_remote=$(echo "$allow_remote" | tr '[:upper:]' '[:lower:]')

          case "$allow_remote" in
              true|yes|y|1)
                  allow_remote="true"
                  break
                  ;;
              false|no|n|0)
                  allow_remote="false"
                  break
                  ;;
              *)
                  log_error "Введите true или false"
                  ;;
          esac
      done
      else
      allow_remote=$ALLOW_REMOTE_CONNECTION
    fi
    log_info "Параметры ГИС МТ:"
    log_info "  Режим совместимости: $compatibility_mode"
    log_info "  Удаленное подключение: $allow_remote"
    log_info "  Адрес ГИС МТ: $gismt_address"

    local data="{\"compatibilityMode\":$compatibility_mode,\"allowRemoteConnection\":$allow_remote,\"gismtAddress\":\"$gismt_address\"}"

    log_info "Отправляю запрос..."

    for attempt in $(seq 1 $max_attempts); do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Проверяем общий таймаут
        if [ $elapsed -ge $total_timeout ]; then
            log_error "Превышен общий лимит времени ($total_timeout секунд)"
            return 1
        fi

        log_info "Попытка $attempt/$max_attempts (прошло ${elapsed}с из ${total_timeout}с)..."

        response=$(curl -sS -w "\n%{http_code}" \
            --location \
            --request PUT "$url" \
            --header 'Content-Type: application/json' \
            --data "$data" \
            --max-time $attempt_timeout \
            --connect-timeout 15 \
            --retry 0 \
            2>&1)

        local curl_exit_code=$?
        local http_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | head -n -1)

        case $curl_exit_code in
            0)
                if resolveGismtStatusResponse "$response_body" "$http_code"; then
                    local total_elapsed=$(( $(date +%s) - start_time ))
                    log_success "Настройка ГИС МТ завершена успешно за ${total_elapsed} секунд"
                    return 0
                else
                    local result_code=$?
                    if [ $result_code -eq 2 ]; then
                        # Нужно повторить
                        if [ $attempt -lt $max_attempts ]; then
                            log_info "Повтор через ${retry_delay} секунд..."
                            sleep $retry_delay
                            # Увеличиваем задержку для следующей попытки (exponential backoff)
                            retry_delay=$((retry_delay * 2))
                            continue
                        else
                            log_error "Исчерпаны все попытки ($max_attempts)"
                        fi
                    else
                        return 1
                    fi
                fi
                ;;
            28)
                log_error "Таймаут запроса (${attempt_timeout}с)"
                ;;
            7)
                log_error "Не удалось подключиться к серверу $API_BASE"
                ;;
            *)
                log_error "Ошибка curl (код: $curl_exit_code)"
                ;;
        esac

        if [ $attempt -lt $max_attempts ]; then
            log_info "Повтор через ${retry_delay} секунд..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
        fi
    done

    log_error "Не удалось настроить ГИС МТ после $max_attempts попыток"
    log_info ""
    log_info "Рекомендации по устранению:"
    log_info "  1. Проверьте сетевые настройки и firewall"
    log_info "  2. Попробуйте настроить вручную"
    log_info ""
    return 1
}



check_gismt_config() {
    local config_file="/etc/esp/esm/um/config_${KKT_ID}.yml"

    # Ищем URL ГИС МТ
    if grep -A5 "gisMT:" "$config_file" | grep -q "url:.*https\?://"; then
        log_info "GISMT адрес найден и валидный"
        return 0
    else
        log_info "GISMT адрес не найден или не валидный"
        return 1
    fi
}


#МАРКА
extract_parameters() {
    local response="$1"

    log_info "Анализ ответа API..."

    # Извлекаем параметры
    code_val=$(echo "$response" | grep -o '"code":[0-9]*' | head -n 1 | cut -d: -f2)
    is_checked_offline=$(echo "$response" | grep -o '"isCheckedOffline":[a-z]*' | cut -d: -f2)
    is_blocked=$(echo "$response" | grep -o '"isBlocked":[a-z]*' | cut -d: -f2)
    found=$(echo "$response" | grep -o '"found":[a-z]*' | cut -d: -f2)
    valid=$(echo "$response" | grep -o '"valid":[a-z]*' | cut -d: -f2)

    # Логируем параметры
    log_info "Параметры ответа:"
    log_info "  - code: $code_val"
    log_info "  - isCheckedOffline: $is_checked_offline"
    log_info "  - isBlocked: $is_blocked"
    log_info "  - found: $found"
    log_info "  - valid: $valid"
}

#МАРКА
analyze_results() {
    echo ""
    log_info "Проверка результатов:"

    # Проверка блокировки марки
    if [ "$is_blocked" = "false" ]; then
        log_success "Марка не заблокирована в системе"
    else
        log_error "Марка заблокирована в системе"
    fi

    # Проверка режима работы
    if [ "$is_checked_offline" = "false" ]; then
        log_success "Режим работы: онлайн (подключение к ГИС МТ)"
    else
        log_warning "Режим работы: оффлайн (локальная проверка)"
    fi

    # Проверка кода ответа
    if [ "$code_val" = "0" ]; then
        log_success "Код ответа API: 0 (успех)"
    else
        log_warning "Код ответа API: $code_val (не 0)"
    fi

    # Итоговый вывод
    echo ""
    log_info "Итоговая оценка работы системы:"

    if [ "$is_checked_offline" = "false" ] && [ "$is_blocked" = "false" ] && [ "$code_val" = "0" ]; then
        log_success "Система работает корректно"
        log_success "Подключение к ГИС МТ функционирует"
        log_success "Все проверки пройдены успешно"
    else
        log_warning "Обнаружены отклонения в работе системы"

        if [ "$is_checked_offline" = "true" ]; then
            log_warning "Рекомендация: Проверить подключение к ГИС МТ"
        fi

        if [ "$is_blocked" = "true" ]; then
            log_warning "Рекомендация: Проверить статус марки в системе"
        fi

        if [ "$code_val" != "0" ]; then
            log_warning "Рекомендация: Проверить логи API"
        fi
    fi
}

#МАРКА
check_mark() {
  log_info "Запуск проверки подключения к ГИС МТ"

  log_info "Отправка запроса к API проверки кодов..."
  response=$(curl -k -s -X POST https://localhost:51401/api/v1/codes/check \
    --header 'Content-Type: application/json' \
    --data '{
      "codes": ["MDEwNjI3MTU4MjY5MjIyNjIxNU1OMDsmHTkxRkZEMB05MmRHVnpkR1owcW9BZnVxV3pRUXRTbDZVRmJaWU9HSFdwOTgrd3FQRTl0TTQ9"],
      "client_info": {
          "name": "Postman",
          "version": "3.6.4",
          "id": "8866a527-8da1-4ac9-b48b-b2b88f692a29",
          "token": "6312020b-4cd4-4fac-9217-f4499fa9c624"
      }
  }')

  if [ $? -ne 0 ]; then
      log_error "Не удалось выполнить запрос к API"
      exit 1
  fi

  log_success "Запрос успешно выполнен"
  log_info "Статус HTTP: 200"

  echo ""
  log_info "Полученный ответ от API:"
  echo "$response"
  echo ""


  extract_parameters "$response"

  analyze_results
}

show_help() {
    cat <<EOF
Конфигуратор драйвера ESM
Версия: 2.0

Использование: $0 [ОПЦИИ]

Опции:
  --default                     Cтандартная установка в интерактивном режиме, будет затребован ввод значений в необходимых
                                для этого местах. Параметры, указанные после --default, перезапишут соответствующие значения по умолчанию.

  --LM_CZ_ADDRESS АДРЕС         Адрес сервера LM_CZ (по умолчанию: localhost)
  --LM_CZ_PORT ПОРТ             Порт сервера LM_CZ (по умолчанию: 50063)
  --LM_CZ_LOGIN ЛОГИН           Логин для подключения к LM_CZ (по умолчанию: admin)
  --LM_CZ_PASSWORD ПАРОЛЬ       Пароль для подключения к LM_CZ (по умолчанию: admin)
  --GISMT_ADDRESS АДРЕС         Адрес сервера GISMT (по умолчанию: https://ts-reg.crpt.ru:19100)
  --COMPATIBILITY_MODE РЕЖИМ    Режим совместимости (по умолчанию: false)
  --ALLOW_REMOTE_CONNECTION     Разрешить удаленные подключения (по умолчанию: true)
  --help, -h                    Показать эту справку

Примеры:
  $0 --default
  $0 --LM_CZ_ADDRESS 192.168.1.100 --LM_CZ_LOGIN admin --LM_CZ_PASSWORD admin
  $0 --default --ALLOW_REMOTE_CONNECTION false
  $0 --LM_CZ_ADDRESS 10.0.0.1 --GISMT_ADDRESS https://ts-reg.crpt.ru:19100 --COMPATIBILITY_MODE true
  $0 --LM_CZ_ADDRESS localhost --LM_CZ_PORT 50063 --COMPATIBILITY_MODE false

Примечания:
  - Значения для COMPATIBILITY_MODE и ALLOW_REMOTE_CONNECTION могут быть true или false
EOF
    exit 0
}

parse_arguments() {
    # Если нет аргументов, показываем справку
    if [ $# -eq 0 ]; then
        echo "[INFO] Аргументы не указаны. Показываю справку..."
        show_help
    fi

    while [ $# -gt 0 ]; do
        case $1 in
            --default)
                if [ "$INTERACTIVE_MODE" = true ]; then
                    echo "[WARNING] Флаг --default уже был указан ранее"
                fi
                INTERACTIVE_MODE=true
                echo "[DEBUG] Обнаружен флаг: --default"
                shift
                ;;
            --LM_CZ_ADDRESS)
                if [ -z "$2" ] || [ "$(echo "$2" | cut -c1-2)" = "--" ]; then
                    echo "[ERROR] Флаг --LM_CZ_ADDRESS требует аргумент"
                    exit 1
                fi
                LM_CZ_ADDRESS="$2"
                echo "[DEBUG] Обнаружен флаг: --LM_CZ_ADDRESS со значением: $2"
                shift 2
                ;;
            --LM_CZ_PORT)
                if [ -z "$2" ] || [ "$(echo "$2" | cut -c1-2)" = "--" ]; then
                    echo "[ERROR] Флаг --LM_CZ_PORT требует аргумент"
                    exit 1
                fi
                # Проверяем что это число с помощью expr
                if expr "$2" : '^[0-9][0-9]*$' >/dev/null && \
                   [ "$2" -ge 1 ] && [ "$2" -le 65535 ]; then
                    LM_CZ_PORT="$2"
                    echo "[DEBUG] Обнаружен флаг: --LM_CZ_PORT со значением: $2"
                else
                    echo "[ERROR] Флаг --LM_CZ_PORT требует числовой аргумент от 1 до 65535"
                    exit 1
                fi
                shift 2
                ;;
            --LM_CZ_LOGIN)
                if [ -z "$2" ] || [ "$(echo "$2" | cut -c1-2)" = "--" ]; then
                    echo "[ERROR] Флаг --LM_CZ_LOGIN требует аргумент"
                    exit 1
                fi
                LM_CZ_LOGIN="$2"
                echo "[DEBUG] Обнаружен флаг: --LM_CZ_LOGIN со значением: $2"
                shift 2
                ;;
            --LM_CZ_PASSWORD)
                if [ -z "$2" ] || [ "$(echo "$2" | cut -c1-2)" = "--" ]; then
                    echo "[ERROR] Флаг --LM_CZ_PASSWORD требует аргумент"
                    exit 1
                fi
                LM_CZ_PASSWORD="$2"
                echo "[DEBUG] Обнаружен флаг: --LM_CZ_PASSWORD (значение скрыто)"
                shift 2
                ;;
            --GISMT_ADDRESS)
                if [ -z "$2" ] || [ "$(echo "$2" | cut -c1-2)" = "--" ]; then
                    echo "[ERROR] Флаг --GISMT_ADDRESS требует аргумент"
                    exit 1
                fi
                GISMT_ADDRESS="$2"
                echo "[DEBUG] Обнаружен флаг: --GISMT_ADDRESS со значением: $2"
                shift 2
                ;;
            --COMPATIBILITY_MODE)
                if [ -z "$2" ] || [ "$(echo "$2" | cut -c1-2)" = "--" ]; then
                    echo "[ERROR] Флаг --COMPATIBILITY_MODE требует аргумент"
                    exit 1
                fi
                # Используем case для проверки true/false
                case "$2" in
                    true|false)
                        COMPATIBILITY_MODE="$2"
                        echo "[DEBUG] Обнаружен флаг: --COMPATIBILITY_MODE со значением: $2"
                        ;;
                    *)
                        echo "[ERROR] Флаг --COMPATIBILITY_MODE требует 'true' или 'false'"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --ALLOW_REMOTE_CONNECTION)
                if [ -z "$2" ] || [ "$(echo "$2" | cut -c1-2)" = "--" ]; then
                    echo "[ERROR] Флаг --ALLOW_REMOTE_CONNECTION требует аргумент"
                    exit 1
                fi
                # Используем case для проверки true/false
                case "$2" in
                    true|false)
                        ALLOW_REMOTE_CONNECTION="$2"
                        echo "[DEBUG] Обнаружен флаг: --ALLOW_REMOTE_CONNECTION со значением: $2"
                        ;;
                    *)
                        echo "[ERROR] Флаг --ALLOW_REMOTE_CONNECTION требует 'true' или 'false'"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --help|-h)
                echo "[DEBUG] Обнаружен флаг: --help"
                show_help
                ;;
            --*)
                echo "[ERROR] Неизвестный флаг: $1"
                echo "Используйте --help для получения списка доступных флагов"
                exit 1
                ;;
            -*)
                echo "[ERROR] Неизвестная короткая опция: $1"
                echo "Используйте --help для получения списка доступных флагов"
                exit 1
                ;;
            *)
                echo "[ERROR] Неожиданный аргумент: $1"
                echo "Все аргументы должны начинаться с --"
                echo "Используйте --help для получения справки"
                exit 1
                ;;
        esac
    done
}

echo_configuration() {
      if [ "$INTERACTIVE_MODE" = true ]; then
        log_info "Активирован интерактивный режим"
      fi

      if [ -n "$COMPATIBILITY_MODE" ]; then
          log_info "Режим совместимости установлен: $COMPATIBILITY_MODE"
      fi

      if [ -n "$LM_CZ_ADDRESS" ]; then
          log_info "Адрес LM_CZ: $LM_CZ_ADDRESS"
      fi

      if [ -n "$LM_CZ_PORT" ]; then
          log_info "Порт LM_CZ: $LM_CZ_PORT"
      fi

      if [ -n "$LM_CZ_LOGIN" ]; then
          log_info "Логин LM_CZ: $LM_CZ_LOGIN"
      fi

      if [ -n "$LM_CZ_PASSWORD" ]; then
          log_info "Пароль LM_CZ: [СКРЫТО]"
      fi

      if [ -n "$GISMT_ADDRESS" ]; then
          log_info "Адрес GISMT: $GISMT_ADDRESS"
      fi

      if [ -n "$ALLOW_REMOTE_CONNECTION" ]; then
          log_info "Разрешение удаленных подключений: $ALLOW_REMOTE_CONNECTION"
      fi
}


main() {
    echo "==================================="
    echo "Работа с API ТСП ИОТ"
    echo "==================================="
    set -- "$@"
    parse_arguments "$@"
    echo_configuration
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
        log_error "Ошибка на этапе регистрации в системе ГИСМТ"
        log_error "Проверяем наличие ГИСМТ адреса в конфигурационном файле"
        # TODO возможно улучшить в версии v2
        if ! check_gismt_config; then
            log_info "Пока непонятно что с этим делать"
        fi
    fi

    if ! check_mark; then
        log_error "Проверка марки прошла проблемно"
        exit 1
    fi

    echo "==================================="
    log_success "Все операции выполнены успешно!"
    echo "==================================="
    return 0
}

# Запуск основной функции
main "$@"
exit 0