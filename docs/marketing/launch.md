# Launch copy drafts — ShotSkiff

## English launch announcement

I built ShotSkiff because moving a quick iPhone screenshot into whatever I was doing on my Mac felt like too many steps.

Now I can take a screenshot with the regular iPhone buttons and have it appear on my Mac, ready to paste or drag. Several screenshots can stay together in one preview too.

It is free and open source. The Mac screenshot workflow is the simplest place to start; it needs an existing trusted iPhone connection plus Python 3 and `libimobiledevice`. The optional camera companion has its own Xcode setup because free Apple signing expires after seven days.

Download and source: https://github.com/huj28-creator/SnapBridge

## 中文发布文案

平时在电脑上写作业、看资料、用 ChatGPT 或做项目，经常得把 iPhone 截图再弄到 Mac 上。

所以我做了 ShotSkiff：照常按手机截图键，图片就会出现在 Mac 浮窗里，直接复制或拖进去。连续截几张还能放在一个窗口里整理。

免费开源。Mac 截图版最容易上手，但首次需要信任 iPhone，并安装 Python 3 和 `libimobiledevice`。想用应用内相机拍照，还可以安装可选的 iPhone 伴侣；免费 Apple 签名七天过期，需要定期刷新。

下载和源码：https://github.com/huj28-creator/SnapBridge

## Show HN draft

Show HN: ShotSkiff — local iPhone screenshots and photos straight to a Mac clipboard

I built ShotSkiff to cut the steps between taking a screenshot on my iPhone and using it in a Mac app. The Mac receiver reads new screenshots from an explicitly selected, already trusted iPhone connection and shows them in a floating preview. A separate optional iPhone companion captures camera photos over authenticated encrypted local transport. Successive images can be grouped and copied together, subject to the destination app's clipboard support.

It is MIT licensed and has no cloud upload or telemetry. The free Mac DMG is ad-hoc signed, not notarized. Screenshot setup currently needs Python 3 and Homebrew libimobiledevice. The optional iPhone app uses free Xcode Personal Team signing, which expires after seven days. Feedback welcome: https://github.com/huj28-creator/SnapBridge

## Reddit draft A — Mac apps / productivity

I made a small open-source Mac utility for the screenshot handoff I kept repeating. Take a screenshot on iPhone with the usual buttons, then it appears in a floating Mac window where you can paste or drag it. Consecutive images join a group. It reads from a specifically trusted phone, locally; no cloud upload. Setup needs Python 3 and libimobiledevice, so it is not a zero-dependency install yet. Here is the Mac DMG and setup guide: [release](https://github.com/huj28-creator/SnapBridge/releases) · [guide](https://github.com/huj28-creator/SnapBridge/blob/main/docs/install-mac.md). Curious what would make the setup clearer.

## Reddit draft B — iOS development / students

ShotSkiff is a free MIT Mac receiver I built for getting iPhone screenshots into desktop notes, reports, and AI chats without messaging them to myself. It uses the normal screenshot buttons; the native camera path is optional and needs an Xcode-signed iPhone companion. I have tried to document the free-signing limitations honestly. Current release supports Apple Silicon and macOS 14+. Feedback/issues: https://github.com/huj28-creator/SnapBridge

Post only where the community rules allow self-promotion; edit each submission for the community and do not cross-post the same copy.

## Product Hunt listing draft

- Name: ShotSkiff
- Tagline: From your iPhone. Straight to your Mac.
- Description: Take a screenshot or photo on iPhone and use it immediately on Mac. Floating previews, drag-and-drop, and grouped image clipboard. Free and MIT licensed, with local transfer and no cloud account.
- First comment: I made ShotSkiff for the small but constant friction of moving phone screenshots into desktop work. The Mac screenshot path uses normal iPhone buttons, though first-time setup still needs an existing trusted device connection and helper tools. The optional camera companion is installed through Xcode and free signing expires after seven days. I would love feedback on the onboarding.
- Topics: Productivity, Developer Tools, Mac, Open Source

## Chinese short-video metadata

1. 标题：iPhone 截图，直接出现在 Mac 上｜ShotSkiff 免费开源
   描述：不用发微信再下载。照常截图，Mac 上就能预览、复制或拖动。Mac 截图导入需信任手机及辅助工具；相机功能需额外安装 iPhone 伴侣。演示手机画面为模拟器录制，不是传输速度测试。
2. 标题：连拍几张，Mac 一个窗口一起整理
   描述：连续收到的图片会合并成组，可放大查看、整组复制或逐张拖动。能否批量粘贴取决于目标软件。ShotSkiff 免费开源，下载与安装要求见 GitHub。
3. 标题：拍题、实验接线、项目记录，手机拍完电脑接着用
   描述：iPhone 截图或拍照后，把图片带进笔记、文档、报告或聊天窗口。截图版不需要自制 iPhone 应用；应用内相机是可选高级功能。具体要求见安装指南。

## Bilibili description

ShotSkiff：iPhone 截图/照片直接到 Mac，支持浮窗预览、复制粘贴、拖拽和连续图片分组。免费 MIT 开源，不上传云端。Mac 截图版需要信任 iPhone 及 Python 3、libimobiledevice；相机伴侣需要 Xcode，免费开发签名七天到期。

视频中的 iPhone 操作来自模拟器，真实 Mac 接收器和本地剪贴板流程经过录制；没有把模拟器当成真机速度测试。音乐、摄影素材和配音来源详见视频项目的 SOURCES-AND-LICENSES.md。源码与下载：https://github.com/huj28-creator/SnapBridge

## Pinned GitHub announcement

ShotSkiff v0.1.0 is available for Apple Silicon Macs. Use the normal iPhone screenshot buttons; new screenshots appear in a floating Mac preview ready to copy or drag. See the [DMG and checksum](https://github.com/huj28-creator/SnapBridge/releases/tag/v0.1.0), [English Mac guide](docs/install-mac.md), [中文指南](docs/install-mac-zh.md), and [optional iPhone camera companion setup](docs/install-iphone.md). The camera companion uses free Xcode signing that expires after seven days. Please report bugs without attaching private photos, pairing codes, or device IDs.

## Feature snippets

- **Screenshots:** Your usual iPhone screenshot buttons, then a Mac preview. No custom iPhone app for this path.
- **Camera:** Optional native iPhone camera companion sends original JPEG bytes over encrypted local transfer.
- **Groups:** Keep successive shots together, enlarge individual thumbnails, or copy image attachments together where supported.
- **Local:** No ShotSkiff account or photo cloud. The app-managed Mac inbox holds at most 20 files.
- **Open source:** MIT license, public source and issues on GitHub.

## Keywords

iPhone screenshot to Mac, Mac screenshot importer, local photo transfer, iPhone Mac clipboard, grouped image paste, iOS developer workflow, student notes, open source Mac utility, privacy-first photo workflow, ShotSkiff.

## Accounts and publication status

These are drafts only. Do not post to Reddit, Hacker News, Product Hunt, Douyin, Xiaohongshu, Bilibili, or YouTube without the account owner's session and platform-specific review. No third-party account posting is authorized by access to the source repository alone.
