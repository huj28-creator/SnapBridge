# 安装高级 iPhone 相机伴侣

iPhone 伴侣是可选的。Mac 截图功能直接使用 iPhone 的普通截图按键，不需要安装 iPhone 应用。

## 要求与签名限制

- macOS 14 或更新版本的 Mac，并安装 Apple 官方 Xcode。
- iOS 17 或更新版本。
- 在 Xcode → Settings → Accounts 登录 Apple 账号。
- 免费个人团队可以签名，但开发描述文件七天后过期。无需购买每年 99 美元的开发者会员；不过这不是 App Store 安装，免费签名有期限。
- 可尝试使用已有的自动续期脚本，但要求 Xcode 账号、原签名证书和配对手机都可用。Apple 仍可能要求手动操作或重新信任，不能保证自动续期总能成功。

## 安装

1. 安装并首次打开 Xcode。
2. 在 Xcode → Settings → Accounts 登录 Apple 账号，等个人团队加载完成。不要把账号密码或验证码输入 ShotSkiff、脚本或聊天。
3. 用 USB 连接并解锁目标 iPhone，按提示点“信任此电脑”。如果 iOS 要求开启开发者模式，按系统提示重启并确认。
4. 从 GitHub 下载源码并打开 `SnapBridge.xcodeproj`。选择 **SnapBridgePhone** 和正确设备。在“Signing & Capabilities”里选自己的 Personal Team 和唯一 Bundle ID。后续刷新要保持团队和 Bundle ID 不变，才能保留应用数据和配对。
5. 在 Xcode 运行 iPhone 目标。允许相机和本地网络访问。打开 Mac 版 ShotSkiff，用其显示的一次性代码配对。
6. 也可运行仓库中的 `scripts/install_phone.py`。它会检测已连接设备；多台手机时不会擅自选择。脚本使用 Xcode 的账号，不会询问你的密码。

## 可选续期

双击 **Refresh iPhone.command**，通过 Xcode 在原应用上刷新。不要先删除手机应用。自动续期助手见 [`renewal.md`](renewal.md)；本地测试验证的是安全检查，不代表 Apple 在线续期服务必然可用。安装后检查签名到期日和续期日志。失败时连接并解锁手机，用 Xcode 手动刷新。续期失败后，免费签名仍会过期。

## 限制

Apple 没有提供让 ShotSkiff 在 iOS 后台静默接受“信任开发者”提示的接口。应用不能替你自动点手机上的信任确认。安装和签名仍由 Apple 的开发工具及规则决定。
