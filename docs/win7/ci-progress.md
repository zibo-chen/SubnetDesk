# Windows CI 验证进度

状态：两个架构的完整候选构建、Windows 主程序启动检查、Sciter ABI 冒烟及各五项 PE 检查通过。Win7 SP1 实机及完整 UI 对齐尚待验收。

最新验证：2026-10-08 14:39:49 UTC，最终构建耗时 18 分 8 秒，退出码 0。
可复核产物哈希、关键构建输入哈希与运行结果见 [windows-build-evidence.json](windows-build-evidence.json)。
本地包保存在 target/win7-dist，均为候选包，未提交或发布。

- Jenkins 节点：`ci-windows-01`，Windows 10，online / idle，1 executor。
- 同一设备通过 SSH 使用 `DevAdmin@10.1.0.103`，hostname `win-dev-01`。
- 本次直接在该 CI 设备的独立目录执行验证，没有对应 Jenkins build number；不得将本次设备测试表述为 Jenkins job SUCCESS。
- 远程源码：`C:\SubnetDeskWin7\run-20261008\source`。
- 本地起点：`b87ed2ab0ec90f2508346cb3be91139b29d6f76a` 加当前工作区修改。
- 源码归档 SHA-256：`75c06b570722a2f6d02ef59bce9069ab03fb5cc478991d61a4a5ea2d814e12f7`。
- CI 脚本额外复制到快照中；SHA-256：`322e2969c8cc12b82f6b2798f0094ee8e8f4eecc7b9b96f9b49d38e966134db6`。
- 流程：固定 nightly + rust-src、独立 vcpkg、x64/x86 主程序/服务/便携启动器、真实 Windows Sciter ABI 冒烟、PE 导入回归检查。
- 构建机验证不替代 Win7 SP1 实机兼容性和交互界面验收。

以下保留失败原因和修复证据。

## 尝试 1：工具链准备失败（已修复）

固定 Rust nightly 和 rust-src 已安装成功；随后 rustup 自动更新阶段因独立 CARGO_HOME 中未安装 rustup 而退出 1。
CI 脚本增加 `--no-self-update`，避免修改构建机的 rustup 安装；工具链检查单独复测通过后继续构建。
原始日志保留于本机 `/tmp/subnetdesk-win7-ci-logs/attempt-01.log`。

## 尝试 2：MSVC 环境初始化失败（已修复）

Python/Brotli、固定 vcpkg 和 5 个构建边界/PE 测试均通过；随后 PowerShell 传给 cmd 的路径引号错误，未能执行包含空格的 VsDevCmd.bat。
改为独立 `.cmd` 文件加载 MSVC 环境，分别实测 x64/x86 的目标架构及 SDK 路径后继续。
原始日志保留于本机 `/tmp/subnetdesk-win7-ci-logs/attempt-02.log`。

## 尝试 3：资源编码失败，发现 CRT 不一致（已修复，待重建）

x64 软件编解码依赖编译完成，耗时约 7.4 分钟；应用编译前的 `inline-sciter.py` 因 Windows GBK 默认编码无法读取 UTF-8 UI 文件而失败。全部资源读写改为显式 UTF-8。
Opus 库的 vcpkg post-build check 同时显示 `/MD` 和 `/MDd`；Win7 专用 overlay 启用上游 `OPUS_STATIC_RUNTIME=ON`，后续重建验证静态 CRT。
额外更新：`res/inline-sciter.py`、`scripts/ci_win7.ps1`、`res/win7/ports/opus/*`，分别复制到原始快照中；源码归档原 SHA 不代表这些后续修复，以下是更新文件的 SHA-256。
- `res/inline-sciter.py`: `123dbf84022a4197caad8353ce775f08d6cc8d2e158141aa22890e7a90afefcc`
- `scripts/ci_win7.ps1`: `fd7e2ed5f0e01d6843c763d5a041ba1e61b7ce51c06dca0c294e4f0587a8d900`
- `res/win7/ports/opus/fix-pkgconfig-version.patch`: `b1998186940daff04e5c332fbb7f27f756cf5c2227f6e8c3f37f2fb2e8222286`
- `res/win7/ports/opus/portfile.cmake`: `0cfff83949bc9804f34e70c273d54a1d64d2e420af2e9ee7f85a5e498cb2bfcf`
- `res/win7/ports/opus/vcpkg.json`: `024bb3bdbf503bebb3033149127cff008e83de347efb17534ece30dfa2f10690`
原始日志保留于本机 `/tmp/subnetdesk-win7-ci-logs/attempt-03.log`。

