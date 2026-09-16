# Pre-release checklist — arm_info 1.2.x

Этот чек-лист используется перед публикацией релиза. Он не создаёт tag/release автоматически: публикация выполняется release workflow после попадания новой версии в `main` либо вручную через `workflow_dispatch`.

- [ ] `bash -n` для `arm_info.sh`, installer, tests и RPM helper.
- [ ] ShellCheck `--severity=error` без ошибок.
- [ ] Базовые CLI/JSON/privacy tests.
- [ ] Enterprise profiles/compare/recommendations tests.
- [ ] Проверка синтаксиса на Ubuntu 24.04, Fedora и Rocky Linux 9.
- [ ] Совпадение версии в `VERSION`, `arm_info.sh`, RPM spec и README.
- [ ] В репозитории отсутствует устаревший `arm_info-enterprise.sh`: enterprise-профили встроены в `arm_info.sh`.
- [ ] Smoke test установки/удаления через `install.sh --destdir`.
- [ ] RPM build smoke test и проверка состава пакета.
- [ ] В `arm_info.sh` нет списка конкретного корпоративного ПО и нет жёстко заданного списка кодов Kerberos.
- [ ] Privacy mode не раскрывает hostname/IP/MAC/DNS/domain и credentials в printer URI; автоматическое имя privacy-отчёта не содержит hostname.
- [ ] Стандартные рекомендации выровнены и содержат причины, влияние, проверки, действие, команду и контроль результата.
- [ ] Enterprise-рекомендации содержат источник, причины, влияние, проверки, действия, команды и контроль результата; shell pipelines/regex с `|` не разрываются на отдельные команды.
- [ ] `--corp` и `--profile enterprise` сохраняют TXT/JSON по умолчанию; `--no-save` отключает сохранение; `-o` работает для файла и каталога.
- [ ] В стандартном отчёте температура CPU выводится как медиана без одновременного значения максимума.
- [ ] Для 1.2.3 системный физический диск корректно определяется по корневой ФС, в том числе при LVM/device-mapper, и выводится первым с ролью `Системный`.
- [ ] Подключённый USB/съёмный накопитель имеет роль `Съёмный (вне индекса)` и не меняет storage score, SMART completeness и эксплуатационный возраст АРМ.
- [ ] Файловая система на USB/съёмном носителе не подменяет `Макс. заполнение`, inode-score и read-only оценку внутренних ФС.
- [ ] Стандартный JSON различает системные, дополнительные внутренние и съёмные накопители; removable media не делают `storage.known=false`.
- [ ] README, CHANGELOG, `docs/USAGE.md`, `docs/AUTOMATION.md`, `docs/ENTERPRISE_PROFILES.md`, `docs/SCORING.md`, `docs/TESTING.md`, release notes и пример отчёта соответствуют текущему поведению.
- [ ] В release workflow публикуется актуальный single-file asset `arm_info.sh` и checksum; устаревший enterprise-helper не прикладывается.
- [ ] Проверка `main...feature` показывает `behind_by = 0` перед merge.
- [ ] Полный CI PR завершён со статусом success.
- [ ] Runtime smoke-test выполнен на доступных целевых РЕД ОС; для 1.2.3 отдельно сравнить один и тот же АРМ без USB и с подключённой флешкой.
- [ ] Если одна из поддерживаемых веток РЕД ОС не проверена перед выпуском, это не должно описываться как подтверждённая runtime-совместимость.
- [ ] После merge подтверждены tag, GitHub Release, release asset и checksum.
