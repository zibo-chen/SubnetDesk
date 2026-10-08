# Win7 Sciter 构建

Win7 作为独立构建目标使用当前 LAN 后端，不回退到旧版 RustDesk 协议。
已在 Jenkins 的 Windows 10 设备构建 x64/x86 候选包并通过启动及 Sciter ABI 冒烟检查，尚未经过 Win7 SP1 实机验收或发布。

| 架构 | Rust target | vcpkg triplet |
| --- | --- | --- |
| 64 位 | `x86_64-win7-windows-msvc` | `x64-windows-static` |
| 32 位 | `i686-win7-windows-msvc` | `x86-windows-static` |

固定工具链为 `nightly-2025-08-01`（Rust 1.90.0 nightly），通过 `rust-src` 和
`-Z build-std=std,panic_abort` 构建 Win7 标准库。主程序、服务和便携启动器均使用
相同 target。旧版 windows-rs 的导入库由锁定依赖补充到链接器搜索路径；预取普通 MSVC
依赖包只用于取得导入库，不编译其标准库或程序。普通 `pc-windows-msvc` 不能替代该 target。
依据：[Rust 官方 Win7 target 文档](https://doc.rust-lang.org/rustc/platform-support/win7-windows-msvc.html)。

## 构建

`.github/workflows/windows-win7.yml` 提供手动运行及 reusable workflow 入口，推送 win7-test/ 前缀测试分支也会触发两个架构的构建。
在 Windows Server 2022 构建两个架构并上传 candidate artifacts，不自动发布 release。
旧 `flutter-build.yml` 中的 Sciter job 仍保持禁用。

本地构建需 Windows 10/11、对应架构的 VS 2022 MSVC developer PowerShell、Python 3、
LLVM/Clang、NASM。将 LLVM 和 NASM 加入 PATH，并设置 `LIBCLANG_PATH` 为 LLVM 的 bin。
Jenkins Windows CI 设备可使用 `scripts/ci_win7.ps1 -Arch both`；脚本加载 MSVC 后会恢复
专用 vcpkg 环境，以免 VS 覆盖 `VCPKG_ROOT`。进度与修复证据见 [ci-progress.md](ci-progress.md)。
构建脚本使用 Cargo 的 target.sodium 配置，按目标架构选择锁定 libsodium-sys 包中的静态库；x64 构建工具继续使用默认库。参考 [Cargo links override](https://doc.rust-lang.org/cargo/reference/config.html#targettriplelinks)。
以下示例在仓库根目录构建 x64；x86 使用 x86 developer shell，并替换 triplet 和 `--arch`。

```powershell
rustup toolchain install nightly-2025-08-01 --profile minimal --component rust-src
python -m pip install brotli
$env:VCPKG_ROOT = "C:\vcpkg-win7"
$env:VCPKG_INSTALLED_ROOT = "$env:VCPKG_ROOT\installed"
$env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"
git clone https://github.com/microsoft/vcpkg $env:VCPKG_ROOT
git -C $env:VCPKG_ROOT checkout 120deac3062162151622ca4860575a33844ba10b
& "$env:VCPKG_ROOT\bootstrap-vcpkg.bat" -disableMetrics
& "$env:VCPKG_ROOT\vcpkg.exe" install --enforce-port-checks --triplet x64-windows-static --x-manifest-root="$pwd/res/win7" --overlay-triplets="$pwd/res/win7/triplets" --overlay-ports="$pwd/res/win7/ports" --overlay-ports="$pwd/res/vcpkg" --x-install-root="$env:VCPKG_INSTALLED_ROOT"
python scripts/build_win7.py --arch x64
```

原生依赖树独立于 Flutter，使用静态 CRT 和 Win7 的 `WINVER/_WIN32_WINNT=0x0601`。
仅构建软件编解码需要的 aom、libvpx、libyuv、opus 和 libjpeg-turbo；不启用
`flutter`、`hwcodec`、`vram`。`windows_slim_errors` 排除 windows-result 的可选 WinRT 错误信息 ABI。
Win7 专用 Opus overlay 显式启用 `OPUS_STATIC_RUNTIME`，避免上游默认为动态 CRT
（[Opus 1.5.2 官方 CMake 配置](https://github.com/xiph/opus/blob/v1.5.2/CMakeLists.txt)）。
vcpkg 安装启用 `--enforce-port-checks`，CRT 不匹配会阻断构建。
不要设置覆盖 `.cargo/config.toml` 的 `RUSTFLAGS` 或 `CARGO_ENCODED_RUSTFLAGS`。

输出位于 `target/win7-dist`：同架构的 ZIP、便携 EXE、Sciter ABI 冒烟 EXE 和导入报告。
ZIP 包含 `rustdesk.exe`、`service.exe`、`sciter.dll` 和第三方许可。
便携 EXE 使用同一 Win7 target 编译，不复用现代 Windows 启动器。

## Sciter 与 Flutter 共用功能

首页采用当前 Flutter 的侧栏、本机卡片、搜索、收藏、网格/列表和设备卡片结构。
LAN 设置、设备名、账号和身份管理连接现有 Rust 后端。连接时可手动输入 LAN 凭据，
或选择已有身份，并由同一后端处理首次设备信任和指纹变更。
LAN 设置验证、服务运行状态及最近连接数据在 `src/lan_ui.rs` 共用，Flutter FFI 签名保持不变。

当前 Sciter 绑定固定为仓库内的 `libs/sciter-rs`，来源及补丁见其 `SUBNETDESK.md`。
引擎使用 TIScript SDK 的固定 commit `f33df075d9eb2f8d252cb88f1b2c8096e56197ed`，
两种架构的 DLL 下载后必须通过 SHA-256 验证；不会下载新的 Sciter.JS 引擎。
引擎许可保留在 `res/win7/sciter-license.htm`，About 区域保留供应商链接及版权说明。

## 已完成检查与验收边界

- Rust 1.90 nightly：当前非 Flutter 库、主程序和服务通过本机编译检查。
- Rust 1.97.1：Flutter 库通过本机编译检查；共用 LAN 状态的 3 个测试通过。
- 两个专用 Win7 target：从源码构建标准库后，Sciter 绑定及冒烟程序通过交叉编译检查。
- 真实 Sciter 引擎：本机值传递、索引引用保留、窗口创建和脚本调用的 ABI 冒烟检查通过。
- x86/x64 引擎 DLL：PE 架构、子系统版本和已知后 Win7 导入检查通过。
- PE 解析、构建边界及导入库选择的 8 个 Python 测试、LAN-only 与品牌检查通过。
- Windows 10 CI 设备：两个架构的完整软件原生依赖、主程序、服务、便携启动器构建通过。
- Windows 10 运行：两个主程序返回版本 1.3.0；两个架构的精确 Sciter DLL ABI 冒烟通过。
- 每个架构的五个 PE 产物检查通过；本地/远程产物哈希和关键源码输入一致，下载后复查通过。

前六项为 macOS arm64 检查；Windows 证据见 [ci-progress.md](ci-progress.md) 和
[windows-build-evidence.json](windows-build-evidence.json)。本次通过 SSH 在同一 Jenkins 设备执行，
没有 Jenkins job/build number。x86 视频 thiscall、完整远程会话、便携解包/安装、
服务生命周期及 Win7 SP1 真机测试尚未执行。PE 检查覆盖普通和延迟导入，但它是已知不兼容
API 的回归检查，不是完整 Win7 API 白名单，也不能验证动态加载调用或驱动行为。

发布前应在 Win7 SP1 x86 和 x64 分别完成：

1. 从干净系统启动 ZIP 和便携 EXE，确认引擎加载、安装、服务启动/停止/卸载。
2. 本机账号设置、服务进程同步、发现、IPv4/IPv6、白名单和凭据错误反馈。
3. 与当前 Flutter 客户端双向连接；首次信任、拒绝、指纹变更、身份选择和记住凭据。
4. GDI 屏幕捕获、软件视频解码、鼠标/键盘、剪贴板、文件传输及重连。
5. UAC/登录界面、不同用户会话、DPI 100%/150%、低分辨率及多显示器。
6. 如果启用 Web 访问，验证 HTTPS、证书和网络访问控制。

界面检查证据见 [design-qa.md](design-qa.md)。远程工具栏、文件传输和连接管理器
继续使用 Sciter 原有交互，当前只继承共用主题及弹窗样式，尚未逐页达到 Flutter 的完整视觉与功能一致性。
