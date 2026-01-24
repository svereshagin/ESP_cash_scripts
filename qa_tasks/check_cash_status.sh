#!/bin/bash

SERVER="10.9.130.187"
USER="tc"
PASSWORD="324012"

echo "🔍 Проверка кассы..."

sshpass -p "$PASSWORD" ssh -oHostKeyAlgorithms=+ssh-rsa $USER@$SERVER '
    # Простой и надежный способ
    echo "1. Ищем процесс кассы:"

    # Способ 1: pgrep (самый надежный)
    if pgrep -f "java21.*ru.crystals.pos" > /dev/null; then
        echo "   ✅ Процесс найден"
        CASH_PID=$(pgrep -f "java21.*ru.crystals.pos")
        echo "   PID: $CASH_PID"
    else
        echo "   ❌ Процесс не найден"
        echo "   Пробую найти другим способом..."

        # Способ 2: ps + grep
        cash_proc=$(ps aux | grep -E "java21.*ru\.crystals\.pos" | grep -v grep)
        if [ -n "$cash_proc" ]; then
            echo "   ✅ Найден через ps:"
            echo "   $cash_proc"
            CASH_PID=$(echo "$cash_proc" | awk "{print \$2}")
        else
            echo "   ❌ Касса точно не запущена"
            exit 1
        fi
    fi

    echo ""
    echo "2. Информация о процессе $CASH_PID:"
    ps -p "$CASH_PID" -o user,pcpu,pmem,vsz,rss,cmd --no-headers | \
    awk "{
        printf \"   Пользователь: %s\\n\", \$1
        printf \"   CPU: %s%%\\n\", \$2
        printf \"   Память: %s%%\\n\", \$3
        printf \"   VSZ: %.1fMB\\n\", \$4/1024
        printf \"   RSS: %.1fMB\\n\", \$5/1024
        printf \"   Команда: %s\\n\", \$6
    }"

    echo ""
    echo "3. Проверяем порты:"
    if netstat -tln 2>/dev/null | grep -q ":50401 "; then
        echo "   ✅ Порт 50401 (ESM) открыт"
    else
        echo "   ❌ Порт 50401 закрыт"
    fi

    if netstat -tln 2>/dev/null | grep -q ":8080 "; then
        echo "   ✅ Порт 8080 (веб-интерфейс) открыт"
        echo "   🔗 Откройте в браузере: http://$(hostname -I | awk "{print \$1}"):8080"
    else
        echo "   ❌ Порт 8080 закрыт"
    fi

    echo ""
    echo "4. Память системы:"
    free -m | grep "Mem:" | awk "{
        printf \"   Всего: %sMB\\n\", \$2
        printf \"   Использовано: %sMB\\n\", \$3
        printf \"   Свободно: %sMB\\n\", \$4
    }"
'