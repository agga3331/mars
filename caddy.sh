#!/usr/bin/env bash
set -euo pipefail

# ==========================
# Настройки
# ==========================
LOG_FILE="./install.log"
FORCE=false

# ==========================
# Цветной вывод
# ==========================
green() { echo -e "\033[1;32m$*\033[0m" | tee -a "$LOG_FILE"; }
yellow() { echo -e "\033[1;33m$*\033[0m" | tee -a "$LOG_FILE"; }
red() { echo -e "\033[1;31m$*\033[0m" | tee -a "$LOG_FILE"; }

# ==========================
# Обработка флагов
# ==========================
while [[ $# -gt 0 ]]; do
  case $1 in
    --log)
      LOG_FILE="$2"
      shift
      ;;
    --force)
      FORCE=true
      ;;
    -h|--help)
      echo "Установка Caddy + Layer4"
      echo "Использование: $0 [опции]"
      echo "  --force          Принудительно переустановить Go и Caddy"
      echo "  --log FILE       Указать файл лога (по умолчанию ./install.log)"
      echo "  -h, --help       Показать справку"
      exit 0
      ;;
    *)
      red "Неизвестный флаг: $1"
      exit 1
      ;;
  esac
  shift
done

# ==========================
# Проверка root-доступа
# ==========================
if [[ $EUID -ne 0 ]]; then
  yellow "⚠️  Скрипт не запущен от root. sudo будет запрашивать пароль."
fi

# ==========================
# Очистка лога
# ==========================
: > "$LOG_FILE"
green "📝 Лог: $LOG_FILE"

# ==========================
# Проверка наличия Go и Caddy
# ==========================
GO_INSTALLED=false
CADDY_INSTALLED=false

if command -v go >/dev/null 2>&1; then
  GO_INSTALLED=true
  yellow "✅ Go уже установлен: $(go version)"
fi

if command -v caddy >/dev/null 2>&1; then
  CADDY_INSTALLED=true
  yellow "✅ Caddy уже установлен: $(caddy version 2>/dev/null || echo 'версия неизвестна')"
fi

# ==========================
# Функции установки
# ==========================
install_go() {
  green "[1/9] Устанавливаем Go 1.23.2..."
  wget -q https://go.dev/dl/go1.23.2.linux-amd64.tar.gz
  sudo tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz
  echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
  export PATH=$PATH:/usr/local/go/bin
  source ~/.bashrc
  go version | tee -a "$LOG_FILE"
}

install_caddy() {
  green "[2/9] Устанавливаем стандартный Caddy..."
  sudo apt update
  sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list
  sudo apt update && sudo apt -y install caddy
}

install_xcaddy() {
  green "[3/9] Устанавливаем xcaddy и Layer4..."
  curl -fsSL https://getcaddy.com | bash -s personal
  go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
  export PATH=$PATH:$(go env GOPATH)/bin
  echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
  source ~/.bashrc
  xcaddy version | tee -a "$LOG_FILE"
  xcaddy build --with github.com/mholt/caddy-l4
}

replace_binary() {
  green "[4/9] Подмена бинарника Caddy..."
  sudo systemctl stop caddy || true
  sudo mv ./caddy /usr/bin/caddy
  sudo setcap cap_net_bind_service=+ep /usr/bin/caddy
  sudo systemctl restart caddy
  sudo systemctl status caddy --no-pager | tee -a "$LOG_FILE"
}

backup_and_write_caddyfile() {
  green "[5/9] Бэкап и настройка Caddyfile..."
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
}

validate_caddy() {
  green "[6/9] Проверка Caddyfile..."
  caddy validate --config /etc/caddy/Caddyfile | tee -a "$LOG_FILE"
  caddy fmt --overwrite /etc/caddy/Caddyfile
  caddy validate --config /etc/caddy/Caddyfile | tee -a "$LOG_FILE"
}

reload_caddy() {
  green "[7/9] Перезагрузка Caddy..."
  sudo systemctl reload caddy
  sudo systemctl status caddy --no-pager | tee -a "$LOG_FILE"
}

# ==========================
# Основная логика
# ==========================
if [[ "$GO_INSTALLED" == false || "$FORCE" == true ]]; then
  install_go
else
  green "⏩ Пропуск установки Go"
fi

if [[ "$CADDY_INSTALLED" == false || "$FORCE" == true ]]; then
  install_caddy
else
  green "⏩ Пропуск установки Caddy"
fi

install_xcaddy
replace_binary
backup_and_write_caddyfile
validate_caddy
reload_caddy

green "✅ Установка и конфигурация Caddy + Layer4 завершена!"
green "📄 Лог: $LOG_FILE"
