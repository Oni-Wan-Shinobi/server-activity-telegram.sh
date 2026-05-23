#!/bin/bash

# ============================================
# SSH Audit Monitor — уведомления о входах и командах
# SSH Audit Monitor — login and command notifications
# ============================================

set -euo pipefail

# Цвета / Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  SSH Audit Monitor v1${NC}"
echo -e "${GREEN}========================================${NC}"

# Выбор языка / Language selection
echo ""
echo -e "${BLUE}Select language / Выберите язык:${NC}"
echo "  1) English"
echo "  2) Русский"
read -r LANG_CHOICE
if [[ "$LANG_CHOICE" == "2" ]]; then
    LANG="ru"
else
    LANG="en"
fi

# UI строки / UI strings
if [ "$LANG" = "ru" ]; then
    T_HEADER="Установка SSH Audit Monitor v1"
    T_ENTER_TOKEN="Введите токен Telegram бота (формат: 123456:ABC-DEF...):"
    T_CHECKING_TOKEN="Проверка токена..."
    T_TOKEN_OK="✅ Токен валиден"
    T_TOKEN_BAD_FORMAT="Ошибка: неверный формат токена!"
    T_TOKEN_INVALID="Ошибка: токен недействителен!"
    T_ENTER_CHATID="Введите ваш Telegram Chat ID:"
    T_CHATID_BAD="Ошибка: Chat ID должен быть числом!"
    T_STARTING="Начинаю установку..."
    T_TG_OK="✅ Тестовое сообщение отправлено"
    T_TG_FAIL="⚠️ Не удалось отправить тестовое сообщение. Проверьте токен и Chat ID."
    T_DONE="УСТАНОВКА ЗАВЕРШЕНА!"
    T_COMMANDS="Полезные команды:"
    T_ALIASES_OK="✅ Алиасы добавлены"
else
    T_HEADER="SSH Audit Monitor v1 Installer"
    T_ENTER_TOKEN="Enter Telegram bot token (format: 123456:ABC-DEF...):"
    T_CHECKING_TOKEN="Checking token..."
    T_TOKEN_OK="✅ Token is valid"
    T_TOKEN_BAD_FORMAT="Error: invalid token format!"
    T_TOKEN_INVALID="Error: token is invalid!"
    T_ENTER_CHATID="Enter your Telegram Chat ID:"
    T_CHATID_BAD="Error: Chat ID must be a number!"
    T_STARTING="Starting installation..."
    T_TG_OK="✅ Test message sent"
    T_TG_FAIL="⚠️ Could not send test message. Check token and Chat ID."
    T_DONE="INSTALLATION COMPLETE!"
    T_COMMANDS="Useful commands:"
    T_ALIASES_OK="✅ Aliases added"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ${T_HEADER}${NC}"
echo -e "${GREEN}========================================${NC}"

# Конфигурация / Configuration
AUDIT_ENV_FILE="/etc/ssh-audit/.env"
AUDIT_LIB_DIR="/usr/local/lib/ssh-audit"
AUDIT_STORAGE_DIR="/var/lib/ssh-audit"
AUDIT_LOG_FILE="/var/log/ssh-audit.log"
CMD_FLUSH_INTERVAL=5  # секунд между отправками пачки команд

