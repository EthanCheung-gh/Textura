package textura.shell

import cui.*
import textura.ui.*

/*
 * `src/modules/appshell/ShortcutsDialog.tsx` + `.shortcuts*` (appshell.css:517-603).
 *
 * Modal 600px wide, title 快捷键. Groups of 4 gap; each group is a 12.5px/650 title, an
 * 11px faint scope line, then a two-column table (168px key column, 12.5px muted action)
 * with a 1px `--border` rule between rows and 10px vertical padding per row.
 */

public class ShortcutEntry {
    public let keys: Array<String>
    public let action: String

    public init(keys: Array<String>, action: String) {
        this.keys = keys
        this.action = action
    }
}

public class ShortcutGroup {
    public let title: String
    public let description: String
    public let items: Array<ShortcutEntry>

    public init(title: String, description: String, items: Array<ShortcutEntry>) {
        this.title = title
        this.description = description
        this.items = items
    }
}

/** The six groups from ShortcutsDialog.tsx:20-89, in order. */
public func shortcutGroups(): Array<ShortcutGroup> {
    let global: Array<ShortcutEntry> = [
        ShortcutEntry(["⌘/Ctrl", "K"], "打开 / 关闭命令面板"),
        ShortcutEntry(["⌘/Ctrl", "N"], "打开快速收集（收集到 GTD 收件箱；同时支持 ⌘/Ctrl + ⇧ + N）"),
        ShortcutEntry(["⌘/Ctrl", "Z"], "撤销上一次工作区修改"),
        ShortcutEntry(["⌘/Ctrl", "⇧", "Z"], "重做"),
        ShortcutEntry(["?", ], "打开快捷键帮助（Shift + /）"),
        ShortcutEntry(["Esc"], "关闭当前弹层")
    ]
    let palette: Array<ShortcutEntry> = [
        ShortcutEntry(["↑", "↓"], "移动高亮项"),
        ShortcutEntry(["Enter"], "执行选中命令 / 打开条目"),
        ShortcutEntry(["Tab"], "跳到下一个分组（⇧ + Tab 反向）"),
        ShortcutEntry(["Esc"], "关闭面板")
    ]
    let capture: Array<ShortcutEntry> = [
        ShortcutEntry(["Enter"], "收集并继续下一条"),
        ShortcutEntry(["⌘/Ctrl", "Enter"], "收集并关闭"),
        ShortcutEntry(["Esc"], "关闭收集窗口"),
        ShortcutEntry(["#标签", "@场景"], "写入 tags 与 gtd.context"),
        ShortcutEntry(["!高能", "!低能"], "写入 gtd.energy"),
        ShortcutEntry(["/今天", "/明天", "/本周"], "写入 gantt.end 截止日期")
    ]
    let gtdKeys: Array<ShortcutEntry> = [
        ShortcutEntry(["↑", "↓"], "移动行高亮"),
        ShortcutEntry(["x"], "完成当前行动"),
        ShortcutEntry(["Enter"], "打开澄清流程"),
        ShortcutEntry(["⌘/Ctrl", "Z"], "撤销（输入框内交给原生编辑）")
    ]
    let sopKeys: Array<ShortcutEntry> = [
        ShortcutEntry(["Delete", "Backspace"], "删除选中的节点或连线"),
        ShortcutEntry(["Esc"], "取消选中 / 退出运行 / 关闭分支选择"),
        ShortcutEntry(["⌘/Ctrl", "Z"], "撤销画布操作")
    ]
    let ganttKeys: Array<ShortcutEntry> = [
        ShortcutEntry(["拖拽"], "调整任务条形，修改起止日期"),
        ShortcutEntry(["Esc"], "取消拖拽"),
        ShortcutEntry(["Enter", "Space"], "选中当前任务（详情面板打开时同步）")
    ]
    let groups: Array<ShortcutGroup> = [
        ShortcutGroup("全局", "任何视图下都可用", global),
        ShortcutGroup("命令面板", "⌘/Ctrl + K 唤出", palette),
        ShortcutGroup("快速收集", "⌘/Ctrl + N 唤出，收集到 GTD 收件箱；收集后保持打开以便连续录入", capture),
        ShortcutGroup("GTD", "在收集 / 澄清 / 下一步视图中生效", gtdKeys),
        ShortcutGroup("SOP", "在 SOP 画布中生效", sopKeys),
        ShortcutGroup("甘特", "在甘特视图中生效", ganttKeys)
    ]
    groups
}

/** One row of the shortcuts table: 168px key column + wrapping action cell. */
func shortcutRow(tokens: ThemeTokens, entry: ShortcutEntry, first: Bool): Unit {
    let c = tokens.color
    if (!first) {
        Divider().foregroundColor(c.border)
    }
    HStack(spacing: vp(0.0)) {
        HStack(spacing: vp(4.0)) {
            for (key in entry.keys) {
                KeyChipView(tokens, key, style: KeyChipStyle.Shortcut)
            }
            Spacer()
        }
            .crossAxisAlignment(CrossAxisAlignment.Start)
            .hug()
            .width(168.0)
        Label(entry.action)
            .fontSize(Length(12.5, LengthUnit.Fp))
            .foregroundColor(c.textMuted)
            .wrap()
            .flex()
    }
        .hug()
        .fillWidth()
        .padding(0.0, 5.0, 0.0, 5.0)
}

/** Shortcuts help overlay (`.shortcuts`, group list of key tables). */
public func buildShortcutsDialog(host: ShellHost, theme: Theme, open: Bool): Unit {
    if (!open) {
        return
    }
    let tokens = tokensOf(theme)
    let c = tokens.color
    let presented = State<Bool>(true)
    Ui.modal(theme, presented, {=> host.closeShortcuts()}, title: "快捷键",
        description: "当前版本已生效的键盘操作，按视图分组。", width: 600.0, body: {=>
            VStack(spacing: vp(tokens.space.s4)) {
                for (group in shortcutGroups()) {
                    VStack(spacing: vp(tokens.space.s1)) {
                        // .shortcut-group-title { 12.5px; 650 }
                        Label(group.title)
                            .fontSize(Length(12.5, LengthUnit.Fp))
                            .fontWeight(FontWeight(650))
                            .foregroundColor(c.text)
                        // .shortcut-group-desc { 11px; faint }
                        Label(group.description)
                            .fontSize(Length(11.0, LengthUnit.Fp))
                            .foregroundColor(c.textFaint)
                            .wrap()
                        VStack(spacing: vp(0.0)) {
                            var first = true
                            for (entry in group.items) {
                                shortcutRow(tokens, entry, first)
                                first = false
                            }
                        }.hug().fillWidth().padding(0.0, 8.0, 0.0, 0.0)
                    }.hug().fillWidth()
                }
                Divider().foregroundColor(c.border)
                Label("快捷键会避开输入框：在文本框中输入时，字母类快捷键不会触发；撤销 / 重做在输入框内交给浏览器原生行为。")
                    .fontSize(Length(11.5, LengthUnit.Fp))
                    .foregroundColor(c.textFaint)
                    .wrap()
                    .padding(0.0, tokens.space.s3, 0.0, 0.0)
            }.hug().fillWidth()
        })
}
