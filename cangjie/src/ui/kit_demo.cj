package textura.ui

import cui.*

/*
 * Control gallery — the visual acceptance surface for `textura.ui`.
 *
 * `demo()` declares a two-column sheet: the design kit rendered with the light tokens on the
 * left and the dark tokens on the right. Because every builder takes its `Theme`, both halves
 * live in one tree, which is what parity screenshots need (one 1440x900 frame shows every
 * control in both themes).
 *
 * The shell owns routing; this is deliberately not wired into `ROUTES`.
 */

private let DEMO_SECTION_GAP: Float32 = 28.0
private let DEMO_GLYPH_CELL: Float32 = 96.0

/** Every control, light + dark, in one scrolling sheet. */
public func demo(): Unit {
    let selection = rememberState<Int64>("kit-segmented") {1}
    let compactSelection = rememberState<Int64>("kit-segmented-sm") {0}
    let titleText = rememberState<String>("kit-input") {"织理 Textura"}
    let noteText = rememberState<String>("kit-textarea") {"一行说明，用于核对 textarea 的最小高度与行高。"}
    let dialogOpen = rememberState<Bool>("kit-modal") {false}
    let light = ThemeTokens.light()
    let dark = ThemeTokens.dark()

    ZStack {
        ScrollView(key: "kit-scroll") {
            HStack(spacing: vp(0.0)) {
                kitColumn(light, selection, compactSelection, titleText, noteText, dialogOpen)
                kitColumn(dark, selection, compactSelection, titleText, noteText, dialogOpen)
            }
        }
        Ui.modal(
            light.theme(),
            dialogOpen,
            {=> dialogOpen.value = false},
            title: "新建事项",
            description: "覆盖遮罩、面板宽高、标题/关闭/内容/页脚；Esc 与点击遮罩关闭。",
            footer: {=>
                Ui.button(light.theme(), "取消", {=> dialogOpen.value = false}, variant: ButtonVariant.Ghost)
                Ui.button(light.theme(), "保存", {=> dialogOpen.value = false}, variant: ButtonVariant.Primary)
            },
            body: {=>
                Ui.field(light.theme(), label: "标题", required: true, hint: "必填，最多 80 字。") {
                    Ui.textInput(light.theme(), titleText, key: "kit-modal-title", placeholder: "写点什么")
                }
            }
        )
    }
}

private func kitColumn(
    tokens: ThemeTokens,
    selection: State<Int64>,
    compactSelection: State<Int64>,
    titleText: State<String>,
    noteText: State<String>,
    dialogOpen: State<Bool>
): Unit {
    VStack(spacing: vp(DEMO_SECTION_GAP)) {
        kitHeader(tokens)
        kitTypography(tokens)
        kitButtons(tokens)
        kitIconButtons(tokens)
        kitBadges(tokens)
        kitProgress(tokens)
        kitSegmented(tokens, selection, compactSelection)
        kitFields(tokens, titleText, noteText)
        kitEmptyState(tokens, dialogOpen)
        kitGlyphGrid(tokens)
    }
        .padding(tokens.space.s6)
        .fillWidth()
        .flex()
        .background(tokens.color.bg)
        .textStyle(TextStyle(fontFamily: FONT_UI_PARITY))
}

private func kitHeader(tokens: ThemeTokens): Unit {
    VStack(spacing: vp(tokens.space.s1)) {
        // h1: 20px / 650 / letter-spacing -0.01em (base.css:41-43)
        Label("Textura 控件陈列 · ${tokens.name}")
            .fontSize(Length(TextSize.display, LengthUnit.Fp))
            .fontWeight(FontWeight(650))
            .foregroundColor(tokens.color.text)
        Label("tokens.css + ui.css 逐值移植；本页覆盖全部基础控件与图标。")
            .fontSize(Length(TextSize.body, LengthUnit.Fp))
            .foregroundColor(tokens.color.textMuted)
    }.hug().fillWidth()
}