# Функции валидации / Validation functions
validate_bot_token() {
    [[ "$1" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]
}

# Ввод данных / Input
echo ""
echo -e "${BLUE}${T_ENTER_TOKEN}${NC}"
read -r BOT_TOKEN
if ! validate_bot_token "$BOT_TOKEN"; then
    echo -e "${RED}${T_TOKEN_BAD_FORMAT}${NC}"
    exit 1
fi

echo -e "${BLUE}${T_CHECKING_TOKEN}${NC}"
if ! curl -s --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" | grep -q '"ok":true'; then
    echo -e "${RED}${T_TOKEN_INVALID}${NC}"
    exit 1
fi
echo -e "${GREEN}${T_TOKEN_OK}${NC}"

echo -e "${BLUE}${T_ENTER_CHATID}${NC}"
read -r CHAT_ID
if [[ ! "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
    echo -e "${RED}${T_CHATID_BAD}${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}${T_STARTING}${NC}"

# 1. Установка пакетов
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[1/10] Установка пакетов..." || echo "[1/10] Installing packages...")${NC}"
sudo apt update -qq
sudo apt install -y auditd audispd-plugins curl jq

# 2. Директории
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[2/10] Создание директорий..." || echo "[2/10] Creating directories...")${NC}"
sudo mkdir -p "$AUDIT_LIB_DIR" "$AUDIT_STORAGE_DIR" /etc/ssh-audit
sudo chmod 755 "$AUDIT_LIB_DIR"
sudo chmod 750 "$AUDIT_STORAGE_DIR"
sudo chmod 750 /etc/ssh-audit

# 3. Пользователь сервиса
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[3/10] Создание пользователя..." || echo "[3/10] Creating service user...")${NC}"
if ! id "ssh-audit" &>/dev/null; then
    sudo useradd -r -s /usr/sbin/nologin -d "$AUDIT_STORAGE_DIR" ssh-audit
fi
sudo chown -R ssh-audit:ssh-audit "$AUDIT_STORAGE_DIR"

# 4. .env файл
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[4/10] Создание конфигурации..." || echo "[4/10] Creating configuration...")${NC}"
sudo tee "$AUDIT_ENV_FILE" > /dev/null << EOF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
HOSTNAME="$(hostname)"
NOTIFY_LANG="${LANG}"
LOG_FILE="${AUDIT_LOG_FILE}"
STORAGE_DIR="${AUDIT_STORAGE_DIR}"
CMD_FLUSH_INTERVAL="${CMD_FLUSH_INTERVAL}"
EOF
sudo chmod 600 "$AUDIT_ENV_FILE"
sudo chown root:ssh-audit "$AUDIT_ENV_FILE"
sudo chmod 640 "$AUDIT_ENV_FILE"
sudo chown root:ssh-audit /etc/ssh-audit
sudo chmod 750 /etc/ssh-audit

# 5. Библиотека функций (переиспользуем геолокацию из common.sh если есть, иначе своя)
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[5/10] Создание библиотеки функций..." || echo "[5/10] Creating function library...")${NC}"
sudo tee "$AUDIT_LIB_DIR/common.sh" > /dev/null << 'EOF'
#!/bin/bash

validate_ipv4() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for octet in 1 2 3 4; do [ "${BASH_REMATCH[$octet]}" -gt 255 ] && return 1; done
        return 0
    fi
    return 1
}

validate_ipv6() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9a-f]{1,4}:){0,7}[0-9a-f]{1,4}$ ]] || \
       [[ "$ip" =~ ^([0-9a-f]{1,4}:){1,7}:$ ]] || \
       [[ "$ip" =~ ^::([0-9a-f]{1,4}:){0,6}[0-9a-f]{1,4}$ ]]; then return 0; fi
    if [[ "$ip" =~ ^::ffff:[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local ipv4="${ip#::ffff:}"; validate_ipv4 "$ipv4" && return 0
    fi
    return 1
}

is_localhost() { [[ "$1" == "::1" ]] || [[ "$1" == "127.0.0.1" ]] || [[ "$1" == "localhost" ]]; }

escape_markdown() { printf '%s' "$1" | sed 's/_/\\_/g; s/\*/\\*/g; s/\[/\\[/g; s/\]/\\]/g'; }

COUNTRY_CACHE_DIR=""
init_country_cache() { COUNTRY_CACHE_DIR="$1"; mkdir -p "$COUNTRY_CACHE_DIR"; }

is_valid_country() { [[ "$1" =~ ^[A-Z]{2}$ ]]; }

country_flag() {
    case "$1" in
        CN) echo "🇨🇳 CN" ;; RU) echo "🇷🇺 RU" ;; US) echo "🇺🇸 US" ;;
        DE) echo "🇩🇪 DE" ;; NL) echo "🇳🇱 NL" ;; FR) echo "🇫🇷 FR" ;;
        GB) echo "🇬🇧 GB" ;; BR) echo "🇧🇷 BR" ;; IN) echo "🇮🇳 IN" ;;
        KR) echo "🇰🇷 KR" ;; JP) echo "🇯🇵 JP" ;; VN) echo "🇻🇳 VN" ;;
        ID) echo "🇮🇩 ID" ;; TR) echo "🇹🇷 TR" ;; UA) echo "🇺🇦 UA" ;;
        HK) echo "🇭🇰 HK" ;; SG) echo "🇸🇬 SG" ;; TW) echo "🇹🇼 TW" ;;
        PL) echo "🇵🇱 PL" ;; IR) echo "🇮🇷 IR" ;; TH) echo "🇹🇭 TH" ;;
        AU) echo "🇦🇺 AU" ;; CA) echo "🇨🇦 CA" ;; IT) echo "🇮🇹 IT" ;;
        ES) echo "🇪🇸 ES" ;; RO) echo "🇷🇴 RO" ;; BG) echo "🇧🇬 BG" ;;
        PK) echo "🇵🇰 PK" ;; BD) echo "🇧🇩 BD" ;; MX) echo "🇲🇽 MX" ;;
        FI) echo "🇫🇮 FI" ;; SE) echo "🇸🇪 SE" ;; NO) echo "🇳🇴 NO" ;;
        *) echo "🌍 $1" ;;
    esac
}

