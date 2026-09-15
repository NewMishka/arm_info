#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOP=${RPM_TOPDIR:-$HOME/rpmbuild}
mkdir -p "$TOP"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}
install -m0644 "$ROOT/arm_info.sh" "$TOP/SOURCES/arm_info.sh"
install -m0644 "$ROOT/arm_info-enterprise.sh" "$TOP/SOURCES/arm_info-enterprise.sh"
install -m0644 "$ROOT/config/arm_info.conf.example" "$TOP/SOURCES/arm_info.conf.example"
install -m0644 "$ROOT/LICENSE" "$TOP/SOURCES/LICENSE"
install -m0644 "$ROOT/README.md" "$TOP/SOURCES/README.md"
install -m0644 "$ROOT/packaging/arm_info.spec" "$TOP/SPECS/arm_info.spec"
rpmbuild --define "_topdir $TOP" -ba "$TOP/SPECS/arm_info.spec"
echo "RPM: $TOP/RPMS/noarch/"
