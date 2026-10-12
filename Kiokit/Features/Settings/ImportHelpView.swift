import SwiftUI
import KiokitCore

struct ImportHelpView: View {
    @Environment(CollectionStore.self) private var store
    var body: some View {
        List {
            Section(store.text("从桌面 Anki 导入")) {
                Text(store.text("1. 在 Anki 桌面版选择牌组，导出为 .apkg。\n2. 通过 AirDrop 或其他方式将文件保存到 iPhone / iPad 的「文件」。\n3. 在 Kiokit 点击导入，选择该文件。"))
                Text(store.text("支持旧版 .anki2 / .anki21 和新版 .anki21b 包，支持常见正反面、反向、填空、模板样式及离线图片和音频。"))
                Text(store.text("导入使用 Anki 的原生选项，保留笔记字段、模板和支持的复习记录。重复处理、牌组合并和媒体重命名均由 Anki 执行。"))
            }
            Section(store.text("文本导入")) {
                Text(store.text("UTF-8 编码，前两列为正面和背面，第三列为可选标签。CSV 支持带引号的逗号和换行；TSV 使用制表符分隔。可识别 Anki 的 #separator、#html 和 #deck 文件头。"))
            }
            Section(store.text("如何复习")) {
                Text(store.text("先回想，再显示答案。根据回忆情况选择重来、困难、良好或简单。按钮上显示下次复习间隔，可撤销最近一次评分。"))
                Text(store.text("学习步长、SM-2 或 FSRS 间隔、随机扰动及遗忘处理使用 Anki 的设置。按钮显示后端实际生成的间隔，学习队列遵循 Anki 的优先级和混排规则。"))
            }
            Section(store.text("备份与支持范围")) {
                Text(store.text(".colpkg 是 Anki 原生完整备份，恢复时会替换当前牌组。旧版 .openanki 文件会先迁移为 Anki 数据；原始数据保留。"))
                Text(store.text("导入不会修改原始文件。模板由 Anki 渲染，离线 JavaScript 可以执行；设备渲染支持范围仍在对照上游验证。"))
            }
        }.ankiForm().font(.subheadline).navigationTitle(store.text("使用说明")).navigationBarTitleDisplayMode(.inline)
    }
}