get_country() {
    local ip="$1"
    if [ -z "$COUNTRY_CACHE_DIR" ]; then echo "Unknown"; return; fi
    local cache_file="${COUNTRY_CACHE_DIR}/country-${ip}"
    if is_localhost "$ip" || ! (validate_ipv4 "$ip" || validate_ipv6 "$ip"); then
        echo "Local"; return
    fi
    if [ -f "$cache_file" ]; then
        local cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        if [ "$cache_age" -lt 86400 ]; then cat "$cache_file"; return; fi
    fi
    local country=""
    country=$(curl -s --max-time 5 "https://ipapi.co/${ip}/country/" 2>/dev/null)
    is_valid_country "$country" || country=""
    if [ -z "$country" ]; then
        country=$(curl -s --max-time 5 "https://ip2c.org/${ip}" 2>/dev/null | cut -d';' -f2)
        is_valid_country "$country" || country=""
    fi
    if [ -z "$country" ]; then
        country=$(curl -s --max-time 5 "https://ipinfo.io/${ip}/country" 2>/dev/null | tr -d '\n')
        is_valid_country "$country" || country=""
    fi
    [ -z "$country" ] && country="??"
    local display; display="$(country_flag "$country")"
    echo "$display" > "$cache_file"
    echo "$display"
}

load_config() {
    if [ ! -f /etc/ssh-audit/.env ]; then return 1; fi
    local owner; owner=$(stat -c %u /etc/ssh-audit/.env 2>/dev/null)
    local mode; mode=$(stat -c %a /etc/ssh-audit/.env 2>/dev/null)
    if [ "$owner" != "0" ] || [ "${mode:2:1}" != "0" ]; then
        echo "ERROR: insecure .env" >&2; return 1
    fi
    BOT_TOKEN=$(grep '^BOT_TOKEN=' /etc/ssh-audit/.env | cut -d'"' -f2)
    CHAT_ID=$(grep '^CHAT_ID=' /etc/ssh-audit/.env | cut -d'"' -f2)
    HOSTNAME=$(grep '^HOSTNAME=' /etc/ssh-audit/.env | cut -d'"' -f2)
    NOTIFY_LANG=$(grep '^NOTIFY_LANG=' /etc/ssh-audit/.env | cut -d'"' -f2)
    LOG_FILE=$(grep '^LOG_FILE=' /etc/ssh-audit/.env | cut -d'"' -f2)
    STORAGE_DIR=$(grep '^STORAGE_DIR=' /etc/ssh-audit/.env | cut -d'"' -f2)
    CMD_FLUSH_INTERVAL=$(grep '^CMD_FLUSH_INTERVAL=' /etc/ssh-audit/.env | cut -d'"' -f2)
    [ -z "$NOTIFY_LANG" ] && NOTIFY_LANG="en"
    [ -z "$LOG_FILE" ] && LOG_FILE="/var/log/ssh-audit.log"
    [ -z "$STORAGE_DIR" ] && STORAGE_DIR="/var/lib/ssh-audit"
    [ -z "$CMD_FLUSH_INTERVAL" ] && CMD_FLUSH_INTERVAL=5
    init_country_cache "$STORAGE_DIR"
    return 0
}

