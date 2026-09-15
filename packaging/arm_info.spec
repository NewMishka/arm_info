Name:           arm-info
Version:        1.1.0
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
The primary target is RED OS 7/8.

%prep

%build

%install
install -Dm0755 %{SOURCE0} %{buildroot}%{_sbindir}/arm_info
install -Dm0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/arm_info.conf

%files
%license %{SOURCE2}
%doc %{SOURCE3}
%{_sbindir}/arm_info
%config(noreplace) %{_sysconfdir}/arm_info.conf

%changelog
* Tue Sep 15 2026 NewMishka - 1.1.0-1
- Public-ready release with CLI, privacy and JSON support