Windows 原生 `cp936` 编码下的资源生成复测已通过。vcpkg 安装新增 `--enforce-port-checks`，将 CRT 等 post-build 检查问题作为失败处理。

## 尝试 4：绑定生成器使用错误依赖目录（已修复）

Win7 Opus overlay 重建成功，严格 vcpkg 检查通过，不再报告动态 CRT；Rust 应用开始编译。
Magnum Opus 的绑定生成失败，因为 VsDevCmd.bat 将 VCPKG_ROOT 改为 Visual Studio 自带的 vcpkg，无法找到已编译的 Opus 头文件。
CI 脚本在加载 MSVC 后重新设置专用 VCPKG_ROOT / INSTALLED_ROOT / HOST_TRIPLET，并输出实际目录；GitHub workflow 的构建步骤也显式固定目录。
更新 scripts/ci_win7.ps1 的 SHA-256：322e2969c8cc12b82f6b2798f0094ee8e8f4eecc7b9b96f9b49d38e966134db6。原始日志保留于 /tmp/subnetdesk-win7-ci-logs/attempt-04.log。

## 尝试 5：AOM pkg-config 清理的重复替换失败（已修复）

实际依赖根目录已正确固定为 C:/SubnetDeskWin7/vcpkg，使用固定版本工具重建原生依赖。AOM 编译完成后，pkg-config 清理阶段再次删除已被 vcpkg 清理过的 -lm，触发 vcpkg_replace_string made no changes。
AOM port 在读取文件并确认仍包含 -lm 后才执行替换，保留文件不存在或其他构建错误的失败行为。
更新 res/vcpkg/aom/portfile.cmake 的 SHA-256：d836ae85d40ac2a6a20c5442f3e87dd4e76c1aab11f00ee8f2e1293b2ca509e6。原始日志保留于 /tmp/subnetdesk-win7-ci-logs/attempt-05.log。

## 尝试 6：旧 Windows 绑定的导入库搜索路径缺失（已修复）

固定版本 vcpkg 的全部 x64 依赖通过严格检查，耗时约 7.3 分钟；Magnum Opus 绑定生成不再报缺失头文件。应用依赖 nokhwa 的 DLL 链接缺少 windows.lib。
已核对 Cargo.lock 中的 windows-rs 依赖：旧清单和 build.rs 只识别 pc/uwp Windows target，未为专用 Win7 target 提供导入库路径。
构建脚本先 fetch 已锁定的普通 MSVC 依赖包（仅下载导入库，不编译普通 target），再按架构和锁定版本为链接器添加 LIB 搜索路径。所有实际编译仍使用专用 Win7 target 和 build-std。
新增 2 个测试验证版本/架构选择及缺失库时提前失败，现有共 7 个测试通过。更新文件 SHA-256：
- scripts/build_win7.py: a016bfb8a9f86f1be9f80856641cd970d1ab8fc847e8f79d601fc544284035e5
- scripts/test_win7_build.py: 0500b605f2624669b298a07eacc75d327b9694f94fc8803341eed33419139eb0
原始日志保留于 /tmp/subnetdesk-win7-ci-logs/attempt-06.log。

## 尝试 7：x64 候选包通过，x86 libyuv 参数失败（已修复）