send_telegram() {
    local message="$1"
    local bot_token="$2"
    local chat_id="$3"
    local log_file="$4"
    local text_escaped
    text_escaped=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local payload="{\"chat_id\":\"${chat_id}\",\"text\":\"${text_escaped}\",\"parse_mode\":\"Markdown\"}"
    curl -s --max-time 10 -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -H "Content-Type: application/json" -d "$payload" > /dev/null 2>&1
    local exit_code=$?
    echo "$(date): TG send - exit code ${exit_code}" >> "$log_file"
    return $exit_code
}
EOF
sudo chmod 644 "$AUDIT_LIB_DIR/common.sh"

# 6. Настройка auditd — правила перехвата execve
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[6/10] Настройка auditd..." || echo "[6/10] Configuring auditd...")${NC}"
sudo tee /etc/audit/rules.d/ssh-audit.rules > /dev/null << 'EOF'
# SSH Audit Monitor — перехват всех выполненных команд
-a always,exit -F arch=b64 -S execve -k ssh-commands
-a always,exit -F arch=b32 -S execve -k ssh-commands
EOF
sudo augenrules --load 2>/dev/null || sudo service auditd restart

# 7. Скрипт мониторинга входов (journalctl → Telegram)
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[7/10] Создание монитора входов..." || echo "[7/10] Creating login monitor...")${NC}"
sudo tee /usr/local/bin/ssh-login-monitor.sh > /dev/null << 'EOF'
#!/bin/bash
source /usr/local/lib/ssh-audit/common.sh
load_config

if systemctl list-units --type=service | grep -q "sshd.service"; then
    SSH_UNIT="sshd"
else
    SSH_UNIT="ssh"
fi

# Кеш геолокации по IP текущих сессий
declare -A SESSION_COUNTRY
declare -A SESSION_USER

