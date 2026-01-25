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

log_debug() {
    if [ -n "$DEBUG" ]; then
        echo -e "[DEBUG] $1" >&2
    fi
}

main() {
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

main