总耗时 13 分 22 秒。x64 主程序/服务、Sciter 冒烟程序和便携启动器全部构建成功；真实 Windows Sciter 冒烟通过，五个产物的 PE 检查通过，并生成 EXE/ZIP/JSON 报告。
x86 AOM、JPEG 和 libvpx 编译通过，随后 libyuv 的 clang 参数缺少前导空格，使 --target 被并入 WINVER 宏定义。已修正 C/C++ 两处参数拼接。
更新 res/vcpkg/libyuv/portfile.cmake 的 SHA-256：02fa04f5db7cf311b17492269459c1a59bd84faf3280bbefb10a7355337c5ccf。
原始日志保留于 /tmp/subnetdesk-win7-ci-logs/attempt-07.log。下一次同时复测两个架构，并清理专用目录中的 x64 scrap 构建记录，确保应用重新链接修正后的原生库。

## 尝试 8：x64 复测通过，x86 libsodium 链接失败（已修复）

总耗时 15 分 39 秒。libyuv 的参数修复后，x64 重新链接并通过 Sciter 冒烟及五项 PE 检查；x86 的全部原生依赖严格检查通过，进入应用链接。
libsodium-sys 0.2.7 的旧 build.rs 使用构建机 cfg(target_pointer_width)，在 x64 主机为 x86 目标选择了 x64 libsodium.lib，触发 LNK4272 和 132 个未解析符号。
构建脚本通过 SODIUM_LIB_DIR 明确选择 Cargo.lock 锁定包中的目标架构 Release/v142 静态库，不修改公共依赖源或改用普通 Windows target。dumpbin 输出确认 Win32 库为 14C/x86，使用 LIBCMT 静态 CRT。
新增架构、锁定版本和缺失库失败测试，共 8 个 Python 测试通过。原始日志保留于 /tmp/subnetdesk-win7-ci-logs/attempt-08.log。
- scripts/build_win7.py SHA-256：d47132be28a9739cd7d68b3c5397e46a279dfad27a7e846c3f16cc430b99e4eb
- scripts/test_win7_build.py SHA-256：2a827e3640f8c3515487756609816af4ce96216757498d9f97bbd1a5fdee1eee

## 尝试 9：x86 构建工具受到全局库变量影响（已修复）

总耗时 10 分 2 秒。x64 检查再次通过；x86 尚未链接应用，其 x64 主机构建脚本因全局 SODIUM_LIB_DIR 使用 Win32 库而失败。
已移除该全局变量，改用 Cargo 官方 target.<triple>.sodium links override，只为专用 Win7 目标提供锁定架构静态库路径；主机构建依赖保留默认 x64 库。未修改注册表缓存或公共依赖源。
8 个 Python 测试仍通过。原始日志保留于 /tmp/subnetdesk-win7-ci-logs/attempt-09.log。
- scripts/build_win7.py SHA-256：ee33bc4fa1742bbb96948fd733320cda5b0ec916191de4171e25322a6fa8b08e


## 尝试 10：两个架构构建与检查通过

固定 Rust 1.90 nightly、专用 Win7 target 和源码标准库构建，两种架构的软件原生依赖均通过 vcpkg 严格检查。主程序、服务和便携启动器全部构建成功。
每个架构对主程序、服务、Sciter DLL、便携 EXE、Sciter 冒烟 EXE 进行 PE 检查，全部通过；下载到本地后重新解析检查仍通过。
Windows 10 CI 设备上分别运行两个主程序 --version，退出码 0、输出 1.3.0；分别运行包内精确 DLL 的真实 Sciter 冒烟，值/索引、窗口、脚本分发与扩展行为事件检查通过。
最终产物与关键构建输入的本地/远程 SHA-256 一致。原始日志保留于 /tmp/subnetdesk-win7-ci-logs/attempt-10.log。

此结果不包含 Win7 SP1 实机、视频 thiscall、完整远程连接、服务生命周期、便携启动器解包/安装或最终 UI 一致性验收。无 Jenkins job/build number，不表述为 Jenkins job SUCCESS。
