# Команды в рекомендациях

`arm_info` **никогда не выполняет команды из рекомендаций автоматически**. Они печатаются как проверяемый план действий администратора.

## Правила 1.2.4

1. Каждая команда выводится отдельно и получает пояснение в скобках: что именно она покажет или изменит.
2. Shell pipeline (`|`) остаётся одной физической командой и при копировании не разрывается.
3. Несколько независимых команд стандартного отчёта выводятся как `Команда 1`, `Команда 2` и т. д.
4. Маркеры `DOMAIN_FQDN`, `DC_FQDN`, `DC_IP`, `USER_NAME`, `PROFILE_NAME`, `CERT_PATH`, `QUEUE_NAME`, `JOB_ID`, `PARENT_PID`, `UNIT_NAME`, `DEVICE_PATH`, `MD_DEVICE`, `IFACE_NAME` нужно заменить фактическими значениями перед запуском.
5. Маркеры специально не используют `<...>`: символы `<`/`>` имеют специальное значение в shell и могут превратить случайно скопированную строку в redirection.
6. Команды, изменяющие состояние, помечаются `ИЗМЕНЯЕТ СОСТОЯНИЕ`. Сейчас это установка пакета, включение/разрешение CUPS-очереди и отмена задания. Их выполняют только после подтверждения причины.
7. Команды Kerberos/GVFS, зависящие от пользовательской session, должны выполняться в контексте затронутого пользователя; root-cache не эквивалентен cache интерактивного пользователя.
8. Необязательные утилиты (`chronyc`, `resolvectl`, `ethtool`, `nc`, `openssl`, `sssctl` и др.) могут отсутствовать. Это не повод автоматически устанавливать их; сначала оценивается необходимость и политика репозитория.

## Проверенные семейства команд

- systemd/journal: `systemctl status`, `systemctl --failed`, `journalctl -b`, `journalctl -k`, `journalctl --list-boots`;
- storage/FS: `smartctl -a/-A/--scan-open`, `findmnt`, `df`, `du`, `/proc/mdstat`, `mdadm --detail`;
- память/CPU: `free`, `vmstat`, `ps`, `top -b -n1`, `sensors`, EDAC sysfs;
- сеть/DNS: `ip`, `nmcli`, `resolvectl`/`systemd-resolve`, `dig`, `host`, `getent`, `nc` под `timeout`, `ethtool`;
- AD/SSSD/Kerberos: `realm list`, `sssctl domain-list/config-check`, `adcli testjoin --verbose`, `klist -l/-A`;
- 802.1X/X.509: `nmcli connection show PROFILE_NAME`, `openssl x509 ... -subject -issuer -dates`;
- CIFS/GVFS: `findmnt -t cifs`, автоматический обход локальных `TARGET` через `timeout 5 stat -f`, `loginctl`, `/run/user/*/gvfs`;
- CUPS: `lpstat`, `cupsctl`, `cupsenable`, `cupsaccept`, `cancel`;
- packages: `command -v`, `rpm -q`, `dnf provides`, `dnf install`.

## Важные ограничения

`openssl x509 -in CERT_PATH ...` по умолчанию ожидает PEM. Для DER-файла добавьте `-inform DER`; сам 802.1X-анализ `arm_info` пытается определить формат автоматически.

`klist -A` показывает коллекцию credentials **текущего пользователя**. Если диагностика запущена от root, билет рабочего пользователя проверяйте отдельно, например `sudo -u 'USER_NAME' klist -A`.

Для CIFS `SOURCE` и `TARGET` — разные сущности. `SOURCE` обычно выглядит как `//server/share` и не является локальным путём для `stat`. Рекомендация 1.2.4 сама получает локальные `TARGET` через `findmnt -n -l -t cifs -o TARGET` и по очереди проверяет каждый из них с таймаутом; вручную подставлять путь больше не требуется. В этой команде намеренно не используется `-r/--raw`: raw-режим `findmnt` hex-экранирует потенциально небезопасные символы, включая байты не-ASCII имён, и такой текст нельзя напрямую передавать в `stat` как фактический путь.

`mdadm --detail MD_DEVICE` требует реальное имя массива из `/proc/mdstat`; скрипт больше не предполагает, что это всегда `/dev/md0`.

`cupsenable`, `cupsaccept` и `cancel` меняют состояние CUPS. До их запуска сначала изучите `lpstat` и `journalctl -u cups`.
