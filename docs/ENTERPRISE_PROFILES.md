# Enterprise profiles

Начиная с версии 1.2.0 `arm_info` поддерживает отдельные read-only профили для корпоративных рабочих станций РЕД ОС. Они не входят в аппаратный health score и предназначены для оперативной диагностики инфраструктурных проблем.

## Профили

### `domain`

Проверяет:

- определение домена через `realm`, `sssctl`, `sssd.conf` или FQDN;
- состояние `sssd`;
- `adcli testjoin` при наличии `adcli`;
- наличие действующего Kerberos ticket и число доступных credential cache;
- синхронизацию времени (`timedatectl`, дополнительно `chronyc`);
- наличие в журнале SSSD Kerberos error/code 6, 7 и 15 за текущую загрузку;
- DNS suffix/search;
- разрешение FQDN;
- `_ldap._tcp` и `_kerberos._tcp` SRV;
- доступность найденных контроллеров по TCP 88/389.

```bash
sudo arm_info --profile domain
sudo arm_info --profile domain --privacy --json -o /tmp/domain.json
```

### `network`

Проверяет:

- default gateway и активные IPv4-интерфейсы;
- источник DNS-конфигурации и upstream DNS;
- ситуацию с `127.0.0.53`, когда upstream DNS не определяется;
- FQDN и доменные SRV;
- активные NetworkManager 802.1X-профили;
- сроки доступных CA/client certificates 802.1X;
- CIFS mounts и зависшие/недоступные точки монтирования;
- GVFS mounts, `caja`, `gvfsd-smb` и `gvfsd-fuse`.

Проверка CIFS/GVFS использует короткий timeout, чтобы сама диагностика не зависла на недоступном ресурсе.

### `print`

Проверяет:

- состояние `cups.service` и CUPS scheduler;
- принтер по умолчанию;
- число очередей;
- paused/disabled/stopped queues;
- число текущих заданий;
- backend URI без раскрытия логина/пароля;
- warnings/errors CUPS за текущую загрузку.

```bash
sudo arm_info --profile print
```

### `software`

Инвентаризирует RPM-пакеты и процессы, относящиеся к типовым корпоративным компонентам: Firefox, Chromium, Remmina, FreeRDP, Citrix/ICAClient, R7, Basis Workplace, Crypto/Token middleware, SNX. Также проверяет zombie-процессы этих приложений.

Названия пакетов у разных поставщиков могут отличаться, поэтому эта проверка является инвентаризационной и не участвует в техническом индексе оборудования.

### `enterprise`

Последовательно запускает `domain + network + print + software`.

```bash
sudo arm_info --profile enterprise
sudo arm_info --profile enterprise --privacy --json -o arm-enterprise.json
```

## Privacy

Для отчётов, которые покидают внутренний контур, используйте `--privacy`. Профили скрывают доменное имя, hostname, MAC, адреса DNS и маскируют IP; printer URI всегда очищается от встроенных учётных данных.

## Exit codes

- `0` — проблем не обнаружено;
- `1` — есть предупреждения;
- `2` — есть критическое отклонение;
- `3` — часть проверки недоступна из-за отсутствующих утилит/данных, при этом критичных проблем нет;
- `64` — ошибка CLI.

## Сравнение двух АРМ

Снимите JSON на двух рабочих станциях:

```bash
sudo arm_info --profile enterprise --privacy --json -o arm-a.json
sudo arm_info --profile enterprise --privacy --json -o arm-b.json
```

Затем:

```bash
arm_info --compare arm-a.json arm-b.json
```

Или машинно-читаемо:

```bash
arm_info --compare arm-a.json arm-b.json --json
```

Сравнение умеет работать и с обычными JSON-отчётами `arm_info`: для enterprise schema сравниваются стабильные ключи checks, для остальных JSON выполняется рекурсивное сравнение с исключением очевидно изменчивых полей времени/отчёта.

Код `0` означает отсутствие отличий, код `1` — отличия найдены.

## Зависимости

Профили используют только уже установленные компоненты и не меняют конфигурацию. Максимальная полнота достигается при наличии `sssd-tools`, `adcli`, `krb5-workstation`, `bind-utils` (`dig`/`host`), `NetworkManager`, `openssl`, `cups-client`, `nc`/`nmap-ncat` и `python3` для `--compare`.

Отсутствующая утилита не делает базовый `arm_info` неработоспособным: соответствующая проверка получает состояние `N/A`/`unknown`.
