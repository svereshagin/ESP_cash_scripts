SSH_OPTIONS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
TINYCORE_SERVER_IP="10.9.130.187"
TINYCORE_USERNAME="tc"
PASSWORD="324012"

connect_to_server() {
  echo "Подключение к серверу $TINYCORE_SERVER_IP..."
  sshpass -p "$PASSWORD" ssh $SSH_OPTIONS "$TINYCORE_USERNAME@$TINYCORE_SERVER_IP"
}

connect_to_server