# iOS 实验版：自签安装

Release 中的 `subnetdesk-<版本>-ios-arm64-unsigned.ipa` 是未签名的实验版，需要用自己的 Apple 账号重新签名后安装。它面向 ARM64 iPhone / iPad，项目最低系统版本为 iOS / iPadOS 15；自签工具可能要求更高版本。IPA 不能直接点击安装，也不能安装到 iOS 模拟器。

iOS 版本目前作为控制端连接其他设备，不支持将 iPhone / iPad 作为被控端。构建成功不代表已通过真机验证，连接、画面、触控和键盘输入仍需要在实际设备上测试。

## 使用 Sideloadly 安装

1. 从本项目对应版本的 Release 下载 `subnetdesk-<版本>-ios-arm64-unsigned.ipa`。
2. 在 Mac 或 Windows 上从 [Sideloadly 官网](https://sideloadly.io/) 安装工具，并按其说明安装系统所需组件。
3. 用 USB 连接 iPhone / iPad，解锁设备，并在提示时选择“信任此电脑”。
4. 在 Sideloadly 中选择设备，拖入 IPA，输入用于自签的 Apple 账号，按提示完成认证、签名和安装。账号信息只在你选择的签名工具中处理，无需提供给 SubnetDesk 项目。
5. 如果系统提示开发者未受信任，在“设置 → 通用 → VPN 与设备管理”中信任自己的开发者账号；菜单名称可能随系统版本不同。
6. iOS / iPadOS 16 及以上如提示需要开发者模式，在“设置 → 隐私与安全性 → 开发者模式”中开启，按提示重启并确认。参见 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
7. 打开 SubnetDesk，尝试连接局域网内的电脑，并允许“本地网络”访问。如果首次授权后连接失败，授权完成后重试。

也可以通过 [AltStore Classic / AltServer](https://faq.altstore.io/altstore-classic/altserver) 导入 IPA 并签名安装；请按所用工具的官方说明操作。

## 签名有效期与更新

免费 Apple 账号签名的应用通常在 7 天后失效，需要在到期前重新签名或使用工具的刷新功能；免费账号也有同时安装的应用数量限制。有效期以签名工具和设备上的实际结果为准。参见 [Sideloadly 说明](https://sideloadly.io/) 和 [AltStore 刷新说明](https://faq.altstore.io/altstore-classic/your-altstore)。

更新时使用相同 Apple 账号和相同 Bundle ID 签名，通常可以覆盖安装。不要为续签先卸载应用；卸载或更换签名身份、Bundle ID 可能导致原有配置无法保留。项目原始 Bundle ID 为 `com.zibochen.subnetdesk`，签名工具可能需要调整它。

## 局域网权限与设备发现限制

手机和目标电脑需要处于可以互通的网络，目标电脑需运行 SubnetDesk 并允许连接。出现本地网络授权提示时选择允许；如果之前拒绝，可在“设置 → 隐私与安全性 → 本地网络”中重新开启 SubnetDesk 权限。访客 Wi-Fi 的客户端隔离、防火墙或 VPN 路由也可能阻止连接。

目前 iOS 设备发现使用 UDP 广播，没有接入桌面端的 mDNS 浏览。Apple 要求 iOS 真机的 UDP 广播 / 组播使用包含 `com.apple.developer.networking.multicast` 的有效签名及 provisioning profile。普通免费账号自签不保证具备该权限，因此实验版不保证自动发现可用；列表为空时，请手动输入目标电脑的 IP 地址和端口，默认连接端口为 `21118`。允许“本地网络”访问并不等于获得广播 / 组播权限。参见 [Apple 本地网络隐私说明](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) 和 [网络 API 说明](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)。

当前工程只声明连接所需的本地网络用途，没有申请推送通知、Wi-Fi 信息或受限的 multicast entitlement，也没有声明未使用的 Bonjour 服务。需要验证广播发现的开发者，应先取得对应能力并配置匹配的签名 profile，再自行构建和签名；仅在 entitlement 文件中添加一个键不能获得该权限。

## 构建与打包

CI 先编译 `aarch64-apple-ios` 的 Rust 静态库，再执行 `flutter build ios --release --no-codesign`，最后用 `scripts/package_unsigned_ios.sh` 将真机 `.app` 打包为 `Payload/Runner.app` 结构的 IPA。脚本在临时副本上移除已有签名和 provisioning profile，不修改原始构建目录。`flutter build ipa --no-codesign` 会跳过 IPA 导出，因此这里单独打包。

实验版 IPA 和本说明同时附在 Release 中；IPA 文件名中的 `unsigned` 表示项目没有提供可直接安装的分发签名。遇到问题时，请附上版本、设备型号、iOS 版本、签名工具版本，以及发生在安装、启动、发现还是连接阶段；提交日志前请删去账号和其他敏感信息。
