CODES='["MDEwNjI3MTU4MjY5MjIyNjIxNU1OMDsmHTkxRkZEMB05MmRHVnpkR1owcW9BZnVxV3pRUXRTbDZVRmJaWU9HSFdwOTgrd3FQRTl0TTQ9"]'

DATA='{"codes":'"$CODES"',"client_info":{"name":"Postman","version":"3.6.4","id":"8866a527-8da1-4ac9-b48b-b2b88f692a29","token":"6312020b-4cd4-4fac-9217-f4499fa9c624"}}'

RESPONSE=$(curl -k -s -X POST https://localhost:51401/api/v1/codes/check \
          --header 'Content-Type: application/json' \
          --data "$DATA")

echo '[INFO] Ответ от сервера:'
echo "$RESPONSE"
echo ''

# Функция для извлечения значения из JSON
get_json_value() {
    echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | cut -d'"' -f4
}

get_json_value_num() {
    echo "$1" | grep -o "\"$2\":[0-9]*" | cut -d: -f2
}

get_json_value_bool() {
    echo "$1" | grep -o "\"$2\":[a-z]*" | cut -d: -f2
}

echo 'Ключевые параметры:'
echo "code: $(get_json_value_num "$RESPONSE" "code")"
echo "isCheckedOffline: $(get_json_value_bool "$RESPONSE" "isCheckedOffline")"
echo "isBlocked: $(get_json_value_bool "$RESPONSE" "isBlocked")"