private func kitTypography(tokens: ThemeTokens): Unit {
    kitSection(tokens, "字体与字号") {
        VStack(spacing: vp(tokens.space.s2)) {
            Label("h1 20/650 · 早上好，今天推进什么？")
                .fontSize(Length(TextSize.display, LengthUnit.Fp))
                .fontWeight(FontWeight(650))
                .foregroundColor(tokens.color.text)
            Label("h2 16/620 · 今日聚焦")
                .fontSize(Length(TextSize.heading, LengthUnit.Fp))
                .fontWeight(FontWeight(620))
                .foregroundColor(tokens.color.text)
            Label("h3 14/600 · 视觉稿评审")
                .fontSize(Length(TextSize.body, LengthUnit.Fp))
                .fontWeight(FontWeight(600))
                .foregroundColor(tokens.color.text)
            Label("body 14/400 · 1 项目今日到期，收件箱 6 条待澄清。")
                .fontSize(Length(TextSize.body, LengthUnit.Fp))
                .foregroundColor(tokens.color.text)
            Label("text-muted · 按 completedAt 的近 7 天滚动窗口")
                .fontSize(Length(TextSize.bodyCompact, LengthUnit.Fp))
                .foregroundColor(tokens.color.textMuted)
            Label("text-faint · 提示与元数据")
                .fontSize(Length(TextSize.caption, LengthUnit.Fp))
                .foregroundColor(tokens.color.textFaint)
            Label("mono 13 · 2026-03-16T10:00:00+08:00")
                .fontSize(Length(TextSize.bodyCompact, LengthUnit.Fp))
                .fontFamily(FONT_MONO)
                .foregroundColor(tokens.color.textMuted)
        }.hug().fillWidth()
    }
}

private func kitButtons(tokens: ThemeTokens): Unit {
    let theme = tokens.theme()
    kitSection(tokens, "按钮 Button") {
        VStack(spacing: vp(tokens.space.s3)) {
            HStack(spacing: vp(tokens.space.s2)) {
                Ui.button(theme, "主要 md", {=> ()}, variant: ButtonVariant.Primary)
                Ui.button(theme, "次要 md", {=> ()})
                Ui.button(theme, "幽灵 md", {=> ()}, variant: ButtonVariant.Ghost)
                Ui.button(theme, "危险 md", {=> ()}, variant: ButtonVariant.Danger)
            }.hug()
            HStack(spacing: vp(tokens.space.s2)) {
                Ui.button(theme, "主要 sm", {=> ()}, variant: ButtonVariant.Primary, size: ControlSize.Sm)
                Ui.button(theme, "次要 sm", {=> ()}, size: ControlSize.Sm)
                Ui.button(theme, "幽灵 sm", {=> ()}, variant: ButtonVariant.Ghost, size: ControlSize.Sm)
                Ui.button(theme, "危险 sm", {=> ()}, variant: ButtonVariant.Danger, size: ControlSize.Sm)
            }.hug()
            HStack(spacing: vp(tokens.space.s2)) {
                Ui.button(theme, "新建", {=> ()}, variant: ButtonVariant.Primary, iconLeft: IconGlyph.Plus)
                Ui.button(theme, "筛选", {=> ()}, iconLeft: IconGlyph.Tag, iconRight: IconGlyph.ChevronDown)
                Ui.button(theme, "播放", {=> ()}, variant: ButtonVariant.Ghost, iconLeft: IconGlyph.Play)
            }.hug()
            HStack(spacing: vp(tokens.space.s2)) {
                Ui.button(theme, "已禁用", {=> ()}, variant: ButtonVariant.Primary, enabled: false)
                Ui.button(theme, "已禁用", {=> ()}, enabled: false)
                Ui.button(theme, "已禁用", {=> ()}, variant: ButtonVariant.Ghost, enabled: false)
                Ui.button(theme, "已禁用", {=> ()}, variant: ButtonVariant.Danger, enabled: false)
            }.hug()
            Ui.button(theme, "整行按钮 block", {=> ()}, variant: ButtonVariant.Secondary, block: true,
                iconLeft: IconGlyph.Check)
        }.hug().fillWidth()
    }
}

