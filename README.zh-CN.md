<p align="center">
  <img src="res/subnetdesk-icon.svg" alt="SubnetDesk 图标" width="120">
</p>

<h1 align="center">SubnetDesk</h1>

<p align="center">
  <strong>面向局域网的远程桌面：连接直接、部署简单、数据路径可控。</strong>
</p>

<p align="center">
  基于 <a href="https://github.com/rustdesk/rustdesk">RustDesk</a> 独立维护，适用于局域网、可路由私网与 VPN。
</p>

<p align="center">
  <a href="https://github.com/zibo-chen/SubnetDesk/releases/latest"><img src="https://img.shields.io/github/v/release/zibo-chen/SubnetDesk?style=flat-square&logo=github&color=2563eb" alt="最新版本"></a>
  <a href="https://github.com/zibo-chen/SubnetDesk/releases"><img src="https://img.shields.io/github/downloads/zibo-chen/SubnetDesk/total?style=flat-square&logo=github&color=0ea5e9" alt="累计下载量"></a>
  <a href="https://github.com/zibo-chen/SubnetDesk/stargazers"><img src="https://img.shields.io/github/stars/zibo-chen/SubnetDesk?style=flat-square&logo=github&color=f59e0b" alt="GitHub Stars"></a>
  <a href="https://github.com/zibo-chen/SubnetDesk/network/members"><img src="https://img.shields.io/github/forks/zibo-chen/SubnetDesk?style=flat-square&logo=github" alt="GitHub Forks"></a>
  <a href="https://github.com/zibo-chen/SubnetDesk/actions/workflows/subnetdesk-preflight.yml"><img src="https://img.shields.io/github/actions/workflow/status/zibo-chen/SubnetDesk/subnetdesk-preflight.yml?branch=master&style=flat-square&label=build" alt="构建状态"></a>
  <a href="LICENCE"><img src="https://img.shields.io/github/license/zibo-chen/SubnetDesk?style=flat-square&color=16a34a" alt="开源许可"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-x64%20%7C%20ARM64-0078D6?style=flat-square&logo=windows11&logoColor=white" alt="Windows">
  <img src="https://img.shields.io/badge/macOS-Intel%20%7C%20Apple%20Silicon-111111?style=flat-square&logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/Linux-x86__64%20%7C%20ARM64-FCC624?style=flat-square&logo=linux&logoColor=111111" alt="Linux">
  <img src="https://img.shields.io/badge/Android-APK-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android">
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

<p align="center">
  <a href="#why-subnetdesk">项目定位</a> ·
  <a href="#features">主要功能</a> ·
  <a href="#download">下载安装</a> ·
  <a href="#quick-start">快速开始</a> ·
  <a href="#build-from-source">源码构建</a>
</p>

<p align="center">
  <img src="assets/screenshots/device-discovery.png" alt="SubnetDesk 局域网设备发现" width="880">
</p>

<a id="why-subnetdesk"></a>

## 💡 为什么选择 SubnetDesk

SubnetDesk 专注于一个明确场景：让本身已经网络互通的设备直接进行远程控制。项目移除了 RustDesk 中的公网设备 ID、信令、中继、云账号、代理和公网自动更新等路径，改为直接连接目标地址，并自动发现局域网设备。

它适合家庭实验室、办公室、教室、现场运维，以及通过 WireGuard、Tailscale、OpenVPN 等 VPN 互通的私有网络。

| | SubnetDesk | 典型 RustDesk 部署 |
| --- | --- | --- |
| 连接方式 | 直接连接 IP 地址或主机名 | 通过设备 ID 和信令服务连接，可使用中继 |
| 设备发现 | 局域网 mDNS 自动发现 | 设备 ID 或地址簿 |
| 服务依赖 | 无需协调服务器 | 设备 ID 连接通常需要公网或自建信令/中继服务 |
| 适用场景 | 局域网、可路由私网、VPN | 互联网和跨 NAT 访问 |

> [!IMPORTANT]
> SubnetDesk 不提供公网信令或中继服务。两台设备必须位于同一局域网、可路由的私有网络，或通过 VPN 实现网络互通。

<a id="features"></a>

## ✨ 主要功能

| | 功能 | 说明 |
| --- | --- | --- |
| 🔎 | 局域网发现 | 通过 mDNS 自动发现附近设备。 |
| ⚡ | 地址直连 | 使用 IP 地址或主机名直接连接，TCP 端口可配置。 |
| 🔐 | 访问认证 | 使用用户名和密码保护访问，密码以 Argon2id 哈希保存。 |
| 🛡️ | 设备验证 | 首次连接时核对并保存设备指纹，降低误连风险。 |
| 🌐 | 网络白名单 | 通过 CIDR 网段限制允许接入的来源网络。 |
| ⭐ | 快速重连 | 保存最近设备、收藏与稳定设备身份。 |
| 🖥️ | RustDesk 体验 | 保留远程控制、剪贴板、音频和文件传输等能力，无需公网协调服务器。 |

