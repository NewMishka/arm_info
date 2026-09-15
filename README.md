# arm_info

`arm_info` — Bash-утилита для комплексной диагностики технического состояния рабочих станций под управлением **РЕД ОС 7/8** и совместимых Linux-систем.

Утилита собирает аппаратные и системные показатели, оценивает состояние накопителей, файловых систем, памяти, CPU, сети и стабильности ОС, формирует объяснимый технический индекс и рекомендации в формате **«что обнаружено → влияние → действие → команда»**.

> Индекс отражает текущее техническое состояние и эксплуатационные риски. Он не является прогнозом остаточного срока службы компьютера.

## Возможности

- ОС, ядро, архитектура, модель системы, BIOS, uptime и ориентир возраста установки;
- CPU: модель, физические ядра/потоки, load, температура по нескольким замерам;
- ОЗУ: объём, доступность, модули, тип/частота, swap, OOM;
- сеть: IP/MAC, gateway, DNS, link, RX/TX errors и dropped, ppm;
- HDD/SSD/NVMe: SMART, ресурс, температура, Power-On Hours, bad/pending/uncorrectable, NVMe critical/media errors;
- файловые системы: заполнение, inode, read-only;
- systemd/journal: failed units, аппаратные/дисковые ошибки и уникальные error-сообщения;
- дополнительные read-only проверки: NTP/time sync, software RAID, ECC/EDAC, батарея, SMART self-test, SSSD/Kerberos/CUPS;
- enterprise-профили: AD/SSSD/Kerberos/DNS, 802.1X, CIFS/GVFS и CUPS;
- сравнение JSON-отчётов двух АРМ;
- TXT или JSON;
- privacy-режим для публикации отчётов;
- настраиваемые пороги через `/etc/arm_info.conf`;
- стабильные exit codes для автоматизации.

## Быстрый запуск

```bash
git clone https://github.com/NewMishka/arm_info.git
cd arm_info
sudo bash arm_info.sh
```

Или установка команды `arm_info`:

```bash
sudo bash install.sh
sudo arm_info
```

Скрипт сохраняет совместимость с прежним сценарием: его содержимое можно целиком вставить в Bash после `su -`. Enterprise-профили требуют установленного рядом helper `arm_info-enterprise.sh`, поэтому для них рекомендуется запуск из клонированного репозитория или после `install.sh`.

## CLI

```text
-h, --help
-V, --version
--privacy
--no-save
-o, --output PATH
-q, --quiet
--json
--config PATH
--profile domain|network|print|software|enterprise
--compare REPORT_A.json REPORT_B.json
```

Примеры:

```bash
sudo arm_info --privacy
sudo arm_info --json --privacy --no-save | jq '.summary'
sudo arm_info --output /var/tmp/arm-reports/
sudo arm_info --config /etc/arm_info.conf
sudo arm_info --profile domain --privacy
sudo arm_info --profile enterprise --privacy --json -o /tmp/arm-enterprise.json
arm_info --compare arm-a.json arm-b.json
```

## Enterprise-профили

`arm_info 1.2.0` добавляет отдельные профили для типовых проблем корпоративных АРМ РЕД ОС. Они **не смешиваются с аппаратным health score** и выводят самостоятельные статусы `OK/WARN/CRIT/N/A`.

- `domain` — SSSD, AD join, Kerberos ticket/cache, ошибки Kerberos в текущем журнале, time sync, DNS SRV и доступность KDC/LDAP;
- `network` — DNS/upstream, FQDN, интерфейсы, 802.1X и сроки сертификатов, CIFS/GVFS/Caja;
- `print` — CUPS service/scheduler, default printer, paused queues, jobs, backend URI и журнал;
- `software` — глобальная инвентаризация всех установленных RPM-пакетов, общее число процессов и zombie-процессы;
- `enterprise` — объединяет `domain + network + print`; глобальная инвентаризация ПО запускается отдельно через `--profile software`.

Подробно: [docs/ENTERPRISE_PROFILES.md](docs/ENTERPRISE_PROFILES.md).

