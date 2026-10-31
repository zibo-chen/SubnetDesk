Name:       subnetdesk
Version:    2.0.0
Release:    0
Summary:    RPM package
License:    GPL-3.0
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool

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
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/subnetdesk.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/subnetdesk.svg
install $HBB/res/rustdesk.desktop %{buildroot}/usr/share/subnetdesk/files/subnetdesk.desktop
install $HBB/res/rustdesk-link.desktop %{buildroot}/usr/share/subnetdesk/files/subnetdesk-link.desktop

%files
/usr/bin/subnetdesk
/usr/share/subnetdesk/libsciter-gtk.so
/usr/share/icons/hicolor/256x256/apps/subnetdesk.png
/usr/share/icons/hicolor/scalable/apps/subnetdesk.svg
/usr/share/subnetdesk/files/subnetdesk.desktop
/usr/share/subnetdesk/files/subnetdesk-link.desktop

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
cp /usr/share/subnetdesk/files/subnetdesk.desktop /usr/share/applications/
cp /usr/share/subnetdesk/files/subnetdesk-link.desktop /usr/share/applications/
systemctl daemon-reload
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
