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

Скрипт сохраняет совместимость с прежним сценарием: его содержимое можно целиком вставить в Bash после `su -`.

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
```

Примеры:

```bash
sudo arm_info --privacy
sudo arm_info --json --privacy --no-save | jq '.summary'
sudo arm_info --output /var/tmp/arm-reports/
sudo arm_info --config /etc/arm_info.conf
```

## Приватность

Обычный отчёт может содержать инфраструктурные данные. Перед публикацией используйте:

```bash
sudo arm_info --privacy
```

Privacy-режим скрывает hostname, MAC, DNS, SSSD-домены, маскирует IP и заменяет имена интерфейсов. Подробно: [docs/PRIVACY.md](docs/PRIVACY.md).

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

## Автоматизация

`--json` выдаёт машинно-читаемый JSON schema v1. Exit codes:

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

CI выполняет `bash -n`, ShellCheck уровня error и CLI/JSON/privacy tests.

## Документация

- [Использование](docs/USAGE.md)
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

Текущая версия: **1.1.0**.

## Лицензия

[MIT](LICENSE) © 2026 NewMishka.
