Name:           arm-info
Version:        1.2.4
Release:        1%{?dist}
Summary:        Diagnostic utility for RED OS and compatible Linux workstations
License:        MIT
URL:            https://github.com/NewMishka/arm_info
Source0:        arm_info.sh
Source1:        arm_info.conf.example
Source2:        LICENSE
Source3:        README.md
BuildArch:      noarch
Requires:       bash
Requires:       coreutils
Requires:       iproute
Requires:       procps-ng
Requires:       util-linux

%description
arm_info collects hardware and operating-system health information, calculates
an explainable technical health index, and produces actionable recommendations.
Version 1.2 adds embedded corporate profiles for domain/Kerberos/DNS,
network/802.1X, CIFS/GVFS, CUPS, global software inventory, and report comparison.
The primary target is RED OS 7/8.

%prep

%build

%install
install -Dm0755 %{SOURCE0} %{buildroot}%{_sbindir}/arm_info
install -Dm0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/arm_info.conf
install -Dm0644 %{SOURCE2} %{buildroot}%{_licensedir}/%{name}/LICENSE
install -Dm0644 %{SOURCE3} %{buildroot}%{_docdir}/%{name}/README.md

%files
%license %{_licensedir}/%{name}/LICENSE
%doc %{_docdir}/%{name}/README.md
%{_sbindir}/arm_info
%config(noreplace) %{_sysconfdir}/arm_info.conf

%changelog
* Wed Sep 16 2026 NewMishka - 1.2.4-1
- Audit and correct all administrator recommendation commands
- Add per-command descriptions, explicit state-change warnings and safe placeholders
- Fix NetworkManager 802.1X/DNS, CUPS package, Kerberos user-context and RAID diagnostics

* Wed Sep 16 2026 NewMishka - 1.2.3-1
- Prioritize the physical system disk and exclude removable/optical media from health scoring
- Fix LVM/device-mapper system-disk detection by using raw lsblk names
- Expand 802.1X certificate discovery and validity reporting across configured NetworkManager profiles
- Add transparent system-stability penalties to the standard report
- Keep long recommendation commands copy-safe as one physical output line
- Synchronize build/release version checks through VERSION and Makefile

* Wed Sep 16 2026 NewMishka - 1.2.2-1
- Aligned and wrapped standard/enterprise recommendations
- Corporate reports save by default with privacy-safe automatic filenames
- Expanded 802.1X certificate diagnostics and command explanations
- CPU temperature is presented as the median in the standard report

* Tue Sep 15 2026 NewMishka - 1.2.1-1
- Single-file distribution: enterprise profiles are embedded in arm_info

* Tue Sep 15 2026 NewMishka - 1.2.0-1
- Enterprise profiles, AD/Kerberos/DNS/CUPS diagnostics and report comparison

* Tue Sep 15 2026 NewMishka - 1.1.0-1
- Public-ready release with CLI, privacy and JSON support
