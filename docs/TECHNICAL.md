# Техническая архитектура

`arm_info` остаётся single-file Bash-утилитой, чтобы сохранять сценарий «SSH → su - → вставить скрипт целиком». Внешние документы и packaging не требуются для самого запуска.

## Источники данных

- `/etc/os-release`, `uname`, `lscpu`, `/proc/cpuinfo`;
- `/proc/meminfo`, `free`, `dmidecode`;
- `/sys/class/net`, `ip`, `resolvectl`/`nmcli`;
- `findmnt`, `df`;
- `systemctl`, `journalctl`;
- `lsblk`, `smartctl`;
- thermal hwmon и `sensors`;
- `/proc/mdstat`, `/sys/devices/system/edac`, `/sys/class/power_supply`;
- `timedatectl`/`chronyc`, `sssctl`, `klist`, `lpstat`.

## Принципы

1. Read-only диагностика: утилита не исправляет систему автоматически.
2. Неизвестный показатель не считается исправным автоматически.
3. Метрики нормализуются там, где абсолютные счётчики вводят в заблуждение (network ppm).
4. Рекомендации объясняют влияние и дают команду для дальнейшей проверки.
5. Privacy применяется к пользовательскому выводу и имени отчёта.
6. Конфигурация парсится whitelist-механизмом, без `source`.

## JSON

Schema version хранится в поле `schema_version`. При несовместимом изменении структуры номер должен быть увеличен.

## Ограничения

Vendor-specific SMART не стандартизирован. Температура зависит от драйверов. Power-On Hours не равен календарному возрасту. Отсутствие Kerberos-билета в root-контексте не говорит о пользовательской сессии. Software RAID проверяется только для Linux md.
