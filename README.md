# arm_info

[![CI](https://github.com/NewMishka/arm_info/actions/workflows/ci.yml/badge.svg)](https://github.com/NewMishka/arm_info/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/NewMishka/arm_info)](https://github.com/NewMishka/arm_info/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Shell](https://img.shields.io/github/languages/top/NewMishka/arm_info)

**Single-file Bash-диагностика рабочих станций РЕД ОС 7/8 и совместимых Linux-систем.**

`arm_info` собирает аппаратные и системные показатели, проверяет корпоративные сервисы и формирует объяснимый TXT/JSON-отчёт с рекомендациями в формате **«что обнаружено → влияние → действие → команда»**.

[Документация](https://newmishka.gitbook.io/newmishka-docs/) ·
[Последний релиз](https://github.com/NewMishka/arm_info/releases/latest) ·
[Пример отчёта](examples/sample-report.txt) ·
[Changelog](CHANGELOG.md)

> **Stable:** последний опубликованный релиз — **v1.3.0**.  
> Ветка `main` может содержать уже проверенные, но ещё не выпущенные изменения.

## Зачем arm_info

Проект рассчитан на практическую диагностику АРМ без развёртывания отдельного агента: достаточно передать **один `arm_info.sh`**, запустить его и получить читаемый отчёт.

Основные сценарии:

- диагностика ОС, CPU, RAM, накопителей, SMART, файловых систем и стабильности системы;
- проверка сети, DNS, интерфейсов и сетевых ошибок;
- корпоративные профили AD/SSSD/Kerberos, 802.1X, CIFS/GVFS/autofs, CUPS и mail;
- сравнение двух обезличенных JSON-отчётов;
- автоматизация через стабильные exit codes и machine-readable JSON;
- privacy-режим для передачи отчёта вне внутреннего контура.

Индекс отражает **текущее техническое состояние и эксплуатационные риски**, а не прогноз остаточного срока службы компьютера.

## Быстрый запуск

Клонировать репозиторий:

```bash
git clone https://github.com/NewMishka/arm_info.git
cd arm_info
sudo bash arm_info.sh
```

Или установить команду `arm_info`:

```bash
sudo bash install.sh
sudo arm_info
```

Для разовой диагностики проблемного АРМ достаточно передать один файл:

```bash
scp arm_info.sh admin@HOST:/tmp/
ssh admin@HOST
sudo bash /tmp/arm_info.sh -c
```

`-c` — короткая форма корпоративного профиля `--corp`.

## Что проверяется

| Область | Примеры |
|---|---|
| Система | ОС, ядро, архитектура, модель, BIOS, uptime |
| CPU | модель, ядра/потоки, load, температура |
| RAM | объём, доступность, модули, swap, OOM |
| Накопители | HDD/SSD/NVMe, SMART, ресурс, температура, Power-On Hours |
| Файловые системы | заполнение, inode, read-only |
| Стабильность | failed units, journal, kernel errors, OOM, time sync, ECC/EDAC |
| Сеть | IP/MAC, gateway, DNS, link, errors/drops |
| Домен | AD join, SSSD, Kerberos, KDC/LDAP, DNS SRV |
| Ресурсы | CIFS, GVFS/GIO, autofs |
| Печать | CUPS, очереди, jobs, backend, журнал |
| Почта | DNS, TCP, TLS/STARTTLS, сертификаты, pre-auth capabilities |

Корпоративные проверки **не смешиваются с базовым health score** и используют собственные статусы `OK/INFO/WARN/CRIT/N/A`.

## Основные команды

```bash
# Стандартная диагностика
sudo arm_info

# Корпоративный профиль
sudo arm_info -c

# Обезличенный корпоративный отчёт
sudo arm_info -c -p

# JSON с сохранением
sudo arm_info -c -p --json --save -o /tmp/arm-corp.json

# Увеличенный бюджет сетевых проверок
sudo arm_info -c -p --network-budget 60 --network-jobs 6

# Полная инвентаризация RPM
sudo arm_info --profile software

# Сравнение двух АРМ
arm_info --compare arm-a.json arm-b.json
```

Ключевые параметры:

```text
-h, --help
-V, --version
-p, --privacy
-s, --save
-o, --output PATH
-q, --quiet
--json
--config PATH
-c, --corp
--probe-autofs
--network-budget SEC
--network-jobs N
--mail-endpoint URI
--mail-domain DOMAIN
--profile domain|network|print|mail|software|enterprise
--compare REPORT_A.json REPORT_B.json
```

Полное описание CLI и сценариев: [GitBook](https://newmishka.gitbook.io/newmishka-docs/) и [docs/USAGE.md](docs/USAGE.md).

## Privacy и безопасность

Обычный отчёт может содержать инфраструктурные данные. Перед публикацией используйте:

```bash
sudo arm_info --privacy
sudo arm_info --corp --privacy --json
```

Privacy скрывает или маскирует штатные hostname, IP/MAC/DNS, домены, серверы, URI и связанные идентификаторы, но перед передачей отчёт всё равно следует просмотреть.

Диагностика по умолчанию **read-only**. Команды, меняющие состояние системы, не выполняются автоматически и в рекомендациях помечаются как `ИЗМЕНЯЕТ СОСТОЯНИЕ`.

Подробнее: [Privacy](docs/PRIVACY.md) · [Команды рекомендаций](docs/COMMANDS.md) · [Security policy](.github/SECURITY.md).

## Форматы и автоматизация

Стандартный `--json` использует schema v1. Корпоративные профили используют schema v2.

Exit codes:

| Код | Значение |
|---:|---|
| 0 | норма, проверка достаточно полная |
| 1 | предупреждения / неудовлетворительное состояние |
| 2 | критическое состояние |
| 3 | состояние нормальное, но проверка неполная |
| 64 | ошибка CLI |

Подробнее: [docs/AUTOMATION.md](docs/AUTOMATION.md).

## Зависимости

Базовые:

```text
bash
iproute
util-linux
procps-ng
coreutils
```

Для полной аппаратной диагностики на РЕД ОС рекомендуется:

```bash
sudo dnf install smartmontools dmidecode lm_sensors
```

Корпоративные профили дополнительно используют доступные в системе `sssd-tools`, `adcli`, `krb5-workstation`, `bind-utils`, `NetworkManager`, `openssl`, `cups-client`, `nc` / `nmap-ncat` и `python3`. Отсутствующая дополнительная утилита не должна превращать непроверенное состояние в ложный `OK`.

## Архитектура

Проект сохраняет single-file runtime-поставку, но внутри разделяет сбор фактов и их интерпретацию.

Базовый отчёт:

```text
collectors → normalized snapshot → checks/scoring → TXT/JSON
```

Корпоративная диагностика:

```text
collect → normalized inventory → probe → checks → output
```

Это позволяет отдельно тестировать сбор данных, scoring/status, privacy и renderers, не добавляя runtime-зависимостей.

Подробнее: [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Разработка и CI

```bash
make version
make check
make test
```

GitHub Actions проверяет Bash-синтаксис, ShellCheck, regression tests, архитектурные контракты, CLI/JSON/privacy, корпоративные профили, рекомендации, совместимость синтаксиса на Ubuntu/Fedora/Rocky Linux, installer и RPM smoke tests.

Автоматические тесты не заменяют полевой прогон на реальном РЕД ОС 7/8 для аппаратно-, доменно- и пользовательски-зависимых сценариев.

## Структура репозитория

```text
arm_info.sh        основной single-file runtime
install.sh         установка команды arm_info
config/            пример конфигурации
docs/              техническая и пользовательская документация
examples/          обезличенный пример отчёта
packaging/         RPM spec и helper сборки
tests/             regression / architecture / performance tests
.github/           CI, шаблоны Issues/PR и community-файлы
```

Навигация по документации: [docs/README.md](docs/README.md).

## Релизы

Текущий stable release: **v1.3.0**.

Текущая версия: **1.3.0**.

Release assets:

- `arm_info.sh`
- `SHA256SUMS`

После скачивания обоих файлов:

```bash
sha256sum -c SHA256SUMS
```

[Release notes 1.3.0](docs/releases/v1.3.0.md) ·
[Verification checklist](docs/releases/v1.3.0-checklist.md) ·
[Все релизы](https://github.com/NewMishka/arm_info/releases)

## Участие в проекте

Перед PR выполните `make check` и `make test`. Не публикуйте реальные внутренние hostname, домены, IP/MAC или необезличенные диагностические отчёты.

[Contributing](.github/CONTRIBUTING.md) ·
[Code of Conduct](.github/CODE_OF_CONDUCT.md) ·
[Security](.github/SECURITY.md)

## Лицензия

[MIT](LICENSE) © 2026 NewMishka.