while IFS= read -r line; do

    # Успешный вход
    if echo "$line" | grep -q "Accepted"; then
        user=$(echo "$line" | grep -oP 'for \K\S+')
        ip=$(echo "$line" | grep -oP 'from \K[0-9a-f:.]+')
        now=$(date '+%Y-%m-%d %H:%M:%S')
        country=$(get_country "$ip")
        escaped_country=$(escape_markdown "$country")
        escaped_user=$(escape_markdown "$user")
        SESSION_COUNTRY[$ip]="$country"
        SESSION_USER[$ip]="$user"
        if [ "$NOTIFY_LANG" = "ru" ]; then
            MSG=$(printf '🟢 *ВХОД НА СЕРВЕР* 🟢\n━━━━━━━━━━━━━━━━━━\n👤 *Пользователь:* %s\n🌍 *IP:* %s\n📍 *Страна:* %s\n⏰ *Время:* %s\n🖥️ *Сервер:* %s\n━━━━━━━━━━━━━━━━━━\n✅ Сессия открыта' \
                "$escaped_user" "$ip" "$escaped_country" "$now" "$HOSTNAME")
        else
            MSG=$(printf '🟢 *SERVER LOGIN* 🟢\n━━━━━━━━━━━━━━━━━━\n👤 *User:* %s\n🌍 *IP:* %s\n📍 *Country:* %s\n⏰ *Time:* %s\n🖥️ *Server:* %s\n━━━━━━━━━━━━━━━━━━\n✅ Session opened' \
                "$escaped_user" "$ip" "$escaped_country" "$now" "$HOSTNAME")
        fi
        send_telegram "$MSG" "$BOT_TOKEN" "$CHAT_ID" "$LOG_FILE"
        echo "$(date): LOGIN - $user from $ip ($country)" >> "$LOG_FILE"

    # Выход из сессии
    elif echo "$line" | grep -qE "Disconnected|session closed|session logout"; then
        user=$(echo "$line" | grep -oP '(for|user) \K\S+' | head -1)
        ip=$(echo "$line" | grep -oP 'from \K[0-9a-f:.]+')
        now=$(date '+%Y-%m-%d %H:%M:%S')
        country="${SESSION_COUNTRY[$ip]:-}"
        [ -z "$country" ] && country=$(get_country "$ip")
        escaped_country=$(escape_markdown "$country")
        escaped_user=$(escape_markdown "$user")
        if [ "$NOTIFY_LANG" = "ru" ]; then
            MSG=$(printf '🔴 *ВЫХОД С СЕРВЕРА* 🔴\n━━━━━━━━━━━━━━━━━━\n👤 *Пользователь:* %s\n🌍 *IP:* %s\n📍 *Страна:* %s\n⏰ *Время:* %s\n🖥️ *Сервер:* %s\n━━━━━━━━━━━━━━━━━━\n🚪 Сессия закрыта' \
                "$escaped_user" "$ip" "$escaped_country" "$now" "$HOSTNAME")
        else
            MSG=$(printf '🔴 *SERVER LOGOUT* 🔴\n━━━━━━━━━━━━━━━━━━\n👤 *User:* %s\n🌍 *IP:* %s\n📍 *Country:* %s\n⏰ *Time:* %s\n🖥️ *Server:* %s\n━━━━━━━━━━━━━━━━━━\n🚪 Session closed' \
                "$escaped_user" "$ip" "$escaped_country" "$now" "$HOSTNAME")
        fi
        send_telegram "$MSG" "$BOT_TOKEN" "$CHAT_ID" "$LOG_FILE"
        echo "$(date): LOGOUT - $user from $ip" >> "$LOG_FILE"
        unset "SESSION_COUNTRY[$ip]"
        unset "SESSION_USER[$ip]"
    fi

done < <(journalctl -f -n 0 -u "$SSH_UNIT" 2>/dev/null)
EOF
sudo chmod +x /usr/local/bin/ssh-login-monitor.sh

# 8. Скрипт мониторинга команд (ausearch → Telegram с буферизацией)
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[8/10] Создание монитора команд..." || echo "[8/10] Creating command monitor...")${NC}"
sudo tee /usr/local/bin/ssh-cmd-monitor.sh > /dev/null << 'EOF'
#!/bin/bash
source /usr/local/lib/ssh-audit/common.sh
load_config

mkdir -p "$STORAGE_DIR/cmd-queues"

