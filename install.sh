#!/usr/bin/env bash
set -euo pipefail

PREFIX=/usr/local
DESTDIR=
ACTION=install

usage() {
  cat <<'USAGE'
Использование: sudo bash install.sh [--prefix /usr/local] [--destdir PATH] [--uninstall]

Устанавливает:
  <prefix>/sbin/arm_info
  /etc/arm_info.conf (только если файла ещё нет)
USAGE
}

while (($#)); do
  case "$1" in
    --prefix) PREFIX=${2:?}; shift 2 ;;
    --destdir) DESTDIR=${2:?}; shift 2 ;;
    --uninstall) ACTION=uninstall; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Неизвестный параметр: $1" >&2; usage >&2; exit 64 ;;
  esac
done

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN="$DESTDIR$PREFIX/sbin/arm_info"
CONF="$DESTDIR/etc/arm_info.conf"

if [[ $ACTION == uninstall ]]; then
  rm -f "$BIN"
  echo "Удалено: $BIN"
  echo "Конфигурация $CONF сохранена. Удалите её вручную при необходимости."
  exit 0
fi

install -Dm0755 "$ROOT/arm_info.sh" "$BIN"
if [[ ! -e $CONF ]]; then
  install -Dm0644 "$ROOT/config/arm_info.conf.example" "$CONF"
  echo "Создана конфигурация: $CONF"
else
  echo "Конфигурация уже существует, не изменена: $CONF"
fi

echo "Установлено: $BIN"
echo "Запуск: sudo $PREFIX/sbin/arm_info"
