Name:       subnetdesk
Version:    1.2.3
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://github.com/zibo-chen/SubnetDesk
Vendor:     SubnetDesk contributors
Requires:   gtk3 libxcb libXfixes alsa-lib libva2 pam gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/subnetdesk/
mkdir -p %{buildroot}/usr/share/subnetdesk/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/rustdesk %{buildroot}/usr/bin/subnetdesk
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/subnetdesk/libsciter-gtk.so
install $HBB/res/subnetdesk.service %{buildroot}/usr/share/subnetdesk/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/subnetdesk.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/subnetdesk.svg
install $HBB/res/rustdesk.desktop %{buildroot}/usr/share/subnetdesk/files/subnetdesk.desktop
install $HBB/res/rustdesk-link.desktop %{buildroot}/usr/share/subnetdesk/files/subnetdesk-link.desktop

%files
/usr/bin/subnetdesk
/usr/share/subnetdesk/libsciter-gtk.so
/usr/share/subnetdesk/files/subnetdesk.service
/usr/share/icons/hicolor/256x256/apps/subnetdesk.png
/usr/share/icons/hicolor/scalable/apps/subnetdesk.svg
/usr/share/subnetdesk/files/subnetdesk.desktop
/usr/share/subnetdesk/files/subnetdesk-link.desktop
/usr/share/subnetdesk/files/__pycache__/*

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop subnetdesk || true
  ;;
esac

%post
cp /usr/share/subnetdesk/files/subnetdesk.service /etc/systemd/system/subnetdesk.service
cp /usr/share/subnetdesk/files/subnetdesk.desktop /usr/share/applications/
cp /usr/share/subnetdesk/files/subnetdesk-link.desktop /usr/share/applications/
systemctl daemon-reload
systemctl enable subnetdesk
systemctl start subnetdesk
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop subnetdesk || true
    systemctl disable subnetdesk || true
    rm /etc/systemd/system/subnetdesk.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/share/applications/subnetdesk.desktop || true
    rm /usr/share/applications/subnetdesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