<a id="download"></a>

## 📦 下载安装

稳定版本请前往 **[GitHub Releases](https://github.com/zibo-chen/SubnetDesk/releases/latest)** 下载。希望体验最新改动时，可以使用 **[Nightly 版本](https://github.com/zibo-chen/SubnetDesk/releases/tag/nightly)** 或 **[GitHub Actions](https://github.com/zibo-chen/SubnetDesk/actions)** 中的构建产物。

| 平台 | 架构 | 安装包 |
| --- | --- | --- |
| Windows | x86_64、ARM64 | `.msi` 安装包（推荐优先使用）、免安装/便携版 `.exe` |
| macOS | Intel、Apple Silicon | `.dmg` |
| Linux | x86_64、ARM64 | `.deb`、`.rpm`、`.AppImage`、`.flatpak`；另提供 x86_64 Arch 包 |
| Android | ARM64、ARMv7、x86_64、通用包 | `.apk` |

> [!NOTE]
> Nightly 属于开发构建，日常使用建议优先选择最新稳定版本。

<a id="quick-start"></a>

## 🚀 快速开始

1. 在两台设备上安装并打开 SubnetDesk。
2. 在被控端打开 **LAN 设置**，设置用户名和密码，并开启局域网发现。默认端口为 `21118`。
3. 在控制端选择已发现的设备，或手动输入 `主机名:端口` / `IP:端口`。
4. 首次连接时核对设备指纹，确认无误后发起连接。

<p align="center">
  <img src="assets/screenshots/lan-settings.png" alt="SubnetDesk LAN 设置" width="880">
</p>

### 网络检查清单

- 两台设备之间路由可达。
- 主机防火墙已允许 TCP `21118` 端口，或你自行配置的端口。
- 自动发现需要网络支持 mDNS；即使 mDNS 不可用，仍可手动输入地址直连。
- 被控端的 CIDR 白名单包含控制端所在网段。
- Linux 用户可查看[主机环境说明](docs/linux-host-readiness.md)，了解 SELinux、Wayland 与登录界面的注意事项。

## 🔒 安全模型

- 数据沿设备之间的可达网络路径传输，不依赖公网协调服务。
- 密码使用 Argon2id 哈希保存，不以明文持久化。
- 设备指纹采用首次使用信任机制，可帮助识别目标设备身份的异常变化。
- CIDR 白名单可限制被控端接受连接的来源网络。

与其他远程控制软件一样，请只向可信网络开放监听端口，使用高强度且不重复的密码，并尽可能通过另一条可信渠道核对设备指纹。

<a id="build-from-source"></a>

## 🛠️ 从源码构建

拉取仓库及其子模块，然后执行 Flutter 桌面端构建：

```bash
git clone --recurse-submodules https://github.com/zibo-chen/SubnetDesk.git
cd SubnetDesk
./build.py --flutter --hwcodec
```

构建需要 Rust、Flutter 和对应平台的原生依赖。固定工具版本、目标架构和完整打包步骤以[原生安装包工作流](.github/workflows/flutter-build.yml)为准。

## 🤝 参与贡献

欢迎提交缺陷报告、功能建议和 Pull Request。开始修改前建议先查看现有 [Issues](https://github.com/zibo-chen/SubnetDesk/issues)，并尽量让改动保持聚焦，符合项目面向局域网与 VPN 的产品定位。

## 💬 交流社区

<p align="center">
  <a href="https://discord.gg/MFZG478wPQ">
    <img src="https://img.shields.io/badge/Discord-加入交流社区-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="加入 SubnetDesk Discord 交流社区">
  </a>
</p>

<p align="center">
  欢迎加入 <a href="https://discord.gg/MFZG478wPQ">SubnetDesk Discord 交流社区</a>。也可以扫描下方二维码添加我的微信，备注 <strong>SubnetDesk</strong>，我会拉你进入微信交流群。
</p>

<p align="center">
  <img src="assets/community/wechat-contact.jpg" alt="添加 czb 微信，加入 SubnetDesk 交流群" width="360">
</p>

## 🙏 致谢与许可

SubnetDesk 基于 [RustDesk](https://github.com/rustdesk/rustdesk) 开发并保留其开源基础。本项目独立维护，并非 RustDesk 官方发行版。

项目采用 [GNU Affero General Public License v3.0](LICENCE) 许可。请仅在自己拥有或已获授权的设备上使用远程控制功能。
