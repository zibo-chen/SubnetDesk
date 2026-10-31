; The payload is the verified Flutter directory package, without user data.
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"
!include "x64.nsh"

Name "SubnetDesk"
OutFile "${OUTPUT}"
InstallDir "$PROGRAMFILES64\SubnetDesk"
RequestExecutionLevel admin
ManifestSupportedOS all
SetCompressor /SOLID lzma
SetOverwrite on
ShowInstDetails show
ShowUninstDetails show
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "SubnetDesk"
VIAddVersionKey "FileDescription" "SubnetDesk Windows 7 x64 Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "SubnetDesk contributors"
Icon "${ICON}"
!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

LangString UnsupportedOS ${LANG_SIMPCHINESE} "需要 Windows 7 SP1 或更高版本的 64 位 Windows。"
LangString UnsupportedOS ${LANG_ENGLISH} "Windows 7 SP1 or later, 64-bit Windows is required."
LangString CloseApp ${LANG_SIMPCHINESE} "请先从托盘退出 SubnetDesk，再运行安装或卸载程序。"
LangString CloseApp ${LANG_ENGLISH} "Exit SubnetDesk from the system tray before installing or uninstalling."
LangString KeepData ${LANG_SIMPCHINESE} "卸载将保留安装目录下的 userdata 文件夹，其中包含设置和设备身份。"
LangString KeepData ${LANG_ENGLISH} "Uninstall keeps the userdata folder containing settings and device identity."

!macro CheckAppRunning
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\SubnetDesk-InteractiveRuntime") p.r0'
  ${If} $0 != 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(CloseApp)" /SD IDOK
    SetErrorLevel 2
    Abort
  ${EndIf}
!macroend

Function .onInit
  ${IfNot} ${RunningX64}
  ${OrIfNot} ${AtLeastWin7}
    MessageBox MB_OK|MB_ICONSTOP "$(UnsupportedOS)" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  ${If} ${IsWin7}
  ${AndIfNot} ${AtLeastServicePack} 1
    MessageBox MB_OK|MB_ICONSTOP "$(UnsupportedOS)" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  SetRegView 64
  SetShellVarContext all
  ReadRegStr $0 HKLM "Software\SubnetDesk\Win7Installer" "InstallLocation"
  ${If} $0 != ""
    StrCpy $INSTDIR $0
  ${EndIf}
  !insertmacro CheckAppRunning
FunctionEnd

Function un.onInit
  SetRegView 64
  SetShellVarContext all
  !insertmacro CheckAppRunning
  IfSilent +2
  MessageBox MB_OK|MB_ICONINFORMATION "$(KeepData)"
FunctionEnd

Section "SubnetDesk"
  !include "${INSTALL_FILES}"
  CreateDirectory "$INSTDIR\userdata"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\SubnetDesk"
  SetOutPath "$INSTDIR"
  CreateShortcut "$SMPROGRAMS\SubnetDesk\SubnetDesk.lnk" "$INSTDIR\SubnetDesk.exe"
  CreateShortcut "$SMPROGRAMS\SubnetDesk\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\SubnetDesk.lnk" "$INSTDIR\SubnetDesk.exe"
  WriteRegStr HKLM "Software\SubnetDesk\Win7Installer" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "DisplayName" "SubnetDesk (Windows 7 x64)"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "Publisher" "SubnetDesk"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "DisplayIcon" "$INSTDIR\SubnetDesk.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7" "NoRepair" 1
SectionEnd

Section "Uninstall"
  !include "${UNINSTALL_FILES}"
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$DESKTOP\SubnetDesk.lnk"
  Delete "$SMPROGRAMS\SubnetDesk\SubnetDesk.lnk"
  Delete "$SMPROGRAMS\SubnetDesk\Uninstall.lnk"
  RMDir "$SMPROGRAMS\SubnetDesk"
  DeleteRegKey HKLM "Software\SubnetDesk\Win7Installer"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SubnetDeskWin7"
  ; Non-recursive: preserve userdata and any files not owned by the installer.
  RMDir "$INSTDIR"
SectionEnd
