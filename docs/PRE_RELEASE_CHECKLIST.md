# Pre-release checklist — arm_info 1.3.0

Чек-лист предназначен для проверки кандидата перед изменением версии и публикацией. Выполнение пунктов не создаёт tag/release автоматически. Пока проверка не завершена, `VERSION`, `ARM_INFO_VERSION` и RPM spec должны оставаться на опубликованной версии 1.2.4.

## Автоматические проверки

- [ ] `make version`, `make check` и `make test` проходят в чистом рабочем дереве.
- [ ] `bash -n` и ShellCheck `--severity=error` проходят для скрипта, installer, tests и RPM helper.
- [ ] `tests/test_stage1_performance.sh` подтверждает TXT-рендер без лишних subprocess и кэш NetworkManager.
- [ ] `tests/test_stage2_limits.sh` подтверждает общий бюджет, bounded timeout и предел параллельности DC.
- [ ] `tests/test_stage3_architecture.sh` подтверждает границы collectors/inventory/probes/checks, признаки configured/mounted/available и дедупликацию ресурсов.
- [ ] `tests/test_enterprise_discovery.sh` подтверждает все DC, GIO без FUSE, ошибки отдельных ресурсов, CUPS journal и privacy stderr.
- [ ] `tests/test_mail_profile.sh` подтверждает discovery, URI validation, DNS/TCP/TLS/STARTTLS, capabilities, privacy и бюджет без доступа к реальной почте.
- [ ] `tests/test_recommendation_commands.sh` подтверждает безопасные токены, описания команд и маркировку state-changing действий.
- [ ] `tests/test_cifs_probe.sh` подтверждает полный readdir + metadata lookup, UTF-8/пробелы и отсутствие metadata-only `stat -f`.
- [ ] `tests/test_sections.sh` подтверждает все пользовательские разделы TXT/JSON и профили `domain/network/print/mail/software/enterprise`.
- [ ] CI проходит на Ubuntu 24.04, Fedora и Rocky Linux 9; installer/RPM smoke tests успешны.

## CLI, версия и упаковка

- [ ] `bash arm_info.sh -c --help` содержит `-p`, выровненный `-s`, `--probe-autofs`, `--network-budget`, `--network-jobs`, `--mail-endpoint`, `--mail-domain`.
- [ ] Неверные значения лимитов и `-o` без `-s` завершаются кодом 64.
- [ ] Без `-s/--save` ни стандартный, ни корпоративный профиль не создаёт файл; privacy-имя не содержит hostname.
- [ ] В репозитории нет `arm_info-enterprise.sh`; распространяется один `arm_info.sh`.
- [ ] Перед выпуском, отдельным финальным коммитом: `VERSION`, `ARM_INFO_VERSION`, RPM spec, README и release notes переведены на 1.3.0; `make version` выводит 1.3.0.
- [ ] `docs/releases/v1.3.0.md` больше не помечен как черновик и содержит только подтверждённые заявления.
- [ ] Release workflow публикует `arm_info.sh` и `SHA256SUMS`; checksum проверен.
- [ ] Перед merge `main...feature` имеет `behind_by = 0`, полный PR CI — success.

## Полевой прогон на целевом РЕД ОС

### Общий контракт

- [ ] Выполнены стандартный TXT/JSON и `--privacy`; проверены score, полнота, SMART, температура, накопители и `Стабильность системы`.
- [ ] Выполнены `-c`, `-c -p`, `-c -p --json`, отдельные `domain/network/print/mail/software`.
- [ ] Проверены отсутствие зависания, читаемость таблиц, копирование длинных команд и сохранение только по `-s`.
- [ ] Privacy не раскрывает hostname, IP/MAC/DNS/domain, SMB/GVFS/GIO пути, mail server/domain/Subject/Issuer и credentials printer URI.

### DNS и контроллеры домена

- [ ] В enterprise присутствует ровно один раздел `DNS / DOMAIN`; network отдельно по-прежнему содержит DNS.
- [ ] Все уникальные DC из Kerberos/LDAP/AD DC SRV показаны, а не только первые три.
- [ ] Каждый DC имеет отдельные результаты TCP 88/389; отсутствие probe-инструмента или бюджета даёт N/A/UNKNOWN, а не ложный OK.
- [ ] Параллельный вывод сохраняет детерминированный порядок и общий итог `N из M`.

