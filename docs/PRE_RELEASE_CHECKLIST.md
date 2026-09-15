# Pre-release checklist — v1.2.0

Этот чек-лист используется перед публикацией релиза и не создаёт tag/release автоматически.

- [ ] `bash -n` для основного скрипта, enterprise helper, installer, tests и RPM helper.
- [ ] ShellCheck `--severity=error` без ошибок.
- [ ] Базовые CLI/JSON/privacy tests.
- [ ] Enterprise profiles/compare/recommendations tests.
- [ ] Проверка синтаксиса на Ubuntu, Fedora и Rocky Linux.
- [ ] Совпадение версии в `VERSION`, `arm_info.sh`, enterprise helper, RPM spec и README.
- [ ] Smoke test установки/удаления через `install.sh --destdir`.
- [ ] RPM build smoke test и проверка состава пакета.
- [ ] В helper нет списка конкретного корпоративного ПО и нет жёстко заданного списка кодов Kerberos.
- [ ] Privacy mode не раскрывает hostname/IP/MAC/DNS/domain и credentials в printer URI.
- [ ] Рекомендации для WARN/CRIT/N/A содержат причины, влияние, проверки, действия, команды и контроль результата.
- [ ] Проверка `main...feature` показывает `behind_by = 0` перед merge.
- [ ] Runtime-проверка на реальном РЕД ОС 7.
- [ ] Runtime-проверка на реальном РЕД ОС 8.
- [ ] Только после подтверждения двух предыдущих пунктов — merge/tag/release.
