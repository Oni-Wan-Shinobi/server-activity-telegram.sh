#!/bin/bash
# ============================================================
# SSH Audit Monitor v2
# Уведомления в Telegram: входы + каждая команда
# Архитектура: journalctl -f (логины) + tail -f audit.log (команды)
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  SSH Audit Monitor v2${NC}"
echo -e "${GREEN}========================================${NC}"

# ── Выбор языка ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}Select language / Выберите язык:${NC}"
echo "  1) English"
echo "  2) Русский"
read -r LANG_CHOICE
LANG="en"
[[ "$LANG_CHOICE" == "2" ]] && LANG="ru"

# ── Токен и Chat ID ───────────────────────────────────────────────────────────
if [ "$LANG" = "ru" ]; then
    echo -e "${BLUE}Введите токен Telegram бота (формат: 123456:ABC-DEF...):${NC}"
else
    echo -e "${BLUE}Enter Telegram bot token (format: 123456:ABC-DEF...):${NC}"
fi
read -r BOT_TOKEN
if ! [[ "$BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}Ошибка: неверный формат токена / Invalid token format${NC}"; exit 1
fi

echo -e "${BLUE}Checking token...${NC}"
if ! curl -s --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" | grep -q '"ok":true'; then
    echo -e "${RED}Ошибка: токен недействителен / Token is invalid${NC}"; exit 1
fi
echo -e "${GREEN}✅ Token OK${NC}"

if [ "$LANG" = "ru" ]; then
    echo -e "${BLUE}Введите Telegram Chat ID:${NC}"
else
    echo -e "${BLUE}Enter Telegram Chat ID:${NC}"
fi
read -r CHAT_ID
if ! [[ "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
    echo -e "${RED}Ошибка: Chat ID должен быть числом / Chat ID must be a number${NC}"; exit 1
fi

# ── Конфигурация ──────────────────────────────────────────────────────────────
CONF_FILE="/etc/ssh-audit.conf"
LOG_DIR="/var/log/ssh-audit"
LOGIN_LOG="$LOG_DIR/logins.log"
CMD_LOG="$LOG_DIR/commands.log"
LIB_FILE="/usr/local/lib/ssh-audit-common.sh"
LOGIN_SCRIPT="/usr/local/bin/ssh-login-monitor.sh"
CMD_SCRIPT="/usr/local/bin/ssh-cmd-monitor.sh"
SERVER_NAME=$(hostname)

echo ""
echo -e "${YELLOW}$([ "$LANG" = "ru" ] && echo "Начинаю установку..." || echo "Starting installation...")${NC}"

# ── [1/7] Пакеты ──────────────────────────────────────────────────────────────
echo -e "${GREEN}[1/7] $([ "$LANG" = "ru" ] && echo "Установка пакетов..." || echo "Installing packages...")${NC}"
sudo apt-get update -qq
sudo apt-get install -y -q auditd curl

# ── [2/7] Директория логов ────────────────────────────────────────────────────
echo -e "${GREEN}[2/7] $([ "$LANG" = "ru" ] && echo "Создание директорий..." || echo "Creating directories...")${NC}"
sudo mkdir -p "$LOG_DIR"
sudo chmod 750 "$LOG_DIR"

# ── [3/7] Конфиг ──────────────────────────────────────────────────────────────
echo -e "${GREEN}[3/7] $([ "$LANG" = "ru" ] && echo "Сохранение конфигурации..." || echo "Saving configuration...")${NC}"
sudo tee "$CONF_FILE" > /dev/null << EOF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
SERVER_NAME="${SERVER_NAME}"
LANG="${LANG}"
LOGIN_LOG="${LOGIN_LOG}"
CMD_LOG="${CMD_LOG}"
EOF
sudo chmod 600 "$CONF_FILE"

# ── [4/7] Общая библиотека ────────────────────────────────────────────────────
echo -e "${GREEN}[4/7] $([ "$LANG" = "ru" ] && echo "Создание библиотеки..." || echo "Creating library...")${NC}"
sudo tee "$LIB_FILE" > /dev/null << 'EOF'
#!/bin/bash
# ssh-audit-common.sh — общие функции для мониторов

load_config() {
    [ -f /etc/ssh-audit.conf ] || { echo "ERROR: /etc/ssh-audit.conf not found" >&2; exit 1; }
    # shellcheck disable=SC1091
    source /etc/ssh-audit.conf
}

# Отправить сообщение в Telegram (Markdown)
tg_send() {
    local text="$1"
    # Экранируем спецсимволы Markdown
    local escaped
    escaped=$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g')
    curl -s --max-time 10 -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"${CHAT_ID}\",\"text\":\"${escaped}\",\"parse_mode\":\"Markdown\"}" \
        > /dev/null 2>&1
}

# Геолокация IP (с кешем на 24ч)
IP_CACHE_DIR="/tmp/ssh-audit-geo"
mkdir -p "$IP_CACHE_DIR"

get_geo() {
    local ip="$1"
    # Локальные адреса
    case "$ip" in
        127.*|::1|localhost) echo "local"; return ;;
    esac
    local cache="$IP_CACHE_DIR/$ip"
    # Кеш на 24 часа
    if [ -f "$cache" ]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
        [ "$age" -lt 86400 ] && { cat "$cache"; return; }
    fi
    # Запрашиваем страну
    local country=""
    country=$(curl -s --max-time 5 "https://ipapi.co/${ip}/country/" 2>/dev/null | tr -d '\n')
    [[ "$country" =~ ^[A-Z]{2}$ ]] || \
        country=$(curl -s --max-time 5 "https://ip2c.org/${ip}" 2>/dev/null | cut -d';' -f2)
    [[ "$country" =~ ^[A-Z]{2}$ ]] || country="??"
    echo "$country" | tee "$cache"
}

EOF
sudo chmod 644 "$LIB_FILE"

# ── [5/7] Правила auditd ──────────────────────────────────────────────────────
echo -e "${GREEN}[5/7] $([ "$LANG" = "ru" ] && echo "Настройка auditd..." || echo "Configuring auditd...")${NC}"
sudo tee /etc/audit/rules.d/ssh-audit.rules > /dev/null << 'EOF'
# SSH Audit Monitor v2
# Перехватываем execve от всех пользователей с login-сессией:
#   auid!=4294967295   — исключаем процессы БЕЗ login-сессии (systemd-демоны,
#                        cron, процессы запущенные до логина)
#   root по SSH имеет auid=0 — проходит фильтр, команды отправляются в Telegram
-a always,exit -F arch=b64 -S execve -F auid!=4294967295 -k user-cmds
-a always,exit -F arch=b32 -S execve -F auid!=4294967295 -k user-cmds
EOF
sudo augenrules --load 2>/dev/null || sudo systemctl restart auditd
sudo systemctl enable auditd
sudo systemctl restart auditd

# ── [6/7] Скрипты мониторов ───────────────────────────────────────────────────
echo -e "${GREEN}[6/7] $([ "$LANG" = "ru" ] && echo "Создание скриптов..." || echo "Creating monitor scripts...")${NC}"

# ── Монитор входов ────────────────────────────────────────────────────────────
# Читает journalctl -f, при Accepted/Disconnected → Telegram + лог
sudo tee "$LOGIN_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
source /usr/local/lib/ssh-audit-common.sh
load_config

# Определяем юнит SSH (sshd или ssh в зависимости от дистра)
if systemctl list-units --type=service 2>/dev/null | grep -q "sshd.service"; then
    SSH_UNIT="sshd"
else
    SSH_UNIT="ssh"
fi

# Кеш страны по IP в рамках сессии
declare -A GEO_CACHE

log_and_send() {
    local msg="$1"
    local log_line="$2"
    tg_send "$msg"
    echo "$log_line" | sudo tee -a "$LOGIN_LOG" > /dev/null
}

while IFS= read -r line; do

    NOW=$(date '+%Y-%m-%d %H:%M:%S')

    # ── Успешный вход ─────────────────────────────────────────────────────────
    if echo "$line" | grep -q "Accepted"; then
        USER=$(echo "$line" | grep -oP 'for \K\S+' || echo "unknown")
        IP=$(echo "$line" | grep -oP 'from \K(\d+\.\d+\.\d+\.\d+|[0-9a-f:]*:[0-9a-f:]+)' | head -1 || echo "N/A")
        GEO_CACHE[$IP]=$(get_geo "$IP")
        GEO="${GEO_CACHE[$IP]}"

        if [ "$LANG" = "ru" ]; then
            MSG=$(printf '🟢 *ВХОД НА СЕРВЕР*\n━━━━━━━━━━━━━━━━━━\n🖥️ *Сервер:* %s\n👤 *Пользователь:* %s\n🌍 *IP:* %s  📍 %s\n⏰ *Время:* %s' \
                "$SERVER_NAME" "$USER" "$IP" "$GEO" "$NOW")
        else
            MSG=$(printf '🟢 *SSH LOGIN*\n━━━━━━━━━━━━━━━━━━\n🖥️ *Server:* %s\n👤 *User:* %s\n🌍 *IP:* %s  📍 %s\n⏰ *Time:* %s' \
                "$SERVER_NAME" "$USER" "$IP" "$GEO" "$NOW")
        fi
        log_and_send "$MSG" "[$NOW] LOGIN  user=$USER ip=$IP geo=$GEO"

    # ── Выход ─────────────────────────────────────────────────────────────────
    elif echo "$line" | grep -qE "Disconnected|session closed|session logout"; then
        USER=$(echo "$line" | grep -oP '(for|user) \K\S+' | head -1 || echo "unknown")
        IP=$(echo "$line" | grep -oP 'from \K(\d+\.\d+\.\d+\.\d+|[0-9a-f:]*:[0-9a-f:]+)' | head -1 || echo "N/A")
        GEO="${GEO_CACHE[$IP]:-$(get_geo "$IP")}"

        if [ "$LANG" = "ru" ]; then
            MSG=$(printf '🔴 *ВЫХОД С СЕРВЕРА*\n━━━━━━━━━━━━━━━━━━\n🖥️ *Сервер:* %s\n👤 *Пользователь:* %s\n🌍 *IP:* %s  📍 %s\n⏰ *Время:* %s' \
                "$SERVER_NAME" "$USER" "$IP" "$GEO" "$NOW")
        else
            MSG=$(printf '🔴 *SSH LOGOUT*\n━━━━━━━━━━━━━━━━━━\n🖥️ *Server:* %s\n👤 *User:* %s\n🌍 *IP:* %s  📍 %s\n⏰ *Time:* %s' \
                "$SERVER_NAME" "$USER" "$IP" "$GEO" "$NOW")
        fi
        log_and_send "$MSG" "[$NOW] LOGOUT user=$USER ip=$IP"
        unset "GEO_CACHE[$IP]"
    fi

done < <(journalctl -f -n 0 -u "$SSH_UNIT" --since="now" 2>/dev/null)
EOF
sudo chmod +x "$LOGIN_SCRIPT"

# ── Монитор команд ────────────────────────────────────────────────────────────
# tail -f /var/log/audit/audit.log → парсим SYSCALL+EXECVE пары → Telegram + лог
#
# Как работает парсинг:
#   auditd пишет пару строк на каждое событие execve:
#     type=SYSCALL msg=audit(TS:EID): ... auid=1001 uid=1001 pid=12345 ...
#     type=EXECVE  msg=audit(TS:EID): argc=3 a0="ls" a1="-la" a2="/tmp"
#   Одинаковый EID (event id) связывает их.
#   Из SYSCALL берём auid (login uid) и pid.
#   Из EXECVE собираем команду.
#   auid встроен в фильтр auditd (>=1000, !=4294967295) — системные не приходят.
sudo tee "$CMD_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
source /usr/local/lib/ssh-audit-common.sh
load_config

AUDIT_LOG="/var/log/audit/audit.log"

# Получить IP SSH-сессии по PID: идём вверх по дереву до sshd,
# затем находим его сокет через ss
get_session_ip() {
    local pid="$1"
    local check="$pid"
    for _ in $(seq 1 15); do
        [ -z "$check" ] || [ "$check" -le 1 ] && break
        local comm
        comm=$(cat /proc/$check/comm 2>/dev/null || echo "")
        if [[ "$comm" == "sshd" ]]; then
            local ip
            ip=$(ss -tnp 2>/dev/null \
                | grep "pid=$check," \
                | grep -oP '\d+\.\d+\.\d+\.\d+' \
                | grep -v '^127\.' \
                | head -1)
            echo "${ip:-local}"
            return
        fi
        check=$(awk '/^PPid:/{print $2}' /proc/$check/status 2>/dev/null || echo "")
    done
    echo "local"
}

# Кеш страны и IP по auid
declare -A SESSION_IP    # auid → ip
declare -A SESSION_GEO   # ip   → geo

# В audit.log порядок: EXECVE идёт ПЕРЕД SYSCALL в одном событии.
# Запоминаем EXECVE, при SYSCALL с тем же EID — обрабатываем пару.
pending_eid=""
pending_cmdline=""
pending_ts=""

# Бесконечный перезапуск tail при ротации лога
while true; do
    while IFS= read -r line; do

        # ── EXECVE: запоминаем команду ────────────────────────────────────────
        if [[ "$line" == *"type=EXECVE"* ]]; then
            eid=$(echo "$line" | grep -oP 'msg=audit\([0-9]+:\K[0-9]+' || echo "")
            [ -z "$eid" ] && continue

            argc=$(echo "$line" | grep -oP 'argc=\K[0-9]+' || echo "0")
            cmd_parts=()
            for i in $(seq 0 $(( argc - 1 ))); do
                part=$(echo "$line" | grep -oP "(?<=a${i}=\")[^\"]+" 2>/dev/null || true)
                if [ -z "$part" ]; then
                    hex=$(echo "$line" | grep -oP "(?<= a${i}=)[0-9A-F]{2,}" 2>/dev/null || true)
                    [ -n "$hex" ] && part=$(python3 -c \
                        "print(bytes.fromhex('$hex').decode('utf-8','replace'))" 2>/dev/null || true)
                fi
                [ -n "$part" ] && cmd_parts+=("$part")
            done
            [ ${#cmd_parts[@]} -eq 0 ] && continue

            pending_eid="$eid"
            pending_cmdline="${cmd_parts[*]}"
            pending_ts=$(echo "$line" | grep -oP 'msg=audit\(\K[0-9]+' || echo "")
            continue
        fi

        # ── SYSCALL: получаем auid+pid, обрабатываем пару ────────────────────
        if [[ "$line" == *"type=SYSCALL"* ]]; then
            eid=$(echo "$line" | grep -oP 'msg=audit\([0-9]+:\K[0-9]+' || echo "")

            if [ -z "$pending_eid" ] || [ "$eid" != "$pending_eid" ]; then
                continue
            fi

            auid=$(echo "$line" | grep -oP '\bauid=\K[0-9]+' | head -1 || echo "")
            pid=$(echo "$line" | grep -oP '\bpid=\K[0-9]+' | head -1 || echo "")
            pending_eid=""

            if [[ -z "$auid" ]] || [[ "$auid" == "4294967295" ]]; then
                continue
            fi

            cmd_str="$pending_cmdline"
            ts_raw="$pending_ts"

            # Имя пользователя по auid
            username=$(getent passwd "$auid" 2>/dev/null | cut -d: -f1)
            [ -z "$username" ] && username="uid:$auid"

            # IP и гео (кешируем по auid)
            if [ -z "${SESSION_IP[$auid]:-}" ]; then
                SESSION_IP[$auid]=$(get_session_ip "$pid")
            fi
            ip="${SESSION_IP[$auid]}"

            if [ -z "${SESSION_GEO[$ip]:-}" ]; then
                SESSION_GEO[$ip]=$(get_geo "$ip")
            fi
            geo="${SESSION_GEO[$ip]}"

            NOW=$(date '+%Y-%m-%d %H:%M:%S')
            event_time=$([ -n "$ts_raw" ] && date -d "@$ts_raw" '+%H:%M:%S' 2>/dev/null || date '+%H:%M:%S')

            # Telegram
            if [ "$LANG" = "ru" ]; then
                MSG=$(printf '⌨️ *КОМАНДА*\n━━━━━━━━━━━━━━━━━━\n🖥️ *Сервер:* %s\n👤 *Пользователь:* %s\n🌍 *IP:* %s  📍 %s\n⏰ *Время:* %s\n\n`%s`' \
                    "$SERVER_NAME" "$username" "$ip" "$geo" "$event_time" "$cmd_str")
            else
                MSG=$(printf '⌨️ *COMMAND*\n━━━━━━━━━━━━━━━━━━\n🖥️ *Server:* %s\n👤 *User:* %s\n🌍 *IP:* %s  📍 %s\n⏰ *Time:* %s\n\n`%s`' \
                    "$SERVER_NAME" "$username" "$ip" "$geo" "$event_time" "$cmd_str")
            fi
            tg_send "$MSG"

            # Лог
            echo "[$NOW] CMD user=$username ip=$ip geo=$geo cmd=$cmd_str" \
                | sudo tee -a "$CMD_LOG" > /dev/null
        fi

    done < <(tail --follow=name --retry -n 0 "$AUDIT_LOG" 2>/dev/null)

    # tail завершился (ротация или ошибка) — пауза и рестарт
    sleep 2
done
EOF
sudo chmod +x "$CMD_SCRIPT"

# ── [7/7] Systemd сервисы + запуск ───────────────────────────────────────────
echo -e "${GREEN}[7/7] $([ "$LANG" = "ru" ] && echo "Создание сервисов..." || echo "Creating services...")${NC}"

sudo tee /etc/systemd/system/ssh-login-monitor.service > /dev/null << EOF
[Unit]
Description=SSH Login Monitor — Telegram notifications
After=network.target
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
ExecStart=${LOGIN_SCRIPT}
Restart=on-failure
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/ssh-cmd-monitor.service > /dev/null << EOF
[Unit]
Description=SSH Command Monitor — Telegram notifications
After=network.target auditd.service
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
ExecStart=${CMD_SCRIPT}
Restart=on-failure
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Logrotate
sudo tee /etc/logrotate.d/ssh-audit > /dev/null << EOF
${LOG_DIR}/*.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
    create 640 root root
}
EOF

sudo systemctl daemon-reload
sudo systemctl enable ssh-login-monitor ssh-cmd-monitor
sudo systemctl restart ssh-login-monitor ssh-cmd-monitor

sleep 2

# ── Алиасы ───────────────────────────────────────────────────────────────────
if ! grep -q "# SSH-AUDIT" ~/.bashrc; then
    cat >> ~/.bashrc << 'BASHEOF'

# SSH-AUDIT
alias audit-logins='sudo tail -50 /var/log/ssh-audit/logins.log'
alias audit-cmds='sudo tail -50 /var/log/ssh-audit/commands.log'
alias audit-status='systemctl status ssh-login-monitor ssh-cmd-monitor --no-pager'
BASHEOF
fi

# ── Тестовое сообщение ────────────────────────────────────────────────────────
NOW=$(date '+%Y-%m-%d %H:%M:%S')
if [ "$LANG" = "ru" ]; then
TG_TEXT="✅ *SSH Audit Monitor v2 установлен*
━━━━━━━━━━━━━━━━━━
🖥️ *Сервер:* ${SERVER_NAME}
⏰ *Время:* ${NOW}
📋 *Отслеживается:*
  • Входы и выходы по SSH
  • Каждая команда пользователей
━━━━━━━━━━━━━━━━━━
📁 *Логи:* /var/log/ssh-audit/"
else
TG_TEXT="✅ *SSH Audit Monitor v2 installed*
━━━━━━━━━━━━━━━━━━
🖥️ *Server:* ${SERVER_NAME}
⏰ *Time:* ${NOW}
📋 *Tracking:*
  • SSH logins and logouts
  • Every user command
━━━━━━━━━━━━━━━━━━
📁 *Logs:* /var/log/ssh-audit/"
fi

TG_ESC=$(printf '%s' "$TG_TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')
if curl -s --max-time 10 -X POST \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"${CHAT_ID}\",\"text\":\"${TG_ESC}\",\"parse_mode\":\"Markdown\"}" \
    > /dev/null 2>&1; then
    echo -e "${GREEN}✅ $([ "$LANG" = "ru" ] && echo "Тестовое сообщение отправлено" || echo "Test message sent")${NC}"
else
    echo -e "${RED}⚠️  $([ "$LANG" = "ru" ] && echo "Не удалось отправить тест. Проверь токен и Chat ID." || echo "Could not send test. Check token and Chat ID.")${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  $([ "$LANG" = "ru" ] && echo "УСТАНОВКА ЗАВЕРШЕНА" || echo "INSTALLATION COMPLETE")${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  ${BLUE}audit-status${NC}   — статус сервисов"
echo -e "  ${BLUE}audit-logins${NC}   — лог входов"
echo -e "  ${BLUE}audit-cmds${NC}     — лог команд"
echo ""