private func kitIconButtons(tokens: ThemeTokens): Unit {
    let theme = tokens.theme()
    kitSection(tokens, "图标按钮 IconButton") {
        HStack(spacing: vp(tokens.space.s2)) {
            Ui.iconButton(theme, IconGlyph.Search, {=> ()}, tooltip: "搜索")
            Ui.iconButton(theme, IconGlyph.Settings, {=> ()}, variant: IconButtonVariant.Secondary,
                tooltip: "设置")
            Ui.iconButton(theme, IconGlyph.Trash, {=> ()}, variant: IconButtonVariant.Danger, tooltip: "删除")
            Ui.iconButton(theme, IconGlyph.Plus, {=> ()}, size: ControlSize.Sm, tooltip: "添加")
            Ui.iconButton(theme, IconGlyph.Close, {=> ()}, size: ControlSize.Sm,
                variant: IconButtonVariant.Secondary, tooltip: "关闭")
            Ui.iconButton(theme, IconGlyph.More, {=> ()}, enabled: false)
        }.hug()
    }
}

private func kitBadges(tokens: ThemeTokens): Unit {
    let theme = tokens.theme()
    kitSection(tokens, "徽章 Badge") {
        VStack(spacing: vp(tokens.space.s2)) {
            HStack(spacing: vp(tokens.space.s2)) {
                Ui.badge(theme, "中性", tone: BadgeTone.Neutral)
                Ui.badge(theme, "强调", tone: BadgeTone.Accent)
                Ui.badge(theme, "通过", tone: BadgeTone.Ok)
                Ui.badge(theme, "注意", tone: BadgeTone.Warn)
                Ui.badge(theme, "失败", tone: BadgeTone.Danger)
                Ui.badge(theme, "信息", tone: BadgeTone.Info)
            }.hug()
            HStack(spacing: vp(tokens.space.s2)) {
                Ui.badge(theme, "今天到期", tone: BadgeTone.Warn, dot: true)
                Ui.badge(theme, "进行中", tone: BadgeTone.Accent, dot: true)
                Ui.badge(theme, "已完成", tone: BadgeTone.Ok, dot: true)
                Ui.badge(theme, "SOP", tone: BadgeTone.Neutral, dot: true)
            }.hug()
        }.hug()
    }
}

private func kitProgress(tokens: ThemeTokens): Unit {
    let theme = tokens.theme()
    kitSection(tokens, "进度 Progress") {
        VStack(spacing: vp(tokens.space.s2)) {
            Ui.progress(theme, 29.0, showLabel: true)
            Ui.progress(theme, 62.0, tone: ProgressTone.Ok, showLabel: true)
            Ui.progress(theme, 48.0, tone: ProgressTone.Warn, showLabel: true)
            Ui.progress(theme, 12.0, tone: ProgressTone.Danger, showLabel: true)
            Ui.progress(theme, 76.0, tone: ProgressTone.Info, showLabel: true)
            HStack(spacing: vp(tokens.space.s3)) {
                VStack(spacing: vp(0.0)) {
                    Ui.progress(theme, 40.0, size: ControlSize.Sm)
                }.hug().width(150.0)
                VStack(spacing: vp(0.0)) {
                    Ui.progress(theme, 90.0, tone: ProgressTone.Ok, size: ControlSize.Sm)
                }.hug().width(150.0)
            }.hug()
        }.hug().fillWidth()
    }
}

private func kitSegmented(tokens: ThemeTokens, selection: State<Int64>, compactSelection: State<Int64>): Unit {
    let theme = tokens.theme()
    kitSection(tokens, "分段控件 Segmented") {
        VStack(spacing: vp(tokens.space.s3)) {
            Ui.segmented(theme, ["全部", "进行中", "已完成"], selection)
            Ui.segmented(theme, ["日", "周", "月"], compactSelection, size: ControlSize.Sm)
            Ui.segmentedWithGlyphs(
                theme,
                [
                    SegmentedItem("列表", glyph: IconGlyph.Timeline),
                    SegmentedItem("日历", glyph: IconGlyph.CalendarGrid),
                    SegmentedItem("看板", glyph: IconGlyph.Workflow)
                ],
                selection
            )
        }.hug()
    }
}

