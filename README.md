🇷🇺 [Русский](#ru) · 🇬🇧 [English](#en)

---

<a name="ru"></a>

# Server Activity Telegram v1

## Что делает скрипт

Логирует все команды и SSH-входы на сервере и отправляет уведомления в Telegram — на русском или английском языке на ваш выбор.

**Логирование команд:** каждая команда записывается с временной меткой и именем пользователя. Раз в N минут (по умолчанию 10) скрипт отправляет сводку в Telegram — что делали, кто и когда.

**Уведомления о входах:** при каждом SSH-подключении в Telegram мгновенно приходит сообщение с именем пользователя, IP-адресом и геолокацией (страна, город, провайдер).

**Хранение логов:** файл `/var/log/commands.log` ротируется ежедневно, архивы хранятся 30 дней в сжатом виде.

---

## Установка

```bash
curl -O https://raw.githubusercontent.com/Oni-Wan-Shinobi/server-activity-telegram.sh/main/server-activity-telegram.sh
sudo bash server-activity-telegram.sh
```

---

Скрипт задаёт 3 вопроса:

**1. Язык интерфейса**
```
Select language / Выберите язык:
  1) English
  2) Русский
> 2
```

**2. Токен Telegram бота**
```
Введите токен Telegram бота (формат: 123456:ABC-DEF...):
> 123456789:AAF-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```
Получить у @BotFather командой /newbot. Скрипт автоматически проверяет валидность токена.

**3. Telegram Chat ID**
```
Введите ваш Telegram Chat ID:
> 123456789
```
Узнать свой Chat ID можно у @userinfobot — напишите ему любое сообщение, он ответит вашим ID.

**4. Интервал отчётов**
```
Интервал отправки команд в минутах (Enter - 10):
> (Enter)
```
Как часто присылать сводку команд в Telegram. По умолчанию 10 минут. Можно поставить 1–60.

После ответов на вопросы установка занимает около минуты и завершается тестовым сообщением в Telegram.

> ⚠️ После установки откройте **новую SSH сессию** — логирование команд активируется только в новых сессиях.

---

## Полезные команды после установки

```bash
activity-log                       # последние 50 команд из лога
activity-status                    # статус cron и auditd
cmdlog                             # команды из auditd (все пользователи)
tail -f /var/log/commands.log      # мониторинг в реальном времени
```

---

## Для кого и когда полезен

**Целевая аудитория:** владельцы VPS и выделенных серверов — разработчики, системные администраторы, небольшие команды.

**Когда ставить:**
- Нужна история команд на сервере без ручного просмотра логов
- Несколько человек имеют доступ к серверу и важно знать кто что делал
- Нужны мгновенные уведомления о каждом входе по SSH

---

## Плюсы

- **Нулевой порог входа** — один скрипт, 1 минута, только Ubuntu 22.04 без доп. зависимостей
- **Двойное логирование** — auditd на уровне ядра + HISTFILE через rsyslog для надёжности
- **Уведомления о входах в реальном времени** — IP, страна, город, провайдер
- **Геолокация без API-ключей** — бесплатный ip-api.com
- **Защита лога** — `chattr +a` защищает `/var/log/commands.log` от удаления
- **Ротация логов** — ежедневное сжатие, хранение 30 дней
- **Совместимость с fail2ban-telegram** — конфликтов нет, устанавливаются независимо

## Минусы

- **Только Debian-based системы** — Ubuntu 20.04/22.04/24.04, Debian 11/12. На CentOS, RHEL, Arch не работает без правок
- **Telegram как единственный канал** — если бот недоступен, уведомления не придут; логирование при этом работает
- **Логирование только в новых сессиях** — команды из сессий открытых до установки не пишутся

---

## Требования

- Ubuntu 20.04 / 22.04 / 24.04 LTS или Debian 11 / 12
- Root-доступ
- Telegram-бот (создать за 1 минуту у @BotFather)
- Ваш Telegram Chat ID (узнать у @userinfobot)

---

[▲ Наверх](#ru) · 🇬🇧 [English version](#en)

---
---

<a name="en"></a>

# Server Activity Telegram v1

## What the script does

Logs all commands and SSH logins on your server and sends notifications to Telegram — in English or Russian, your choice.

**Command logging:** every command is recorded with a timestamp and username. At a configurable interval (default 10 minutes) the script sends a summary to Telegram — who did what and when.

**Login notifications:** every SSH connection triggers an instant Telegram message with the username, IP address, and geolocation (country, city, ISP).

**Log retention:** `/var/log/commands.log` is rotated daily, archives are stored for 30 days in compressed form.

---

## Installation

```bash
curl -O https://raw.githubusercontent.com/Oni-Wan-Shinobi/server-activity-telegram.sh/main/server-activity-telegram.sh
sudo bash server-activity-telegram.sh
```

---

The script asks 4 questions:

**1. Interface language**
```
Select language / Выберите язык:
  1) English
  2) Русский
> 1
```

**2. Telegram bot token**
```
Enter Telegram bot token (format: 123456:ABC-DEF...):
> 123456789:AAF-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```
Get it from @BotFather with /newbot. The script validates the token automatically.

**3. Telegram Chat ID**
```
Enter your Telegram Chat ID:
> 123456789
```
Find your Chat ID via @userinfobot — send it any message and it will reply with your ID.

**4. Report interval**
```
Command report interval in minutes (Enter - 10):
> (Enter)
```
How often to send the command summary to Telegram. Default is 10 minutes. Can be set to 1–60.

After answering all questions, installation takes about a minute and ends with a test message in Telegram.

> ⚠️ After installation, open a **new SSH session** — command logging activates only in new sessions.

---

## Useful commands after installation

```bash
activity-log                       # last 50 commands from the log
activity-status                    # cron and auditd status
cmdlog                             # commands from auditd (all users)
tail -f /var/log/commands.log      # live monitoring
```

---

## Who it's for and when to use it

**Target audience:** VPS and dedicated server owners — developers, sysadmins, small teams.

**When to install:**
- You need a history of commands on the server without manually checking logs
- Multiple people have access to the server and you need to know who did what
- You want instant notifications for every SSH login

---

## Pros

- **Zero entry threshold** — one script, 1 minute, Ubuntu 22.04 only, no extra dependencies
- **Dual logging** — auditd at the kernel level + HISTFILE via rsyslog for reliability
- **Real-time login notifications** — IP, country, city, ISP
- **Geolocation without API keys** — free ip-api.com
- **Log protection** — `chattr +a` protects `/var/log/commands.log` from deletion
- **Log rotation** — daily compression, 30-day retention
- **Compatible with fail2ban-telegram** — no conflicts, installs independently

## Cons

- **Debian-based systems only** — Ubuntu 20.04/22.04/24.04, Debian 11/12. Doesn't work on CentOS, RHEL, or Arch without modifications
- **Telegram as the only channel** — if the bot is unavailable, notifications won't arrive; logging still works
- **Logging only in new sessions** — commands from sessions opened before installation are not logged

---

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04 LTS or Debian 11 / 12
- Root access
- A Telegram bot (create in 1 minute via @BotFather)
- Your Telegram Chat ID (get it from @userinfobot)

---

[▲ Top](#en) · 🇷🇺 [Русская версия](#ru)