### SMB, autofs, GVFS и GIO

- [ ] На АРМ с несколькими ресурсами отображаются все: рабочие, недоступные и ещё не смонтированные настроенные.
- [ ] CIFS TARGET с пробелами/кириллицей не разбивается и не hex-экранируется; `sec=krb5,multiuser` проверяется в GUI-контексте.
- [ ] Подключение, видимое одновременно через GIO и FUSE, выводится один раз; GIO без FUSE всё равно обнаруживается.
- [ ] Подпапки внутри одной смонтированной шары не выводятся как самостоятельные SMB/GVFS-ресурсы.
- [ ] Обычный запуск читает статическую autofs-карту пассивно и не инициирует mount; несмонтированная запись имеет INFO.
- [ ] Отдельно, в согласованном тестовом окне, `--probe-autofs` различает доступный, недоступный и неподтверждённый CIFS-ресурс. Учтено, что чтение может вызвать автомонтирование.
- [ ] Ошибка одного ресурса не скрывает остальные и порождает адресную рекомендацию.

### CUPS

- [ ] Ноль реальных journal entries priority 0–4 даёт OK; одна и более — WARN; отказ доступа к journal — N/A.
- [ ] Отсутствующий default printer остаётся INFO.
- [ ] Рекомендации содержат read-only `lpstat -t`, `lpq -a -l`, `lpq -P QUEUE_NAME -l` и штатные действия `cancel -a QUEUE_NAME` / `cancel -a`.
- [ ] `cupsenable`, `cupsaccept`, `cancel`, `lpr`, restart помечены `ИЗМЕНЯЕТ СОСТОЯНИЕ`; `rm -rf /var/spool/cups/*` нигде не предлагается.

### Почта

- [x] На одном целевом АРМ пользователь подтвердил, что mail-профиль работает.
- [ ] На релизной выборке проверены auto-discovery из Thunderbird-совместимого `prefs.js` и явные `--mail-endpoint`/`--mail-domain`.
- [ ] Проверены хотя бы один implicit TLS endpoint и один STARTTLS endpoint; hostname, chain и срок сертификата интерпретируются корректно.
- [ ] Профиль не запрашивает пароль, не аутентифицируется, не меняет Kerberos cache, не открывает ящик и не отправляет письмо.
- [ ] URI с credentials отклоняется; недоступный endpoint остаётся в отчёте с рекомендацией.

### Бюджет и производительность

- [ ] `sudo bash arm_info.sh -c -p --network-budget 60` отражён в справке и завершается в разумное время на реальной инфраструктуре.
- [ ] При намеренно малом бюджете все обнаруженные DC/ресурсы/endpoints остаются видимыми, а непроверенные получают N/A.
- [ ] На типовом и насыщенном АРМ нет заметной регрессии полного времени относительно 1.2.4; замер и окружение записаны.

## Команды рекомендаций и совместимость

- [ ] Каждая команда имеет описание результата; shell pipeline остаётся одной физической строкой.
- [ ] Используются только актуальные безопасные токены: `DOMAIN_FQDN`, `DC_FQDN`, `DC_IP`, `USER_NAME`, `PROFILE_NAME`, `CERT_PATH`, `QUEUE_NAME`, `JOB_ID`, `PARENT_PID`, `UNIT_NAME`, `DEVICE_PATH`, `MD_DEVICE`, `IFACE_NAME`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_IP`, `MAIL_PROTOCOL`, `MAIL_DOMAIN`.
- [ ] Kerberos-команды учитывают user context; RAID не предполагает `/dev/md0`; OpenSSL учитывает PEM/DER.
- [ ] Изменяющие состояние команды не запускаются самим `arm_info` и выполняются вручную только после подтверждения причины.
- [ ] Если РЕД ОС 7 или 8 не проверена, эта ветка не описывается как подтверждённая runtime-совместимость.

## После одобрения кандидата

- [ ] Получено явное решение выпустить 1.3.0.
- [ ] Выполнен финальный version bump и повторён весь автоматический прогон.
- [ ] После merge подтверждены tag `v1.3.0`, GitHub Release, оба asset и `sha256sum -c SHA256SUMS`.