## Сравнение двух АРМ

Для ситуации «на рабочем АРМ всё работает, на проблемном нет» можно получить два обезличенных JSON и сравнить их:

```bash
sudo arm_info --profile enterprise --privacy --json -o arm-a.json
sudo arm_info --profile enterprise --privacy --json -o arm-b.json
arm_info --compare arm-a.json arm-b.json
```

`--compare` возвращает `0`, если сравниваемые поля одинаковы, и `1`, если найдены отличия. Для сравнения требуется `python3`.

## Приватность

Обычный отчёт может содержать инфраструктурные данные. Перед публикацией используйте:

```bash
sudo arm_info --privacy
```

Privacy-режим скрывает hostname, MAC, DNS, SSSD-домены, маскирует IP и заменяет имена интерфейсов. В enterprise-профилях дополнительно скрываются доменные значения; printer URI всегда очищается от встроенных учётных данных. Подробно: [docs/PRIVACY.md](docs/PRIVACY.md).

## Технический индекс

| Группа | Вес |
|---|---:|
| Накопители / износ | 40% |
| Файловые системы | 15% |
| Стабильность ОС | 15% |
| Оперативная память | 10% |
| Процессор / температура | 10% |
| Возраст / наработка | 5% |
| Сеть | 5% |

Если группа не может быть достоверно проверена, неизвестное значение не превращается в `100/100`: уменьшается полнота диагностики, а недостоверная группа исключается из соответствующей части расчёта.

Подробно: [docs/SCORING.md](docs/SCORING.md).

## Зависимости

Базовые: `bash`, `iproute`, `util-linux`, `procps-ng`, `coreutils`.

Для полной диагностики на РЕД ОС рекомендуется:

```bash
sudo dnf install smartmontools dmidecode lm_sensors
```

Дополнительные проверки используют установленные в системе `chronyc`, `sssctl`, `klist`, `lpstat`, `mdadm` и EDAC-интерфейсы, но не требуют их установки для базового запуска.

Для максимальной полноты enterprise-профилей полезны `sssd-tools`, `adcli`, `krb5-workstation`, `bind-utils`, `NetworkManager`, `openssl`, `cups-client`, `nc`/`nmap-ncat`. `python3` нужен только для `--compare`.

## Автоматизация

Базовый `--json` выдаёт machine-readable JSON schema v1. Enterprise-профили используют schema v2 (`checks[]` со стабильными ключами). Exit codes:

- `0` — норма, проверка достаточно полная;
- `1` — предупреждения/неудовлетворительное состояние;
- `2` — критическое состояние;
- `3` — состояние нормальное, но проверка неполная;
- `64` — ошибка CLI.

Подробнее: [docs/AUTOMATION.md](docs/AUTOMATION.md).

## Конфигурация

Пример: [config/arm_info.conf.example](config/arm_info.conf.example). Установщик создаёт `/etc/arm_info.conf`, если его ещё нет. Конфигурация не выполняется через `source`: скрипт читает только разрешённый список ключей.

## RPM

В репозитории есть `packaging/arm_info.spec` и helper:

```bash
sudo dnf install rpm-build
bash packaging/build-rpm.sh
```

## Разработка

```bash
make check
make test
```

CI выполняет `bash -n`, ShellCheck уровня error, базовые CLI/JSON/privacy tests и тесты enterprise-профилей/compare.

## Документация

- [Использование](docs/USAGE.md)
- [Enterprise profiles](docs/ENTERPRISE_PROFILES.md)
- [Scoring](docs/SCORING.md)
- [Техническая архитектура](docs/TECHNICAL.md)
- [Privacy](docs/PRIVACY.md)
- [Автоматизация](docs/AUTOMATION.md)
- [Дополнительные проверки](docs/OPTIONAL_CHECKS.md)
- [Совместимость](docs/COMPATIBILITY.md)
- [Тестирование](docs/TESTING.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## Версия

Текущая версия: **1.2.0**.

## Лицензия

[MIT](LICENSE) © 2026 NewMishka.
