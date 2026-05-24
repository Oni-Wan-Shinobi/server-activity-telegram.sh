#!/bin/bash

# ============================================
# Server Activity Telegram v1 — установщик
# Логирование команд и входов с уведомлениями
# ============================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Server Activity Telegram v1${NC}"
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

# Строки интерфейса / UI strings
if [ "$LANG" = "ru" ]; then
    T_HEADER="Установка системы мониторинга активности v1"
    T_ENTER_TOKEN="Введите токен Telegram бота (формат: 123456:ABC-DEF...):"
    T_CHECKING_TOKEN="Проверка токена..."
    T_TOKEN_OK="✅ Токен валиден"
    T_TOKEN_BAD_FORMAT="Ошибка: неверный формат токена!"
    T_TOKEN_INVALID="Ошибка: токен недействителен!"
    T_ENTER_CHATID="Введите ваш Telegram Chat ID:"
    T_CHATID_BAD="Ошибка: Chat ID должен быть числом!"
    T_ENTER_INTERVAL="Интервал отправки команд в минутах (Enter - 10):"
    T_INTERVAL_BAD="Некорректное значение, используем 10"
    T_STARTING="Начинаю установку..."
    T_DONE="УСТАНОВКА ЗАВЕРШЕНА!"
    T_TG_OK="✅ Тестовое сообщение отправлено"
    T_TG_FAIL="⚠️ Не удалось отправить тестовое сообщение. Проверьте токен и Chat ID."
    T_COMMANDS="Полезные команды:"
    T_STEP_PACKAGES="Установка пакетов..."
    T_STEP_CONFIG="Создание конфигурации..."
    T_STEP_AUDITD="Настройка auditd..."
    T_STEP_LOGGING="Настройка логирования команд..."
    T_STEP_LOGROTATE="Настройка logrotate..."
    T_STEP_CMDSCRIPT="Создание скрипта команд..."
    T_STEP_LOGINSCRIPT="Создание скрипта входов..."
    T_STEP_PAM="Настройка PAM..."
    T_STEP_CRON="Настройка cron..."
    T_STEP_TEST="Отправка тестового сообщения..."
    T_NEW_SESSION="⚠️  Откройте новую SSH сессию — логирование команд активируется в новых сессиях"
else
    T_HEADER="Server Activity Monitor Installer v1"
    T_ENTER_TOKEN="Enter Telegram bot token (format: 123456:ABC-DEF...):"
    T_CHECKING_TOKEN="Checking token..."
    T_TOKEN_OK="✅ Token is valid"
    T_TOKEN_BAD_FORMAT="Error: invalid token format!"
    T_TOKEN_INVALID="Error: token is invalid!"
    T_ENTER_CHATID="Enter your Telegram Chat ID:"
    T_CHATID_BAD="Error: Chat ID must be a number!"
    T_ENTER_INTERVAL="Command report interval in minutes (Enter - 10):"
    T_INTERVAL_BAD="Invalid value, using 10"
    T_STARTING="Starting installation..."
    T_DONE="INSTALLATION COMPLETE!"
    T_TG_OK="✅ Test message sent"
    T_TG_FAIL="⚠️ Could not send test message. Check token and Chat ID."
    T_COMMANDS="Useful commands:"
    T_STEP_PACKAGES="Installing packages..."
    T_STEP_CONFIG="Creating configuration..."
    T_STEP_AUDITD="Configuring auditd..."
    T_STEP_LOGGING="Configuring command logging..."
    T_STEP_LOGROTATE="Configuring logrotate..."
    T_STEP_CMDSCRIPT="Creating command reporter..."
    T_STEP_LOGINSCRIPT="Creating login notifier..."
    T_STEP_PAM="Configuring PAM..."
    T_STEP_CRON="Configuring cron..."
    T_STEP_TEST="Sending test message..."
    T_NEW_SESSION="⚠️  Open a new SSH session — command logging activates in new sessions"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ${T_HEADER}${NC}"
echo -e "${GREEN}========================================${NC}"

# Конфигурация путей
ENV_FILE="/etc/server-activity/.env"
CMDLOG_SCRIPT="/usr/local/bin/tg_cmdlog.sh"
LOGIN_SCRIPT="/usr/local/bin/tg_login.sh"
COMMANDS_LOG="/var/log/commands.log"

