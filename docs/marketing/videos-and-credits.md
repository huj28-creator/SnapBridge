# 素材、制作与授权

修订版 46 秒、1080×1920、30 fps。照片均为真实摄影作品；无 AI 生成照片或视频。平面动画和主持人“小桥”为原创程序绘制。

## 演示说明

iOS 模拟器使用公开示例照片作为摄像头输入，通过同一台 Mac 上的 localhost TLS，保留应用的实际接收、保存、剪贴板流程。Mac 原生窗口由 Apple ScreenCaptureKit 录制。单张与整组三张粘贴是实际剪贴板操作，目的地是本地演示笔记应用，未向云端发送图片。字幕已标示模拟器和示例照片；没有将演示动画作为真机速度测量。

录制夹具与用户实际应用使用不同的身份、目录和临时凭据。verify/original-byte-checks.json 记录 13 个收到的 JPEG，全部与公开源照片字节相同。学习提问和工程报告画面为用途说明，未伪造 AI 解答或工程诊断。照片人物和摄影师未为产品背书。

## 摄影素材

获取日期：2026-10-22。许可：[Unsplash License](https://unsplash.com/license)。图片有裁切、缩放、平移及组合，没有修改照片内容。

| 文件 | 摄影师 | 原作品页面 |
|---|---|---|
| workspace.jpg | JESHOOTS.COM | https://unsplash.com/photos/pUAM5hPaCRI |
| notes.jpg | Jakub Żerdzicki | https://unsplash.com/photos/1rm4_SojyNM |
| whiteboard.jpg | Centre for Ageing Better | https://unsplash.com/photos/wEcjmkYyeFI |
| circuit.jpg | Vishnu Mohanan | https://unsplash.com/photos/vtg8tAdoWVQ |
| math.jpg | Antoine Dautry | https://unsplash.com/photos/05A-kdOH6Hw |
| math-board.jpg | Artturi Jalli | https://unsplash.com/photos/gYrYa37fAKI |
| site.jpg | Scott Blake | https://unsplash.com/photos/x-ghf9LjrVg |

直接获取地址同时记录在 assets/photo-sources.json。

## 音乐

“Monkeys Spinning Monkeys” — Kevin MacLeod (incompetech.com).
Licensed under Creative Commons: By Attribution 4.0 License.

- 官方曲目：https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400011
- 许可说明：https://incompetech.com/music/royalty-free/licenses/
- CC BY 4.0：https://creativecommons.org/licenses/by/4.0/

截取、淡入淡出及配音避让，片尾和发布文案均署名。无音乐版另附。

## 配音与文字

合成配音采用用户选定的 zh-CN-XiaoxiaoNeural 晓晓女声，rate=+12%；不是用户录音或声音克隆。音频及逐词边界通过 edge-tts 获取：https://github.com/rany2/edge-tts

中文稿参考 Humanizer-zh 的具体动作、自然表达及去空泛套话原则，未复制示例文案：
- https://github.com/holygeek00/humanizer-zh-cn/blob/main/SKILL.md
- https://github.com/blader/humanizer/blob/main/SKILL.md

## 样式与录制研究

未复制付费模板。Pillow 与 FFmpeg 制作平面动画及分镜；设备框只是包裹实际原生录屏的外框，界面不是绘制的假截图。

- TikTok 官方 Creative Codes：https://ads.tiktok.com/business/library/TikTok_CreativeCodes_May2023.pdf
- Apple ScreenCaptureKit：https://developer.apple.com/documentation/screencapturekit

## 公开仓库

https://github.com/huj28-creator/SnapBridge

片尾二维码指向该公开仓库。iPhone 当前通过 Xcode 安装，不是 App Store 下载。
