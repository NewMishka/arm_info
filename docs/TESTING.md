# Тестирование

Перед отправкой PR:

```bash
make version
make check
make test
```

`make version` читает значение из `VERSION`; отдельной захардкоженной версии в `Makefile` нет.

## Что проверяют локальные тесты

`make check` сначала сверяет `VERSION` с `ARM_INFO_VERSION` в `arm_info.sh` и `Version:` в RPM spec, затем выполняет Bash syntax check для основного single-file скрипта, installer, CLI/корпоративных tests, recommendation-command test, полного теста разделов отчёта и RPM helper. При наличии ShellCheck запускается `shellcheck --severity=error`.

`make test` дополнительно запускает:

- `tests/test_stage1_performance.sh` — регрессии TXT-рендера и кэша NetworkManager;
- `tests/test_stage2_limits.sh` — единые тайм-ауты, общий сетевой бюджет и ограниченная параллельность DC;
- `tests/test_stage3_architecture.sh` — граница collectors/probes/emitters, единый снимок CIFS/autofs/GVFS/GIO, признаки configured/mounted/available, дедупликация, отдельные статусы и privacy;
- `tests/test_cli.sh` — версия, CLI, standard JSON schema v1, privacy и контракт стандартных рекомендаций;
- `tests/test_enterprise_discovery.sh` — поведенческие проверки production-функций: шесть уникальных DC из трёх SRV-источников, отсутствие TCP-инструментов, три GVFS-ресурса с одним неисправным, UTF-8/пробелы, privacy ошибок, запуск под владельцем и неполное перечисление; GIO без FUSE и удаление GIO/FUSE дублей; CUPS с нулём/двумя записями, служебными строками и ошибкой доступа к журналу; рекомендация cancel -a. Переключение к другому UID проверяется, если среда разрешает `runuser`; локальные каталоги не заменяют полевой тест FUSE/SMB на РЕД ОС.
- `tests/test_enterprise.sh` — корпоративный CLI, schema v2, privacy, `--compare`, single-file policy и контракт корпоративного отчёта;
- `tests/test_mail_profile.sh` — автообнаружение IMAP/SMTP из `prefs.js`, явные URI, DNS-кэш, оба порта, TLS/STARTTLS hostname verification, GSSAPI capability, истекающий сертификат, privacy и общий сетевой бюджет без подключения к реальной почте;
- `tests/test_recommendation_commands.sh` — статический аудит рекомендуемых команд: безопасные placeholder-токены, отсутствие известных некорректных форм, синтаксис representative commands и обязательная маркировка state-changing действий;
- `tests/test_sections.sh` — сквозной контроль всех пользовательских разделов стандартного TXT, всех основных групп standard JSON, всех секций профилей `domain/network/print/mail/software/enterprise`, корпоративного TXT и критичных helper-контрактов SMART/CPU/ФС/корпоративных проверок.
- `tests/test_cifs_probe.sh` — отдельная regression-проверка CIFS: TARGET читается одной колонкой без whitespace-splitting, UTF-8/пробелы сохраняются, а доступность проверяется фактическим чтением каталога вместо `stat -f`.

`tests/test_sections.sh` специально не ограничивается проверкой наличия функций в исходнике: он запускает отчёты и проверяет, что разделы действительно доходят до пользовательского TXT/JSON. Для аппаратно-зависимых ветвей, которые нельзя гарантированно воспроизвести на GitHub runner (SMART реального NVMe, датчики CPU и т. п.), дополнительно используются статические regression guards на путь сбора данных. Это не заменяет полевой тест РЕД ОС, но не позволяет незаметно удалить критичный helper, как произошло с `run_smart()` в pre-release 1.2.4.

## CI

CI проверяет:

- `bash -n` для shell-файлов;
- ShellCheck уровня `error`;
- базовые CLI/JSON/privacy tests;
- корпоративные profiles/compare/recommendations tests;
- recommendation-command audit tests;
- CIFS runtime-probe regression tests (UTF-8, пробелы, actual directory read);
- архитектурный контракт collectors → inventory → probes → checks и объединение разных способов монтирования;
- полный тест разделов отчёта `tests/test_sections.sh`;
- Bash syntax в Ubuntu 24.04, Fedora и Rocky Linux 9;
- согласованность версии `VERSION` / `arm_info.sh` / RPM spec / `make version` / README;
- smoke-test установки/удаления через `install.sh --destdir`;
- single-file policy: отсутствие отдельного enterprise-helper, отсутствие hard-coded списка корпоративного ПО и списка кодов Kerberos;
- контракт текстовых отчётов: медиана CPU, `Стабильность системы`, корпоративное сохранение, copy-safe команды, документация;
- RPM build smoke test и состав пакета.

