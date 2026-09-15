PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: check test install uninstall

check:
	bash -n arm_info.sh install.sh tests/test_cli.sh
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck --severity=error arm_info.sh install.sh tests/test_cli.sh; fi

test: check
	bash tests/test_cli.sh

install:
	bash install.sh --prefix "$(PREFIX)" --destdir "$(DESTDIR)"

uninstall:
	bash install.sh --prefix "$(PREFIX)" --destdir "$(DESTDIR)" --uninstall
