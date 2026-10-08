这是 SubnetDesk 的 Win7 Sciter 测试版，提供 x64 和 x86 两种架构。

使用 Rust 1.90 nightly 和专用 Win7 target，复用当前 LAN 后端。首页、LAN 设置和账号/身份管理已按 Flutter 界面调整。

下载：
- win7-x64.exe / win7-x86.exe：便携启动器。
- win7-x64.zip / win7-x86.zip：包含主程序、服务、Sciter DLL 和第三方许可。解压后运行 rustdesk.exe。
- imports.json：PE 导入检查报告。
- SHA256SUMS.txt：下载文件校验值。

两个架构均由本次 GitHub Actions 从同一提交构建。原生依赖、主程序、服务及便携启动器编译，Sciter ABI 冒烟、主程序启动和 PE 检查通过。

这是测试版：尚未完成 Win7 SP1 实机、完整远程会话、服务安装/卸载和便携解包验收。远程工具栏、文件传输及连接管理器尚未完成与 Flutter 的完整对齐。
欢迎反馈系统版本、架构、复现步骤及日志。
