# Использование arm_info

## Запуск без установки

```bash
sudo bash arm_info.sh
```

Запуск через `sh` не рекомендуется: используются Bash-конструкции.

## Установка

```bash
sudo bash install.sh
sudo arm_info
```

Удаление бинарника:

```bash
sudo bash install.sh --uninstall
```

Конфигурация `/etc/arm_info.conf` при удалении сохраняется.

Начиная с `1.2.1` базовая и корпоративная диагностика находятся в одном `arm_info.sh`; отдельный enterprise-helper не нужен.

## Режим прямой вставки

`arm_info.sh` обёрнут в отдельную subshell. Поэтому его можно целиком вставить в root Bash-терминал. Перенаправление отчёта не останется активным после завершения.

## Стандартный отчёт

Обычный запуск по умолчанию создаёт:

```text
ARM_INFO_<hostname>_YYYY-MM-DD_HH-MM-SS.txt
```

В `--privacy`:

```text
ARM_INFO_PRIVATE_YYYY-MM-DD_HH-MM-SS.txt
```

Для JSON используется расширение `.json`.

## Корпоративный отчёт

Короткий корпоративный профиль:

```bash
sudo arm_info --corp
```

Он эквивалентен `--profile enterprise` и выполняет `domain + network + print`. Глобальная инвентаризация ПО в него не входит.

`--corp` и `--profile enterprise` в `1.2.2` также сохраняют отчёт по умолчанию. Имена формируются так:

```text
ARM_INFO_CORP_<hostname>_YYYYMMDD_HHMMSS.txt
ARM_INFO_CORP_PRIVATE_YYYYMMDD_HHMMSS.txt   # --privacy
```

Для корпоративного JSON расширение меняется на `.json`.

Отдельные профили `domain`, `network`, `print` и `software` без `-o/--output` выводятся в терминал; файл создаётся только при явном указании пути.

## Выбор места сохранения

Стандартный отчёт:

```bash
sudo arm_info --output /var/tmp/
sudo arm_info --output /var/tmp/report.txt
```

Корпоративный отчёт:

```bash
sudo arm_info --corp -o /var/tmp/
sudo arm_info --corp -o /var/tmp/arm-corp.txt
```

Если стандартный каталог недоступен для записи, стандартный анализ использует `/tmp`. Для явного `-o/--output` корпоративный профиль завершится ошибкой, если каталог недоступен.

## Без сохранения

```bash
sudo arm_info --no-save
sudo arm_info --corp --no-save
```

## Только файл

Опция `--quiet` относится к стандартному анализу:

```bash
sudo arm_info --quiet
```

Для корпоративного профиля используйте перенаправление shell либо `-o`; профиль всё равно печатает результат в терминал.

## JSON

Стандартная schema v1:

```bash
sudo arm_info --json --privacy --no-save
```

Корпоративная schema v2:

```bash
sudo arm_info --corp --privacy --json --no-save
sudo arm_info --corp --privacy --json -o /var/tmp/arm-corp.json
```

## Публичный отчёт

```bash
sudo arm_info --privacy
sudo arm_info --corp --privacy
```

Перед отправкой в публичный Issue всё равно просмотрите отчёт: рекомендации могут содержать локальные пути устройств, файловых систем и другие диагностические детали.
