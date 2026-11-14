# 在 Mac 上安装 ShotSkiff

最简单的方式是自动接收 iPhone 新截图；这个流程**不需要**在 iPhone 上安装 ShotSkiff。

## 下载与安装

1. 从 [GitHub Releases](https://github.com/huj28-creator/SnapBridge/releases/latest) 下载 Mac 版。
2. 打开 DMG，把 **ShotSkiff.app** 拖到 **Applications（应用程序）**快捷方式。
3. 在“应用程序”里双击 ShotSkiff。
4. 免费版本没有 Apple 公证。如果 macOS 提示无法验证开发者，在“应用程序”里按住 Control 点击 ShotSkiff，选“打开”，再确认一次。必要时先尝试打开一次，再到“系统设置 → 隐私与安全性 → 仍要打开”。不要关闭 Gatekeeper 或 SIP。

## 连接 iPhone 并接收截图

1. 用 USB 连接 iPhone，解锁手机。
2. 手机出现提示时，点“信任此电脑”并输入密码。
3. 打开 ShotSkiff 的“配对 iPhone / 设置”，按设备名称选择 iPhone。多台设备时请自行确认选对手机。
4. 截图功能需要 Python 3 和 Homebrew 的 `libimobiledevice`。ShotSkiff 会说明依赖；点击安装按钮前会先征求同意，然后才运行 `brew install libimobiledevice`。它不会偷偷安装 Homebrew。如果还没有 Homebrew，请先从 [brew.sh](https://brew.sh) 安装，重新打开 ShotSkiff，再点“刷新 iPhone”。
5. 点“启用截图导入”。已有照片会跳过，只监测之后的新截图。
6. 按 iPhone 侧边键和音量加键截图。保存完成后，图片会出现在 Mac 浮窗。

首次通过 USB 信任后，设备可用时也能尝试通过已信任的 Wi-Fi 连接读取；并非所有网络或设备状态都支持。找不到手机时可改用 USB。

## 复制、粘贴和存储

点击“复制”，在目标应用按 ⌘V，或直接拖动图片。连续收到的图片会放在同一个窗口里；目标应用是否支持一次粘贴多张图片由目标应用决定。每次收图都会替换 Mac 剪贴板。

收件箱位于 `~/Library/Application Support/SnapBridge/Inbox`，最多保留 20 张由应用管理的图片；超出后最旧图片会被永久删除。图片不会上传到云端。截图监测仅读取你明确选择的、已信任 iPhone 的新截图。使用应用内相机需要额外安装 iPhone 伴侣，请看[高级安装指南](install-iphone-zh.md)。

在设置里点击“暂停导入”即可停止自动截图导入。卸载前请参阅[卸载说明](uninstall-zh.md)。

## 常见问题

- **找不到 iPhone：** 解锁手机、重新插线、按提示点“信任此电脑”，再点“刷新 iPhone”。
- **没有信任提示：** 解锁后重新连接。只有确实需要时才重置 iPhone 的“位置与隐私”设置；这会影响其他电脑的信任记录。
- **截图没有出现：** 检查是否启用、是否选对设备、Python 3 和 `libimobiledevice` 是否安装，重新连接并刷新设备。
- **Wi-Fi 不可用：** 使用 USB。Wi-Fi 依赖 Apple 已建立的可信设备连接，可能暂时无法连接。
- **传输变慢：** 手机锁定、照片图库繁忙或无线连接状态可能造成延迟；完整 PNG 收到后才能复制原图。
- **相机伴侣断连：** 在手机和 Mac 打开伴侣并允许本地网络访问，确认两台设备在本地网络可达。Mac 会自动重连。
- **目标软件不接受多图粘贴：** 目标软件可能不支持剪贴板多文件；可从组合窗口逐张拖动。

## 相机伴侣

先安装 Mac 接收端，再看[免费安装 iPhone 伴侣](install-iphone-zh.md)。需要 Xcode 和 Apple 账号。免费个人团队签名每七天过期；自动刷新为可选功能，受前置条件影响，iOS 仍可能要求重新信任。