Автоматический CI на Ubuntu/Fedora/Rocky проверяет синтаксис, тестовые контракты, установку и упаковку, но не является runtime-проверкой РЕД ОС.

## Аудит команд рекомендаций

Автоматический тест защищает найденные в ревизии ошибки: некорректные поля `nmcli`, FILE-cache-only Kerberos-проверку, hard-coded `/dev/md0`, shell placeholders вида `<DOMAIN>`, заведомо бесполезный `rpm -qf` для отсутствующего `lpstat` и физический разрыв команд. Representative команды дополнительно проверяются через `bash -n -c` после подстановки безопасных служебных маркеров.

Автотест не заменяет полевой запуск: команды, зависящие от конкретной инфраструктуры (`adcli`, DNS SRV, 802.1X, Kerberos user context, CUPS и CIFS), перед production release должны быть просмотрены на целевом РЕД ОС. State-changing команды не запускаются тестами автоматически.

## Полевой smoke-test РЕД ОС

РЕД ОС 7/8 остаётся основной целевой платформой. Для релизов рекомендуется проверять на доступных реальных АРМ минимум:

```bash
sudo bash arm_info.sh
sudo bash arm_info.sh --privacy
sudo bash arm_info.sh --json --privacy
sudo bash arm_info.sh --corp
sudo bash arm_info.sh --corp --privacy --json
sudo bash arm_info.sh --profile mail
sudo bash arm_info.sh --profile software
```

Проверяются не только exit code, но и отсутствие зависания, отсутствие файла при обычном запуске, сохранение только по `-s/--save`, читаемость таблиц/рекомендаций, privacy и валидность JSON. Наличие `smartmontools`, `dmidecode` и `lm_sensors` повышает полноту базовой диагностики.

## Полевые проверки 1.2.3

Перед release 1.2.3 отдельно проверялись:

- LVM/device-mapper root: физический root-диск должен отображаться как `Системный` без tree-префикса `lsblk`;
- тот же АРМ с USB-флешкой: USB должен быть `Съёмный (вне индекса)`, оптический привод — `Оптический (вне индекса)`; removable media не должны менять storage score/SMART completeness и `Макс. заполнение` внутренних ФС;
- `--profile network` и `--corp` на АРМ с 802.1X: должны отображаться настроенные профили, сертификат и даты начала/окончания, когда X.509 доступен как PEM/DER; fallback-кандидат не должен выдаваться за подтверждённый профиль;
- стандартный блок `Стабильность системы`: итоговый score и каждый штраф должны быть видны отдельно;
- длинная команда из рекомендаций должна копироваться как одна shell-строка, даже если терминал визуально переносит её.

Эти сценарии были подтверждены пользователем на целевом РЕД ОС перед выпуском 1.2.3: накопители и 802.1X отображаются корректно, обновлённый блок стабильности проверен, copy-safe вывод команд проверен.

## Полевые проверки кандидата 1.3

Автотесты не заменяют реальные DNS SRV, Kerberos multiuser CIFS, desktop D-Bus, autofs и CUPS journal. Перед выпуском 1.3.0 обязательны сценарии из [PRE_RELEASE_CHECKLIST.md](PRE_RELEASE_CHECKLIST.md), в том числе:

- один раздел `DNS / DOMAIN` в enterprise и полный список DC с TCP 88/389;
- несколько SMB-ресурсов разного происхождения, включая рабочий, недоступный и настроенный, но не смонтированный;
- пассивный autofs без side effects и отдельный согласованный запуск с `--probe-autofs`;
- GIO-ресурс без FUSE и отсутствие дубля одного GIO/FUSE подключения;
- отсутствие ложных SMB/GVFS-строк для обычных подпапок и вложенных CIFS/DFS referral mounts внутри смонтированной шары;
- CUPS journal с 0, 1+ и недоступными записями, а также безопасные рекомендации очистки очередей;
- mail implicit TLS и STARTTLS без credentials/аутентификации/отправки;
- малый и увеличенный `--network-budget`, при которых inventory остаётся полным;
- сравнение времени с 1.2.4 на одном и том же АРМ.

Работа mail-профиля уже подтверждена пользователем на одном целевом АРМ. Итоговый сценарий с тремя SMB-ресурсами после архитектурного stage 3 и полная матрица РЕД ОС ещё не считаются подтверждёнными до повторного прогона.
