#!/bin/bash

SSH_OPTIONS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
TINYCORE_SERVER_IP="10.9.130.187"
TINYCORE_USERNAME="tc"
PASSWORD="324012"

echo "Запуск проверки марки на удаленном сервере..."
echo ""

sshpass -p "$PASSWORD" ssh $SSH_OPTIONS "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP" "
echo 'Выполняю проверку марки...'
RESPONSE=\$(curl -k -s -X POST https://localhost:51401/api/v1/codes/check --header 'Content-Type: application/json' --data '{\"codes\":[\"MDEwNjI3MTU4MjY5MjIyNjIxNU1OMDsmHTkxRkZEMB05MmRHVnpkR1owcW9BZnVxV3pRUXRTbDZVRmJaWU9HSFdwOTgrd3FQRTl0TTQ9\"],\"client_info\":{\"name\":\"Postman\",\"version\":\"3.6.4\",\"id\":\"8866a527-8da1-4ac9-b48b-b2b88f692a29\",\"token\":\"6312020b-4cd4-4fac-9217-f4499fa9c624\"}}')
echo ''
echo 'Ответ от сервера:'
echo \"\$RESPONSE\"
echo ''
echo 'Ключевые параметры:'
echo 'code: ' \$(echo \"\$RESPONSE\" | grep -o '\"code\":[0-9]*' | head -n 1 | cut -d: -f2)
echo 'isCheckedOffline: ' \$(echo \"\$RESPONSE\" | grep -o '\"isCheckedOffline\":[a-z]*' | cut -d: -f2)
echo 'isBlocked: ' \$(echo \"\$RESPONSE\" | grep -o '\"isBlocked\":[a-z]*' | cut -d: -f2)
"

echo ""
echo "Проверка завершена."