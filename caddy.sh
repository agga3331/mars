#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="./install.log"

# ==========================
# Цветной вывод
# ==========================
green() { echo -e "\033[1;32m$*\033[0m" | tee -a "$LOG_FILE"; }
yellow() { echo -e "\033[1;33m$*\033[0m" | tee -a "$LOG_FILE"; }
red() { echo -e "\033[1;31m$*\033[0m" | tee -a "$LOG_FILE"; }

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
    source ~/.bashrc
else
    yellow "✅ xcaddy уже установлен: $(xcaddy version)"
fi

# ==========================
# Сборка Caddy с Layer4
# ==========================
green "[4/9] Сборка Caddy с плагином Layer4..."
xcaddy build --with github.com/mholt/caddy-l4

# ==========================
# Подмена бинарника
# ==========================
green "[5/9] Подмена бинарника Caddy..."
sudo systemctl stop caddy || true
sudo mv ./caddy /usr/bin/caddy
sudo setcap cap_net_bind_service=+ep /usr/bin/caddy
sudo systemctl restart caddy
sudo systemctl status caddy --no-pager | tee -a "$LOG_FILE"

# ==========================
# Настройка Caddyfile
# ==========================
green "[6/9] Бэкап и запись Caddyfile..."
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%s) || true

sudo tee /etc/caddy/Caddyfile >/dev/null <<'EOF'
{
    layer4 {
        0.0.0.0:443 {
            @reality tls sni ozon.com
            route @reality {
                proxy 127.0.0.1:8443
            }
            route {
                proxy 127.0.0.1:8443
            }
        }
    }
}

uk.marss.pro {
    reverse_proxy 127.0.0.1:4443 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF

# ==========================
# Проверка и перезагрузка
# ==========================
green "[7/9] Проверка Caddyfile..."
caddy validate --config /etc/caddy/Caddyfile | tee -a "$LOG_FILE"
caddy fmt --overwrite /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile | tee -a "$LOG_FILE"

green "[8/9] Перезагрузка Caddy..."
sudo systemctl reload caddy
sudo systemctl status caddy --no-pager | tee -a "$LOG_FILE"

green "✅ Установка и настройка Caddy с Layer4 завершена!"
green "📄 Лог: $LOG_FILE"