# Функции валидации
validate_bot_token() {
    [[ "$1" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]
}

# Ввод токена и Chat ID
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

# Интервал отправки
echo ""
echo -e "${BLUE}${T_ENTER_INTERVAL}${NC}"
read -r INTERVAL
if [ -z "$INTERVAL" ]; then
    INTERVAL=10
elif [[ ! "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
    echo -e "${YELLOW}${T_INTERVAL_BAD}${NC}"
    INTERVAL=10
fi

echo ""
echo -e "${YELLOW}${T_STARTING}${NC}"

# ── 1. Установка пакетов ──────────────────────────────────────────────────────
echo -e "${GREEN}[1/10] ${T_STEP_PACKAGES}${NC}"
apt-get update -qq
apt-get install -y auditd audispd-plugins curl python3 rsyslog > /dev/null 2>&1

# ── 2. Создание директорий и конфига ─────────────────────────────────────────
echo -e "${GREEN}[2/10] ${T_STEP_CONFIG}${NC}"
mkdir -p /etc/server-activity

cat > "$ENV_FILE" << EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
INTERVAL="$INTERVAL"
LANG="$LANG"
EOF
chmod 600 "$ENV_FILE"

# ── 3. Настройка auditd ───────────────────────────────────────────────────────
echo -e "${GREEN}[3/10] ${T_STEP_AUDITD}${NC}"
systemctl enable auditd --now > /dev/null 2>&1 || true

# Добавляем правила если их ещё нет
if ! auditctl -l 2>/dev/null | grep -q "execve"; then
    auditctl -a always,exit -F arch=b64 -S execve -k commands
    auditctl -a always,exit -F arch=b32 -S execve -k commands
fi

# Постоянные правила
cat > /etc/audit/rules.d/commands.rules << 'EOF'
-a always,exit -F arch=b64 -S execve -k commands
-a always,exit -F arch=b32 -S execve -k commands
EOF
service auditd restart > /dev/null 2>&1 || true

# ── 4. Настройка HISTFILE логирования ─────────────────────────────────────────
echo -e "${GREEN}[4/10] ${T_STEP_LOGGING}${NC}"
cat > /etc/profile.d/history_log.sh << 'EOF'
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL=""
shopt -s histappend
export PROMPT_COMMAND='history 1 | logger -p local6.info -t "CMD[$(whoami)@$(hostname)]"'
EOF
chmod +x /etc/profile.d/history_log.sh

# rsyslog
if ! grep -q "local6" /etc/rsyslog.d/commands.conf 2>/dev/null; then
    echo 'local6.* /var/log/commands.log' > /etc/rsyslog.d/commands.conf
fi
# Отключаем схлопывание повторяющихся строк / Disable repeated message reduction
sed -i 's/\$RepeatedMsgReduction on/$RepeatedMsgReduction off/' /etc/rsyslog.conf
if ! grep -q "RepeatedMsgReduction" /etc/rsyslog.conf; then
    echo '$RepeatedMsgReduction off' >> /etc/rsyslog.conf
fi
systemctl restart rsyslog > /dev/null 2>&1 || true

# Создаём лог если нет
if [ ! -f "$COMMANDS_LOG" ]; then
    touch "$COMMANDS_LOG"
    chown syslog:adm "$COMMANDS_LOG"
    chmod 0640 "$COMMANDS_LOG"
fi

# ── 5. Настройка logrotate ────────────────────────────────────────────────────
echo -e "${GREEN}[5/10] ${T_STEP_LOGROTATE}${NC}"
cat > /etc/logrotate.d/commands << 'EOF'
/var/log/commands.log {
    su root syslog
    rotate 30
    daily
    compress
    missingok
    notifempty
    create 0640 syslog adm
    dateext
    dateformat -%Y-%m-%d
    postrotate
        systemctl restart rsyslog
    endscript
}
EOF

# cron для ротации (снимает chattr перед ротацией)
cat > /etc/cron.daily/commands-rotate << 'EOF'
#!/bin/bash
chattr -a /var/log/commands.log 2>/dev/null || true
logrotate /etc/logrotate.d/commands
chattr +a /var/log/commands.log 2>/dev/null || true
EOF
chmod +x /etc/cron.daily/commands-rotate

# ── 6. Скрипт отправки команд в Telegram ─────────────────────────────────────
echo -e "${GREEN}[6/10] ${T_STEP_CMDSCRIPT}${NC}"
cat > "$CMDLOG_SCRIPT" << SCRIPT
#!/bin/bash
source /etc/server-activity/.env

SEP="──────────────────────"
SINCE=\$(date -d "\$INTERVAL minutes ago" +"%Y-%m-%d %H:%M:%S")

COMMANDS=\$(awk -v since="\$SINCE" '
/CMD\[/ {
    match(\$0, /([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})/, t)
    if (t[1] >= since) {
        match(\$0, /CMD\[([^@]+)/, u)
        match(\$0, /[0-9]+  [0-9-]+ [0-9:]+ (.+)$/, c)
        print t[1], u[1], c[1]
    }
}' /var/log/commands.log)

if [ -z "\$COMMANDS" ]; then
    exit 0
fi

send_message() {
    local text="\$1"
    curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \\
        -H "Content-Type: application/json" \\
        -d "\$(python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps({'chat_id': '\$CHAT_ID', 'text': text}))
" <<< "\$text")" > /dev/null
    sleep 3
}

if [ "\$LANG" = "ru" ]; then
    HEADER="\$(printf '🖥 %s — команды за последние %s мин\n🕰 %s\n%s' "\$(hostname)" "\$INTERVAL" "\$(date '+%Y-%m-%d %H:%M:%S')" "\$SEP")"
else
    HEADER="\$(printf '🖥 %s — commands last %s min\n🕰 %s\n%s' "\$(hostname)" "\$INTERVAL" "\$(date '+%Y-%m-%d %H:%M:%S')" "\$SEP")"
fi

CHUNK=""
while IFS= read -r line; do
    TIME=\$(echo "\$line" | awk '{print \$1, \$2}')
    USER=\$(echo "\$line" | awk '{print \$3}')
    CMD=\$(echo "\$line" | awk '{\$1=\$2=\$3=""; print substr(\$0,4)}')

    if [ "\$USER" = "root" ]; then
        USER_LINE="👑 root"
    else
        USER_LINE="👤 \$USER"
    fi

    ENTRY="\$(printf '🕐 %s\n%s\n💻 %s\n%s' "\$TIME" "\$USER_LINE" "\$CMD" "\$SEP")"

    if [ \$(( \${#CHUNK} + \${#ENTRY} + 50 )) -gt 3800 ]; then
        send_message "\$(printf '%s\n\n%s' "\$HEADER" "\$CHUNK")"
        CHUNK=""
    fi
    CHUNK="\$(printf '%s\n%s\n' "\$CHUNK" "\$ENTRY")"
done <<< "\$COMMANDS"

if [ -n "\$CHUNK" ]; then
    send_message "\$(printf '%s\n\n%s' "\$HEADER" "\$CHUNK")"
fi
SCRIPT
chmod +x "$CMDLOG_SCRIPT"

# ── 7. Скрипт уведомлений о входах ───────────────────────────────────────────
echo -e "${GREEN}[7/10] ${T_STEP_LOGINSCRIPT}${NC}"
cat > "$LOGIN_SCRIPT" << SCRIPT
#!/bin/bash
source /etc/server-activity/.env

USER_LOGIN="\$PAM_USER"
IP="\$PAM_RHOST"
TYPE="\$PAM_TYPE"

if [ "\$TYPE" != "open_session" ]; then
    exit 0
fi

if [ -n "\$IP" ] && [ "\$IP" != "localhost" ] && [ "\$IP" != "127.0.0.1" ]; then
    GEO=\$(curl -s --max-time 5 "http://ip-api.com/json/\$IP?fields=country,city,isp")
    COUNTRY=\$(echo \$GEO | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('country','?'))" 2>/dev/null || echo "?")
    CITY=\$(echo \$GEO | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('city','?'))" 2>/dev/null || echo "?")
    ISP=\$(echo \$GEO | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('isp','?'))" 2>/dev/null || echo "?")
    GEO_LINE="🌍 \$COUNTRY, \$CITY
🌐 \$ISP"
else
    IP="\$([ "\$LANG" = "ru" ] && echo "локальный" || echo "local")"
    GEO_LINE="\$([ "\$LANG" = "ru" ] && echo "🌍 локальное подключение" || echo "🌍 local connection")"
fi

if [ "\$LANG" = "ru" ]; then
    MESSAGE="🚨🔴 ВХОД НА СЕРВЕР 🔴🚨
──────────────────────
👤 Пользователь: \$USER_LOGIN
🖥 Сервер: \$(hostname)
📅 Время: \$(date '+%Y-%m-%d %H:%M:%S')
🔑 IP: \$IP
\$GEO_LINE
──────────────────────"
else
    MESSAGE="🚨🔴 SERVER LOGIN 🔴🚨
──────────────────────
👤 User: \$USER_LOGIN
🖥 Server: \$(hostname)
📅 Time: \$(date '+%Y-%m-%d %H:%M:%S')
🔑 IP: \$IP
\$GEO_LINE
──────────────────────"
fi

curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \\
    -H "Content-Type: application/json" \\
    -d "\$(python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps({'chat_id': '\$CHAT_ID', 'text': text}))
" <<< "\$MESSAGE")" > /dev/null
SCRIPT
chmod +x "$LOGIN_SCRIPT"

# ── 8. PAM — уведомления о входах ────────────────────────────────────────────
echo -e "${GREEN}[8/10] ${T_STEP_PAM}${NC}"
PAM_LINE="session optional pam_exec.so /usr/local/bin/tg_login.sh"
if ! grep -qF "$PAM_LINE" /etc/pam.d/sshd; then
    echo "$PAM_LINE" >> /etc/pam.d/sshd
fi

# ── 9. Cron для отправки команд ───────────────────────────────────────────────
echo -e "${GREEN}[9/10] ${T_STEP_CRON}${NC}"
# Удаляем старую запись если есть
crontab -l 2>/dev/null | grep -v "tg_cmdlog" | crontab - 2>/dev/null || true
# Добавляем новую
(crontab -l 2>/dev/null; echo "*/${INTERVAL} * * * * ${CMDLOG_SCRIPT}") | crontab -

# Защита лога от удаления
chattr +a "$COMMANDS_LOG" 2>/dev/null || true

# ── 10. Тестовое сообщение ────────────────────────────────────────────────────
echo -e "${GREEN}[10/10] ${T_STEP_TEST}${NC}"

if [ "$LANG" = "ru" ]; then
TG_TEXT="✅ Server Activity Telegram v1 установлен!
──────────────────────
🖥 Сервер: $(hostname)
⏱ Интервал отчётов: ${INTERVAL} мин
──────────────────────
📋 Что логируется:
  • Все команды с именем пользователя
  • Входы по SSH с геолокацией IP
──────────────────────
🛡 Мониторинг активен!"
else
TG_TEXT="✅ Server Activity Telegram v1 installed!
──────────────────────
🖥 Server: $(hostname)
⏱ Report interval: ${INTERVAL} min
──────────────────────
📋 What is logged:
  • All commands with username
  • SSH logins with IP geolocation
──────────────────────
🛡 Monitoring is active!"
fi

TG_TEXT_ESCAPED=$(printf '%s' "$TG_TEXT" | python3 -c "import json,sys; print(json.dumps({'chat_id':'${CHAT_ID}','text':sys.stdin.read()}))")
if curl -s --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$TG_TEXT_ESCAPED" | grep -q '"ok":true'; then
    echo -e "${GREEN}${T_TG_OK}${NC}"
else
    echo -e "${YELLOW}${T_TG_FAIL}${NC}"
fi

# Алиасы
if ! grep -q "# SERVER-ACTIVITY ALIASES" ~/.bashrc; then
    cat >> ~/.bashrc << 'EOF'

# SERVER-ACTIVITY ALIASES
alias activity-log='tail -50 /var/log/commands.log'
alias activity-status='crontab -l | grep tg_cmdlog && echo "✅ cron active" && systemctl is-active auditd && echo "✅ auditd active"'
alias cmdlog='/usr/local/bin/cmdlog 2>/dev/null || ausearch -k commands -i | grep "type=SYSCALL" | tail -50'
# ======================================
EOF
fi

# ── Итог ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ${T_DONE}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}${T_NEW_SESSION}${NC}"
echo ""
echo -e "${GREEN}${T_COMMANDS}${NC}"
if [ "$LANG" = "ru" ]; then
echo -e "  cmdlog              - команды из auditd (все пользователи)"
echo -e "  activity-log        - читаемый лог команд с аргументами"
echo -e "  tail -f /var/log/commands.log  - мониторинг в реальном времени"
echo -e "  activity-status     - статус мониторинга"
else
echo -e "  cmdlog              - commands from auditd (all users)"
echo -e "  activity-log        - readable command log with arguments"
echo -e "  tail -f /var/log/commands.log  - live monitoring"
echo -e "  activity-status     - monitoring status"
fi
echo ""
