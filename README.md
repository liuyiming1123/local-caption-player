# 实时字幕播放器

macOS 本地视频播放器：播放时从原始音轨提前识别字幕，根据视频时间显示；支持保存文字、本机备份、实时识别回退和 Liquid Glass 控件。控制栏播放时在鼠标静止约 3 秒后隐藏。

## 要求

- macOS 26 或更新版本，Xcode 及命令行工具。
- 苹果 SpeechAnalyzer 对所选语言的本机识别模型可用并已安装。实时识别模式还需要语音识别、屏幕与系统音频录制权限。
- 播放格式取决于系统 AVFoundation。视频和转写文字不会上传。

## 构建与测试

```sh
./test.sh
./build.sh
open "build/实时字幕播放器.app"
```

构建脚本使用临时签名，仅适合本机试用；系统隐私授权可能在重新签名后需要重新设置。首次打开视频时默认使用原音识别，切换识别语言后可在“字幕”菜单重新开始识别。字幕文稿保存于 `~/Documents/播放器字幕`；识别备份保存在 `~/Library/Application Support/实时字幕播放器/转录备份`，不会自动删除。

## 限制

自动识别可能缺字、错字或时间偏差；原音预识别可包含尚未观看的部分。未识别完的内容不会出现在文档中。快进、拖动、长视频、高倍速及各种视频格式的覆盖范围仍需更多真实文件验收。生成的文件是转写，不是摘要或人工校对稿。

## 来源

播放、语音识别和玻璃界面使用 Apple AVKit、Speech、SwiftUI 和 ScreenCaptureKit。音频缓冲区转换参考 [SubtitleOverlay](https://github.com/SweelLong/SubtitleOverlay)，许可见 `Sources/SubtitleOverlay-LICENSE.txt`。项目此前也调研过 [IINA](https://github.com/iina/iina)，但未集成其代码或播放引擎。
