# Win7 x64 Flutter 专用包

当前 Win7 路线与 RustDesk 原版一致：Flutter 3.24.5 / Dart 3.5.4，加上
`rustdesk/engine` 发布的 `windows-x64-release.zip` 定制引擎。
Sciter Win7 构建、Sciter 引擎下载和旧测试版发布流程已废弃，专用包不包含 Sciter DLL。
范围为 Windows 7 SP1 **64 位**；不再生成 32 位 Sciter 替代包。

## 引擎与共享 UI

引擎来源及 SHA-256 固定在 `res/win7/flutter-engine.json`。下载地址虽是上游的
`main` release，文件内容必须匹配固定哈希；校验失败会阻止构建，不能自动接受替换文件。
引擎、导入库、头文件和 `gen_snapshot.exe` 必须整体替换，不能只替换 DLL。
构建后再次比对包内 `flutter_windows.dll`，确保 Flutter 工具未恢复普通引擎。

参考固定版本的 [RustDesk 原版流程](https://github.com/rustdesk/rustdesk/blob/bd9262397208c509ea97af61f0d44621ef25611c/.github/workflows/flutter-build.yml)
及 [定制引擎构建流程](https://github.com/rustdesk/engine/blob/9176a596b1f82625dfe8831edbcc4f2c9dc22da9/.github/workflows/flutter-engine-windows-x64-release-build.yml)。

`flutter/` 是唯一 UI 来源，首页、本机设置、设备列表、主题、插画、会话窗口和远控工具栏
均直接复用。`scripts/prepare_win7_flutter.py` 在独立构建目录中做 SDK API 兼容替换：
颜色透明度、主题类型、下拉框初值、文件选择器接口，以及访问引导弹层的布局信息。
弹层内容和交互仍来自同一组件。不会维护第二套页面或改写正常版本的依赖文件。
Win7 的依赖版本和锁文件分别位于 `res/win7/flutter-dependencies.json`、
`res/win7/flutter-pubspec.lock`。源码/资源哈希和兼容变更文件随包记录。

旧 SDK 下发现自绘滑块在宽松约束中宽度为 0；共享组件现在显式采用可用宽度，保留原有
指针、键盘和无障碍交互。共享 Flutter 测试在 Win7 SDK 上执行，不跳过失败用例。

## Rust 与原生依赖

当前 LAN 后端的依赖需要比 RustDesk 原版 1.75 更新的 Rust。使用固定
`nightly-2025-08-01` 和 `x86_64-win7-windows-msvc` 专用目标，以
`-Z build-std=std,panic_abort` 从源码构建 Win7 标准库。
不使用普通现代 Windows target 的标准库，也不使用 Sciter 可执行程序。

vcpkg 依赖树独立于普通 Windows 包，固定 baseline，使用静态 CRT、
`WINVER/_WIN32_WINNT=0x0601` 和软件编解码。不启用 `hwcodec`、`vram`，
不携带现代 Windows 的显示器驱动、注入工具或系统服务。
Flutter runner 和目录包启动器均声明 Win7 支持及旧系统 DPI 回退，并保留管理员权限。

## GitHub runner 构建

`.github/workflows/windows-win7-flutter.yml` 可手动运行；推送 `win7-test/**` 分支也会触发。
流程使用 Windows Server 2022 runner，执行：

1. 锁定依赖及共享 UI 回归测试。
2. 校验并替换 RustDesk 定制 Flutter 引擎。
3. 构建 Win7 原生依赖、Rust Flutter 库、Flutter runner 和便携入口。
4. 验证引擎身份，对包中每个 EXE、DLL 检查架构、子系统及已知不兼容导入。
   Dart `data/app.so` 是引擎自行加载的 ELF AOT 快照，单独检查 x64 格式、快照导出和无外部 ELF 依赖。
5. 在 runner 执行实际包内程序的 `--version`，上传专用测试 ZIP 和校验/导入报告。

本地 Windows 开发环境需先安装 NSIS 3（`choco install nsis --yes`），然后使用：

```powershell
.\scripts\ci_win7.ps1 -Arch x64 -FlutterSdk C:\flutter-3.24.5
```

输出为 `target/win7-dist/subnetdesk-<版本>-win7-x64-flutter.zip` 和
`subnetdesk-<版本>-win7-x64-flutter-setup.exe`。
安装版使用同一份已检查的 Flutter 运行文件，默认安装到 `Program Files\SubnetDesk`，
需要管理员权限，提供简体中文/英文界面、桌面/开始菜单快捷方式和系统卸载入口。
安装、重装和卸载均不覆盖或删除安装目录中的 `userdata/`；重装前需从托盘退出程序。
安装版不自动迁移绿色版配置；如需沿用原设备身份，先退出程序，再自行备份并复制原
`userdata/` 到安装目录。`*-setup.json` 记录安装器哈希、来源和逐文件哈希。

解压整个目录后运行顶层 `SubnetDesk.exe`；`app/` 存放运行文件，`userdata/` 存放独立配置、
身份和日志。测试 ZIP 不覆盖现有配置。配套 `*-provenance.json` 提供源码、引擎和包的哈希，
`*-imports.json` 提供逐个 PE 文件的检查结果，`*-aot.json` 记录 Dart 快照检查。

也可直接将已验证的绿色目录包封装成安装版（不会重新编译或修改运行文件）：

```powershell
python scripts/package_win7_installer.py --package target/win7-dist/subnetdesk-1.3.0-win7-x64-flutter --version 1.3.0 --output target/win7-dist/subnetdesk-1.3.0-win7-x64-flutter-setup.exe
```

## 验收边界

GitHub runner 和现有 Jenkins 节点运行的是较新 Windows。其构建、启动及 PE 导入检查
不能替代 Win7 SP1 实机的 UI、认证、屏幕捕获、键鼠输入、托盘和完整连接测试。
现阶段先交付专用测试包和兼容检查；未执行的 Win7 实机项目保持未验证状态。
旧 `ci-progress.md`、`design-qa.md` 和旧截图仅保留为废弃 Sciter 路线的历史记录。
