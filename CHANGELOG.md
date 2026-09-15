# Changelog

## 1.2.0 — 2026-09-15

### Added
- Enterprise-профили `domain`, `network`, `print`, `software`, `enterprise`.
- Проверка AD/SSSD/Kerberos, `adcli testjoin`, Kerberos ticket/cache, time sync и счётчиков Kerberos 6/7/15 в SSSD journal.
- Расширенная DNS-диагностика: источник `/etc/resolv.conf`, upstream DNS, DNS suffix/search, FQDN, LDAP/Kerberos SRV, TCP 88/389.
- Проверка NetworkManager 802.1X и срока доступных CA/client certificates.
- Проверка CIFS/GVFS/Caja с коротким timeout для потенциально зависших mounts.
- Профиль CUPS: service/scheduler, default printer, paused/disabled queues, jobs, backend URI и journal warnings/errors.
- Инвентаризация корпоративного ПО: R7, Citrix/ICAClient, Remmina/FreeRDP, браузеры, Basis Workplace, Crypto/Token middleware и SNX.
- `--compare` для сравнения двух JSON-отчётов АРМ.
- Enterprise JSON schema v2 со стабильными ключами `checks[]`.
- Документация `docs/ENTERPRISE_PROFILES.md` и отдельные CI tests.

### Changed
- Установщик и RPM package устанавливают enterprise helper вместе с основной командой.
- `arm_info.sh` делегирует `--profile` и `--compare` enterprise helper, сохраняя прежний запуск базовой диагностики.
- Privacy mode расширен на доменные/enterprise-поля; printer URI очищается от встроенных учётных данных.

## 1.1.0 — 2026-09-15

### Added
- CLI: `--help`, `--version`, `--privacy`, `--no-save`, `--output`, `--quiet`, `--json`, `--config`.
- JSON schema v1 и exit codes для автоматизации.
- Безопасный privacy mode.
- Настраиваемые пороги `/etc/arm_info.conf`.
- Проверки time sync, previous-boot failure markers, md RAID, ECC/EDAC, battery, SMART self-test, SSSD/Kerberos/CUPS.
- `install.sh`, `Makefile`, RPM spec и build helper.
- CI, security/contributing/conduct, issue/PR templates.
- Документация по privacy, automation, optional checks и compatibility.
- Автоматизация GitHub Releases для v1.0.0 и текущей версии.

### Changed
- Проект подготовлен для публичного использования.
- Технический индекс дополнен RAID/ECC/time-sync сигналами без смешивания прикладных SSSD/CUPS checks с аппаратной оценкой.

## 1.0.0 — 2026-09-15

Первый публичный выпуск: комплексная диагностика АРМ, SMART, системные ресурсы, технический индекс, заключение и рекомендации, TXT-отчёт.
