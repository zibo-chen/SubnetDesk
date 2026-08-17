Name:       subnetdesk
Version:    1.2.3
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://github.com/zibo-chen/SubnetDesk
Vendor:     SubnetDesk contributors
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/subnetdesk" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/subnetdesk"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/subnetdesk.service -t "%{buildroot}/usr/share/subnetdesk/files"
install -Dm 644 $HBB/res/rustdesk.desktop "%{buildroot}/usr/share/subnetdesk/files/subnetdesk.desktop"
install -Dm 644 $HBB/res/rustdesk-link.desktop "%{buildroot}/usr/share/subnetdesk/files/subnetdesk-link.desktop"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/subnetdesk.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/subnetdesk.svg"

%files
/usr/share/subnetdesk/*
/usr/share/subnetdesk/files/subnetdesk.service
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
cp /usr/share/subnetdesk/files/subnetdesk.service /etc/systemd/system/subnetdesk.service
cp /usr/share/subnetdesk/files/subnetdesk.desktop /usr/share/applications/
cp /usr/share/subnetdesk/files/subnetdesk-link.desktop /usr/share/applications/
ln -sf /usr/share/subnetdesk/subnetdesk /usr/bin/subnetdesk
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
    rm /usr/bin/subnetdesk || true
    rmdir /usr/share/subnetdesk || true
    rm /usr/share/applications/subnetdesk.desktop || true
    rm /usr/share/applications/subnetdesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
