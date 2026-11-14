# 卸载 ShotSkiff

1. 在菜单栏图标菜单中选择“退出 ShotSkiff”。
2. 从“应用程序”文件夹删除 `ShotSkiff.app`。
3. 可选：删除 `~/Library/Application Support/SnapBridge/Inbox`，这会永久删除最多 20 张已接收图片。先导出想保留的文件。
4. 可选：删除 `~/Library/Application Support/SnapBridge`，移除截图设备选择及诊断/续期状态；这不会清除 Mac 钥匙串中的相机配对记录。
5. 要清除相机配对，请在卸载前打开 ShotSkiff，选择“更改已配对 iPhone… → 重置配对”。这会主动撤销已信任的手机。
6. 可选：按 [`renewal.md`](renewal.md) 中的说明停用续期助手。不要随意删除其他应用也在使用的 Xcode 或 Homebrew。

这不会修改 ShotSkiff 之外的 iPhone 照片，也不会自动卸载 iPhone 伴侣。如需卸载，请在手机上另行删除。
