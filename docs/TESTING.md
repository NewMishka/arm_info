# Тестирование

Перед отправкой PR:

```bash
make check
make test
```

## Что проверяют локальные тесты

`make check` выполняет Bash syntax check для основного single-file скрипта, installer, CLI/enterprise tests и RPM helper. При наличии ShellCheck запускается `shellcheck --severity=error`.

`make test` дополнительно запускает:

- `tests/test_cli.sh` — версия, CLI, standard JSON schema v1, privacy и контракт стандартных рекомендаций;
- `tests/test_enterprise.sh` — enterprise CLI, schema v2, privacy, `--compare`, single-file policy и контракт корпоративного отчёта.

## CI

CI проверяет:

- `bash -n` для shell-файлов;
- ShellCheck уровня `error`;
- базовые CLI/JSON/privacy tests;
- enterprise profiles/compare/recommendations tests;
- Bash syntax в Ubuntu 24.04, Fedora и Rocky Linux 9;
- согласованность версии `VERSION` / `arm_info.sh` / RPM spec / README;
- smoke-test установки/удаления через `install.sh --destdir`;
- single-file policy: отсутствие отдельного enterprise-helper, отсутствие hard-coded списка корпоративного ПО и списка кодов Kerberos;
- RPM build smoke test и состав пакета.

Автоматический CI на Ubuntu/Fedora/Rocky проверяет синтаксис, тестовые контракты, установку и упаковку, но не является runtime-проверкой РЕД ОС.

## Полевой smoke-test РЕД ОС

РЕД ОС 7/8 остаётся основной целевой платформой. Для релизов рекомендуется проверять на доступных реальных АРМ минимум:

```bash
sudo bash arm_info.sh
sudo bash arm_info.sh --privacy
sudo bash arm_info.sh --json --privacy --no-save
sudo bash arm_info.sh --corp
sudo bash arm_info.sh --corp --privacy --json --no-save
sudo bash arm_info.sh --profile software
```

Проверяются не только exit code, но и отсутствие зависания, корректное сохранение отчёта, читаемость таблиц/рекомендаций, privacy и валидность JSON. Наличие `smartmontools`, `dmidecode` и `lm_sensors` повышает полноту базовой диагностики.