private func kitFields(tokens: ThemeTokens, titleText: State<String>, noteText: State<String>): Unit {
    let theme = tokens.theme()
    kitSection(tokens, "表单 Field / Input") {
        VStack(spacing: vp(tokens.space.s3)) {
            Ui.field(theme, label: "标题", required: true, hint: "必填；14 字以内更易读。") {
                Ui.textInput(theme, titleText, key: "kit-name", placeholder: "事项标题")
            }
            Ui.field(theme, label: "备注", error: "该字段不能为空。") {
                Ui.textInput(theme, noteText, key: "kit-note", placeholder: "补充说明", invalid: true)
            }
            Ui.field(theme, label: "描述", hint: "textarea 最小高度 76。") {
                Ui.textArea(theme, noteText, key: "kit-area", placeholder: "多行文本")
            }
            Ui.field(theme, label: "只读字段") {
                Ui.textInput(theme, titleText, key: "kit-readonly", enabled: false)
            }
        }.hug().fillWidth()
    }
}

private func kitEmptyState(tokens: ThemeTokens, dialogOpen: State<Bool>): Unit {
    let theme = tokens.theme()
    kitSection(tokens, "空状态 EmptyState") {
        VStack(spacing: vp(tokens.space.s3)) {
            Ui.emptyState(
                theme,
                "收件箱是空的",
                description: "所有事项都已澄清。按 ⌘K 打开命令面板新建一条。",
                glyph: IconGlyph.Inbox,
                action: {=>
                    Ui.button(theme, "新建事项", {=> dialogOpen.value = true}, variant: ButtonVariant.Primary,
                        iconLeft: IconGlyph.Plus)
                }
            )
            Ui.emptyState(theme, "没有匹配结果", glyph: IconGlyph.Search, compact: true)
        }.hug().fillWidth()
            .background(tokens.color.surface)
            .border(tokens.color.border, width: tokens.metrics.borderWidth, radius: tokens.radius.lg)
    }
}

private func kitGlyphGrid(tokens: ThemeTokens): Unit {
    kitSection(tokens, "图标 Icons（icons.tsx 全量 30 个）") {
        // 6 cells per row keeps the kebab-case id labels uncut inside a 656vp column.
        VStack(spacing: vp(tokens.space.s2)) {
            for (row in 0..5) {
                HStack(spacing: vp(tokens.space.s2)) {
                    for (column in 0..6) {
                        let index = row * 6 + column
                        if (index < ALL_ICON_GLYPHS.size) {
                            kitGlyphCell(tokens, ALL_ICON_GLYPHS[index])
                        }
                    }
                }.hug()
            }
        }.hug()
    }
}

private func kitGlyphCell(tokens: ThemeTokens, glyph: IconGlyph): Unit {
    VStack(spacing: vp(2.0)) {
        Ui.icon(tokens.theme(), glyph, side: 20.0, color: tokens.color.textMuted)
        Label(iconGlyphId(glyph))
            .fontSize(Length(TextSize.micro, LengthUnit.Fp))
            .fontFamily(FONT_MONO)
            .foregroundColor(tokens.color.textFaint)
    }.hug().width(DEMO_GLYPH_CELL)
}

private func kitSection(tokens: ThemeTokens, title: String, body!: () -> Unit): Unit {
    VStack(spacing: vp(tokens.space.s3)) {
        HStack(spacing: vp(tokens.space.s2)) {
            // h3: 14px / 600 (base.css:51-54)
            Label(title)
                .fontSize(Length(TextSize.body, LengthUnit.Fp))
                .fontWeight(FontWeight(600))
                .foregroundColor(tokens.color.text)
            Spacer()
            Label("ui.css")
                .fontSize(Length(TextSize.micro, LengthUnit.Fp))
                .fontFamily(FONT_MONO)
                .foregroundColor(tokens.color.textFaint)
        }.hug().fillWidth()
        Divider().foregroundColor(tokens.color.border)
        body()
    }.hug().fillWidth()
}
