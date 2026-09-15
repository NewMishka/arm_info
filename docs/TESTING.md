# Тестирование

Перед отправкой PR:

```bash
make check
make test
```

## CI

CI проверяет:

- `bash -n` для основных shell-файлов;
- ShellCheck уровня `error`;
- CLI, JSON schema v1 и privacy mode;
- синтаксическую совместимость Bash в контейнерах Ubuntu, Fedora и Rocky Linux.

РЕД ОС 7/8 остаётся основной полевой платформой. Перед релизом рекомендуется ручной smoke-test минимум на одной системе РЕД ОС 7.x и одной РЕД ОС 8.x с `smartmontools`, `dmidecode` и `lm_sensors`.
