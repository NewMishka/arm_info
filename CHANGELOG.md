# Changelog

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