# Получить IP сессии по PID через /proc
get_session_ip() {
    local pid="$1"
    # Пройти вверх по дереву процессов до sshd
    local check_pid="$pid"
    for _ in $(seq 1 10); do
        local ppid
        ppid=$(awk '/^PPid:/{print $2}' /proc/$check_pid/status 2>/dev/null) || break
        local comm
        comm=$(cat /proc/$check_pid/comm 2>/dev/null)
        if [[ "$comm" == "sshd" ]]; then
            # Найти IP в файловых дескрипторах sshd
            local ip
            ip=$(ss -tnp 2>/dev/null | grep "pid=$check_pid," | grep -oP '\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1)
            [ -n "$ip" ] && echo "$ip" && return
        fi
        check_pid="$ppid"
        [ "$check_pid" -le 1 ] && break
    done
    echo ""
}

# Флаг последней обработанной записи
LAST_TS_FILE="$STORAGE_DIR/last_audit_ts"
[ -f "$LAST_TS_FILE" ] || echo "0" > "$LAST_TS_FILE"

# Ассоциативные массивы: буфер команд и время последнего флуша на пользователя+ip
declare -A CMD_BUFFER       # ключ: "user|ip" → накопленные строки
declare -A LAST_FLUSH_TIME  # ключ: "user|ip" → timestamp последнего флуша
declare -A USER_COUNTRY     # кеш: ip → страна

flush_buffer() {
    local key="$1"
    local user="${key%%|*}"
    local ip="${key##*|}"
    local buf="${CMD_BUFFER[$key]:-}"
    [ -z "$buf" ] && return
    local now; now=$(date '+%Y-%m-%d %H:%M:%S')
    local country="${USER_COUNTRY[$ip]:-}"
    [ -z "$country" ] && country=$(get_country "$ip") && USER_COUNTRY[$ip]="$country"
    local escaped_country; escaped_country=$(escape_markdown "$country")
    local escaped_user; escaped_user=$(escape_markdown "$user")
    local escaped_ip; escaped_ip=$(escape_markdown "$ip")
    if [ "$NOTIFY_LANG" = "ru" ]; then
        MSG=$(printf '⌨️ *КОМАНДЫ — %s*\n━━━━━━━━━━━━━━━━━━\n%s\n━━━━━━━━━━━━━━━━━━\n👤 *Пользователь:* %s\n🌍 *IP:* %s\n📍 *Страна:* %s\n🖥️ *Сервер:* %s' \
            "$escaped_user" "$buf" "$escaped_user" "$escaped_ip" "$escaped_country" "$HOSTNAME")
    else
        MSG=$(printf '⌨️ *COMMANDS — %s*\n━━━━━━━━━━━━━━━━━━\n%s\n━━━━━━━━━━━━━━━━━━\n👤 *User:* %s\n🌍 *IP:* %s\n📍 *Country:* %s\n🖥️ *Server:* %s' \
            "$escaped_user" "$buf" "$escaped_user" "$escaped_ip" "$escaped_country" "$HOSTNAME")
    fi
    send_telegram "$MSG" "$BOT_TOKEN" "$CHAT_ID" "$LOG_FILE"
    echo "$(date): CMD FLUSH - $user@$ip ($(echo "$buf" | wc -l) cmds)" >> "$LOG_FILE"
    CMD_BUFFER[$key]=""
    LAST_FLUSH_TIME[$key]=$(date +%s)
}

# Основной цикл — читаем audit-лог в реальном времени
while true; do
    # Читать новые записи из audit-лога начиная с последней временной метки
    local_last_ts=$(cat "$LAST_TS_FILE" 2>/dev/null || echo "0")

    # ausearch по тегу ssh-commands, начиная со времени последней обработки
    while IFS= read -r audit_line; do
        # Пропускаем не-EXECVE строки
        echo "$audit_line" | grep -q 'type=EXECVE' || continue

        # Извлекаем timestamp
        ts=$(echo "$audit_line" | grep -oP 'msg=audit\(\K[0-9]+' || echo "0")

        # Обновляем последний timestamp
        if [ "$ts" -gt "$local_last_ts" ]; then
            echo "$ts" > "$LAST_TS_FILE"
            local_last_ts="$ts"
        fi

        # Извлекаем PID
        pid=$(echo "$audit_line" | grep -oP '\bpid=\K[0-9]+' | head -1)
        [ -z "$pid" ] && continue

        # Извлекаем команду (argc + a0, a1, a2...)
        argc=$(echo "$audit_line" | grep -oP 'argc=\K[0-9]+' || echo "0")
        cmd_parts=()
        for i in $(seq 0 $((argc - 1))); do
            part=$(echo "$audit_line" | grep -oP "a${i}=\"\K[^\"]+" || \
                   echo "$audit_line" | grep -oP "a${i}=\K[0-9A-F]+" | \
                   xargs -I{} python3 -c "print(bytes.fromhex('{}').decode('utf-8','replace'))" 2>/dev/null || echo "")
            [ -n "$part" ] && cmd_parts+=("$part")
        done
        [ ${#cmd_parts[@]} -eq 0 ] && continue
        cmd_str="${cmd_parts[*]}"

        # Получить пользователя
        uid=$(echo "$audit_line" | grep -oP '\buid=\K[0-9]+' | head -1)
        username=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
        [ -z "$username" ] && username="uid:${uid}"

        # Получить IP сессии
        session_ip=$(get_session_ip "$pid")
        [ -z "$session_ip" ] && session_ip="local"

        # Реальное время события
        event_time=$(date -d "@${ts}" '+%H:%M:%S' 2>/dev/null || date '+%H:%M:%S')

        # Ключ буфера
        buf_key="${username}|${session_ip}"

        # Добавить в буфер с реальным временем события
        line_entry="\`[${event_time}]\` ${cmd_str}"
        if [ -z "${CMD_BUFFER[$buf_key]:-}" ]; then
            CMD_BUFFER[$buf_key]="$line_entry"
        else
            CMD_BUFFER[$buf_key]="${CMD_BUFFER[$buf_key]}"$'\n'"$line_entry"
        fi

    done < <(ausearch -k ssh-commands --start recent -i 2>/dev/null | grep 'type=EXECVE')

    # Проверяем буферы на флуш (по времени)
    now_ts=$(date +%s)
    for key in "${!CMD_BUFFER[@]}"; do
        buf="${CMD_BUFFER[$key]:-}"
        [ -z "$buf" ] && continue
        last_flush="${LAST_FLUSH_TIME[$key]:-0}"
        elapsed=$((now_ts - last_flush))
        if [ "$elapsed" -ge "$CMD_FLUSH_INTERVAL" ]; then
            flush_buffer "$key"
        fi
    done

    sleep "$CMD_FLUSH_INTERVAL"
done
EOF
sudo chmod +x /usr/local/bin/ssh-cmd-monitor.sh

# 9. Systemd сервисы
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[9/10] Создание systemd сервисов..." || echo "[9/10] Creating systemd services...")${NC}"

# Сервис мониторинга входов
sudo tee /etc/systemd/system/ssh-login-monitor.service > /dev/null << 'EOF'
[Unit]
Description=SSH Login Monitor — Telegram notifications
After=network.target auditd.service
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/ssh-login-monitor.sh
Restart=on-failure
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Сервис мониторинга команд
sudo tee /etc/systemd/system/ssh-cmd-monitor.service > /dev/null << 'EOF'
[Unit]
Description=SSH Command Monitor — Telegram notifications
After=network.target auditd.service
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/ssh-cmd-monitor.sh
Restart=on-failure
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Health check таймер
sudo tee /usr/local/bin/ssh-audit-healthcheck.sh > /dev/null << 'EOF'
#!/bin/bash
source /usr/local/lib/ssh-audit/common.sh
load_config
RESTARTED=0
for svc in ssh-login-monitor ssh-cmd-monitor; do
    if ! systemctl is-active --quiet "$svc"; then
        systemctl restart "$svc"
        echo "$(date): Health check restarted $svc" >> "$LOG_FILE"
        RESTARTED=1
    fi
done
if [ "$RESTARTED" -eq 1 ]; then
    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "$NOTIFY_LANG" = "ru" ]; then
        MSG=$(printf '🔄 *Восстановление мониторинга* 🔄\n━━━━━━━━━━━━━━━━━━\n🖥️ *Сервер:* %s\n⏰ *Время:* %s\n📋 *Событие:* Сервис мониторинга перезапущен\n━━━━━━━━━━━━━━━━━━\n✅ *Система восстановлена*' "$HOSTNAME" "$NOW")
    else
        MSG=$(printf '🔄 *Monitor Restored* 🔄\n━━━━━━━━━━━━━━━━━━\n🖥️ *Server:* %s\n⏰ *Time:* %s\n📋 *Event:* Monitor service restarted\n━━━━━━━━━━━━━━━━━━\n✅ *System restored*' "$HOSTNAME" "$NOW")
    fi
    send_telegram "$MSG" "$BOT_TOKEN" "$CHAT_ID" "$LOG_FILE"
fi
EOF
sudo chmod +x /usr/local/bin/ssh-audit-healthcheck.sh

sudo tee /etc/systemd/system/ssh-audit-healthcheck.service > /dev/null << 'EOF'
[Unit]
Description=SSH Audit Monitor Health Check
[Service]
Type=oneshot
ExecStart=/usr/local/bin/ssh-audit-healthcheck.sh
User=root
NoNewPrivileges=true
EOF

sudo tee /etc/systemd/system/ssh-audit-healthcheck.timer > /dev/null << 'EOF'
[Unit]
Description=Health check timer for SSH Audit Monitor
[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF

# Logrotate
sudo tee /etc/logrotate.d/ssh-audit > /dev/null << 'EOF'
/var/log/ssh-audit.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
    create 644 root root
}
EOF

# Алиасы
if ! grep -q "# SSH-AUDIT ALIASES" ~/.bashrc; then
    cat >> ~/.bashrc << 'EOF'

# SSH-AUDIT ALIASES / АЛИАСЫ SSH-AUDIT
alias audit-login-status='systemctl status ssh-login-monitor --no-pager'
alias audit-cmd-status='systemctl status ssh-cmd-monitor --no-pager'
alias audit-log='sudo tail -50 /var/log/ssh-audit.log'
alias audit-sessions='sudo who'
# ======================================
EOF
    echo -e "${GREEN}${T_ALIASES_OK}${NC}"
fi

# Запуск
sudo systemctl daemon-reload
sudo systemctl enable ssh-login-monitor
sudo systemctl enable ssh-cmd-monitor
sudo systemctl enable ssh-audit-healthcheck.timer
sudo systemctl restart ssh-login-monitor
sudo systemctl restart ssh-cmd-monitor
sudo systemctl start ssh-audit-healthcheck.timer
sudo systemctl enable auditd
sudo systemctl restart auditd

# 10. Тестовое сообщение
echo -e "${GREEN}$([ "$LANG" = "ru" ] && echo "[10/10] Отправка тестового сообщения..." || echo "[10/10] Sending test message...")${NC}"
NOW=$(date '+%Y-%m-%d %H:%M:%S')
if [ "$LANG" = "ru" ]; then
TG_TEXT="✅ *SSH Audit Monitor v1 установлен!* ✅
━━━━━━━━━━━━━━━━━━
🖥️ *Сервер:* $(hostname)
⏰ *Время:* ${NOW}
⚙️ *Отслеживается:*
  • Успешные входы по SSH
  • Выходы из SSH сессий
  • Все команды всех пользователей
  • Пачка команд каждые ${CMD_FLUSH_INTERVAL} сек
━━━━━━━━━━━━━━━━━━
👁️ *Аудит активен!*"
else
TG_TEXT="✅ *SSH Audit Monitor v1 installed!* ✅
━━━━━━━━━━━━━━━━━━
🖥️ *Server:* $(hostname)
⏰ *Time:* ${NOW}
⚙️ *Tracking:*
  • Successful SSH logins
  • SSH session logouts
  • All commands from all users
  • Command batch every ${CMD_FLUSH_INTERVAL} sec
━━━━━━━━━━━━━━━━━━
👁️ *Audit is active!*"
fi
TG_TEXT_ESCAPED=$(printf '%s' "$TG_TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')
TG_PAYLOAD="{\"chat_id\":\"${CHAT_ID}\",\"text\":\"${TG_TEXT_ESCAPED}\",\"parse_mode\":\"Markdown\"}"
if curl -s --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$TG_PAYLOAD" > /dev/null 2>&1; then
    echo -e "${GREEN}${T_TG_OK}${NC}"
else
    echo -e "${RED}${T_TG_FAIL}${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ${T_DONE}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}${T_COMMANDS}${NC}"
if [ "$LANG" = "ru" ]; then
echo -e "  audit-login-status - статус монитора входов"
echo -e "  audit-cmd-status   - статус монитора команд"
echo -e "  audit-log          - последние 50 записей лога"
echo -e "  audit-sessions     - активные сессии"
else
echo -e "  audit-login-status - login monitor status"
echo -e "  audit-cmd-status   - command monitor status"
echo -e "  audit-log          - last 50 log entries"
echo -e "  audit-sessions     - active sessions"
fi
echo ""
