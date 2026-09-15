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

## Режим прямой вставки

`arm_info.sh` обёрнут в отдельную subshell. Поэтому его можно целиком вставить в root Bash-терминал. Перенаправление отчёта не останется активным после завершения.

## Отчёт

По умолчанию создаётся:

```text
ARM_INFO_<hostname>_YYYY-MM-DD_HH-MM-SS.txt
```

В `--privacy`:

```text
ARM_INFO_PRIVATE_YYYY-MM-DD_HH-MM-SS.txt
```

Для JSON расширение `.json`.

## Выбор места

```bash
sudo arm_info --output /var/tmp/
sudo arm_info --output /var/tmp/report.txt
```

Если каталог недоступен для записи, применяется `/tmp`.

## Без файла

```bash
sudo arm_info --no-save
```

## Только файл

```bash
sudo arm_info --quiet
```

## Публичный отчёт

```bash
sudo arm_info --privacy
```

Перед отправкой в Issue всё равно просмотрите отчёт: рекомендации могут содержать команды с локальными путями устройств/файловых систем.
