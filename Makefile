PREFIX ?= /usr/local
DESTDIR ?=
VERSION := $(shell tr -d '[:space:]' < VERSION)

.PHONY: check test version install uninstall

version:
	@printf '%s\n' "$(VERSION)"

check:
	@test -n "$(VERSION)"
	@test "$(VERSION)" = "$$(sed -n 's/^ARM_INFO_VERSION="\([^"]*\)"/\1/p' arm_info.sh | head -1)"
	@test "$(VERSION)" = "$$(awk '/^Version:/{print $$2; exit}' packaging/arm_info.spec)"
	bash -n arm_info.sh install.sh tests/test_cli.sh tests/test_enterprise.sh tests/test_recommendation_commands.sh tests/test_sections.sh tests/test_cifs_probe.sh tests/cifs_field_probe.sh packaging/build-rpm.sh
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck --severity=error arm_info.sh install.sh tests/test_cli.sh tests/test_enterprise.sh tests/test_recommendation_commands.sh tests/test_sections.sh tests/test_cifs_probe.sh tests/cifs_field_probe.sh packaging/build-rpm.sh; fi

test: check
	bash tests/test_cli.sh
	bash tests/test_enterprise.sh
	bash tests/test_recommendation_commands.sh
	bash tests/test_sections.sh
	bash tests/test_cifs_probe.sh

install:
	bash install.sh --prefix "$(PREFIX)" --destdir "$(DESTDIR)"

uninstall:
	bash install.sh --prefix "$(PREFIX)" --destdir "$(DESTDIR)" --uninstall
