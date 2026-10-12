# OpenAnki iOS

用 Swift / SwiftUI 编写的独立离线闪卡应用，支持 iPhone 和 iPad，最低 iOS 17。无需账号或联网。

## 运行

用 Xcode 打开 `OpenAnkiIOS.xcodeproj`，选择 `OpenAnkiIOS` scheme 和 iOS 模拟器，点击 Run。首次构建通过 Swift Package Manager 下载 ZIPFoundation 和 Zstandard；安装后的应用完全离线运行。真机运行需在 Signing & Capabilities 中选择你的开发团队。

CLI 构建：

```sh
xcodebuild -project OpenAnkiIOS.xcodeproj -scheme OpenAnkiIOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

## 已实现

- 新建、重命名和删除牌组，选择图标与颜色。
- 添加、编辑、搜索、筛选、移动、暂停、删除卡片，添加反向卡片。
- 四档评分、学习和重新学习步骤、到期队列、每日新卡片额度、撤销最近一次评分。
- 本地保存复习进度，七天统计、连续学习天数、回忆率、学习时间。
- 导入 `.apkg`（旧版 `.anki2` / `.anki21`、新版 Zstandard `.anki21b`）、UTF-8 CSV/TSV。
- 常见 Anki 模板、条件字段、反向卡片、填空、振假名、提示、CSS、离线图片和音频。
- `.openanki` 完整备份与恢复，包括牌组、学习进度、设置和媒体。
- 浅色 / 深色模式，iPad 布局，键盘快捷键（空格显示答案，1–4 评分）。

首次运行包含三个可删除的示例牌组，统计从零开始。

## 导入说明

在桌面 Anki 导出 `.apkg`，将文件保存到 iOS「文件」，点击应用中的导入按钮。也可以从「文件」的分享菜单用 OpenAnki 打开牌组。

同名牌组合并；相同笔记 GUID + 卡片序号去重，重复导入保留已有学习进度，不更新已有卡片内容。Anki 导入卡片从新卡片开始，保留暂停状态，不迁移 Anki 的复习历史。

文本格式：前两列为正面和背面，第三列为可选标签（用空格分隔）。CSV 支持引号与多行字段，TSV 使用制表符；支持 Anki 文件头 `#separator`、`#html`、`#deck`。

恢复 `.openanki` 备份会替换当前集合，应用会要求确认。恢复前建议先导出当前备份。读取原集合失败时不会重新创建或覆盖数据；保存失败时不会推进复习。媒体先安装，再原子提交集合。

支持范围：这是 Swift 实现的独立应用，复习算法采用 SM-2 风格，未集成 Anki 的 Rust 后端或 FSRS。导入模板会渲染成独立卡片；编辑一张卡片不会连带修改同笔记的其他卡片。图像遮挡、自定义 JavaScript、MathJax、外部网络资源、AnkiWeb 同步和 `.colpkg` 暂未实现。依赖这些功能的复杂模板需要先在桌面版调整。

导入大小限制：每个集合解压后 256 MB、单个媒体 64 MB、媒体总大小 1 GB、单包 100,000 张卡片和 20,000 个媒体文件。

## 代码结构

- `OpenAnkiIOS/`：SwiftUI 页面、Observation 数据状态、离线 WebKit 卡片显示。
- `Core/`：可独立测试的 Swift Package，包含模型、调度、原子保存、导入、模板和备份。
- `Config/Info.plist`：`.apkg` / `.openanki` 文件类型注册。
- `OpenAnkiIOSUITests/`：模拟器交互测试。

文件格式参考相邻的 `../anki` 源码中的 schema、模板与包格式定义；未修改桌面 Anki 工程。依赖固定为 [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/tree/0.9.20)（MIT）和 [Zstandard 1.5.7](https://github.com/facebook/zstd/tree/v1.5.7)（BSD / GPL 双许可证）。

## 验证

本机验证通过：Xcode 26 的 iOS 模拟器 Debug 构建、iOS 真机目标 Release 编译（未签名）、12 项核心测试、4 项模拟器界面测试。用户提供的 `N4.apkg` 实测导入 2,216 张卡片与 1,100 个媒体文件，完成完整备份往返验证，并在 iPad Pro 模拟器实际导入。原始牌组文件未修改，也未加入仓库。

```sh
swift test --package-path Core

# 可选：额外验证本机真实牌组的导入、媒体和完整备份往返
OPENANKI_TEST_APKG=/path/to/deck.apkg swift test --package-path Core

xcodebuild -project OpenAnkiIOS.xcodeproj -scheme OpenAnkiIOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

固定的测试牌组是原创小样本，包含旧版 / 新版包、反向、填空、图片、音频和无效媒体路径。Python fixture 生成脚本仅用于更新样本，构建与测试无需 Python。UI 测试使用独立测试目录，不影响正常运行的牌组。
