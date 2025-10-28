#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="./install.log"

# ==========================
# Цветной вывод
# ==========================
green() { echo -e "\033[1;32m$*\033[0m" | tee -a "$LOG_FILE"; }
yellow() { echo -e "\033[1;33m$*\033[0m" | tee -a "$LOG_FILE"; }
red() { echo -e "\033[1;31m$*\033[0m" | tee -a "$LOG_FILE"; }

# Очистка лога
: > "$LOG_FILE"
green "📝 Лог: $LOG_FILE"

# ==========================
# Установка Go (если нет)
# ==========================
if ! command -v go >/dev/null 2>&1; then
    green "[1/9] Устанавливаем Go 1.23.2..."
    wget -q https://go.dev/dl/go1.23.2.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin
    source ~/.bashrc
else
    yellow "✅ Go уже установлен: $(go version)"
fi

# Добавим Go в PATH, если не в системе
if ! command -v go >/dev/null 2>&1; then
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    source ~/.bashrc
fi

go version | tee -a "$LOG_FILE"

# ==========================
# Установка Caddy (если нет)
# ==========================
if ! command -v caddy >/dev/null 2>&1; then
    green "[2/9] Устанавливаем стандартный Caddy..."
    sudo apt update
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update && sudo apt -y install caddy
else
    yellow "✅ Caddy уже установлен: $(caddy version 2>/dev/null || echo 'версия неизвестна')"
fi

# ==========================
# Установка xcaddy
# ==========================
if ! command -v xcaddy >/dev/null 2>&1; then
    green "[3/9] Устанавливаем xcaddy..."
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    export PATH=$PATH:$(go env GOPATH)/bin
    echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
    source ~/.bashr
