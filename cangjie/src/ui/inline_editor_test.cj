package textura.ui

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*

/*
 * 原位编辑器（`Ui.inlineEditor`，docs/DEVICE-NOTES.md §20）的行为门禁。
 *
 * 这些用例直接针对 `Ui.inlineEditor`，不经过任何视图：打开即聚焦、Enter 提交、Esc 取消、
 * 点外部提交、插入符锚点随输入右移。它们取代的是「每个字段都弹一个模态框」的旧路径，
 * 所以任何一条失败都意味着输入框又回到了「点得进去但没有插入符/输入法」或「又弹了一层」。
 */
private let INLINE_TEST_VIEWPORT: Rect = Rect(0.0, 0.0, 1440.0, 900.0)
/** 被编辑字段的矩形：编辑器必须正好落在这里（宽度=字段宽度）。 */
private let INLINE_FIELD: Rect = Rect(360.0, 240.0, 220.0, 34.0)
private let INLINE_KEY: String = "test-inline-input"

private class InlineProbe {
    let draft = State<String>("初始值")
    let focus = FocusRequest()
    let commits = ArrayListProbe()
    let cancels = ArrayListProbe()

    /**
     * 打开编辑器：写草稿、置 `open`、并**武装**一次性焦点请求。
     *
     * 第三步不能省。`FocusRequest` 是调用方拥有的对象（见 `src/ui/focus.cj`），`Ui.inlineEditor`
     * 只负责把请求落到本帧的布局里，绝不自己武装——否则它每帧都会重新武装，用户 Tab 走之后
     * 插入符又被拽回来（`promptTabDoesNotSnapBackToTheEditor` 守的就是这条）。真机上四个调用点
     * （SOP/OKR/GTD 日期/GTD 场景）都在点击字段时 `request(key)`，本 harness 对齐同一写法，
     * 与 `PromptHarness.arm()` 一致。
     */
    func arm(): Unit {
        focus.request(INLINE_KEY)
    }

    func build(): Unit {
        Ui.inlineEditor(texturaLight(), draft, INLINE_FIELD, true, key: INLINE_KEY, placeholder: "占位", focus: focus,
            onCommit: {value => commits.record(value)}, onCancel: {=> cancels.bump()})
    }
}

/** 极小的记录器：Cangjie 闭包捕获引用类型，所以用类而不是裸局部变量。 */
private class ArrayListProbe {
    private let values = ArrayList<String>()
    var count: Int64 = 0

    func record(value: String): Unit {
        count += 1
        values.add(value)
    }

    func bump(): Unit {
        count += 1
    }

    func last(): String {
        if (values.isEmpty()) {
            ""
        } else {
            values[values.size - 1]
        }
    }
}

@Test
func inlineEditorTakesFocusOnTheFirstFrame(): Unit {
    let probe = InlineProbe()
    probe.arm()
    let testHost = WidgetTestHost()
    let _ = testHost.frame(INLINE_TEST_VIEWPORT) {=> probe.build()}
    // Without this the field has no caret, no IME and no typing — the regression §16 was about.
    @Expect(testHost.context.focusId, INLINE_KEY)
}

@Test
func inlineEditorCommitsOnEnter(): Unit {
    let probe = InlineProbe()
    probe.arm()
    let testHost = WidgetTestHost()
    let _ = testHost.frame(INLINE_TEST_VIEWPORT) {=> probe.build()}
    let _ = testHost.frame(INLINE_TEST_VIEWPORT, events: [UiEvent.TextInput("（改）")]) {=> probe.build()}
    let _ = testHost.frame(INLINE_TEST_VIEWPORT, events: [UiEvent.KeyDown(Key.Enter, false)]) {=> probe.build()}
    @Expect(probe.commits.count, 1)
    @Expect(probe.commits.last(), "初始值（改）")
}

@Test
func inlineEditorCancelsOnEscape(): Unit {
    let probe = InlineProbe()
    probe.arm()
    let testHost = WidgetTestHost()
    let _ = testHost.frame(INLINE_TEST_VIEWPORT) {=> probe.build()}
    let _ = testHost.frame(INLINE_TEST_VIEWPORT, events: [UiEvent.KeyDown(Key.Escape, false)]) {=> probe.build()}
    // Esc never writes: it only asks the caller to close.
    @Expect(probe.cancels.count, 1)
    @Expect(probe.commits.count, 0)
}

@Test
func inlineEditorCommitsOnAnOutsidePress(): Unit {
    let probe = InlineProbe()
    probe.arm()
    let testHost = WidgetTestHost()
    let _ = testHost.frame(INLINE_TEST_VIEWPORT) {=> probe.build()}
    let _ = testHost.frame(INLINE_TEST_VIEWPORT, events: [UiEvent.TextInput("下一项")]) {=> probe.build()}
    // A press far away from the field: the Web build treats that as "done".
    let _ = testHost.frame(INLINE_TEST_VIEWPORT, events: [UiEvent.MouseDown(MouseButton.Left, 40.0, 600.0)]) {
        => probe.build()
    }
    @Expect(probe.commits.count, 1)
    @Expect(probe.commits.last(), "初始值下一项")
}

@Test
func inlineEditorKeepsAPressInsideTheField(): Unit {
    let probe = InlineProbe()
    probe.arm()
    let testHost = WidgetTestHost()
    let _ = testHost.frame(INLINE_TEST_VIEWPORT) {=> probe.build()}
    let inside = INLINE_FIELD.centerX()
    let _ = testHost.frame(INLINE_TEST_VIEWPORT,
        events: [UiEvent.MouseDown(MouseButton.Left, inside, INLINE_FIELD.centerY())]) {=> probe.build()}
    // Clicking the field itself places the caret; it must not end the edit.
    @Expect(probe.commits.count, 0)
}

@Test
func inlineEditorReportsTheCaretAnchorAndFollowsTyping(): Unit {
    let probe = InlineProbe()
    probe.arm()
    let testHost = WidgetTestHost()
    let _ = testHost.frame(INLINE_TEST_VIEWPORT) {=> probe.build()}
    let first = match (testHost.context.textInputAnchorRect()) {
        case Some(rect) => rect
        case None =>
            @Expect("a caret anchor for the focused field", "none")
            return
    }
    // The anchor is what the shell forwards to the OS (and what the ArkTS page sends as
    // `cursorInfo`), so it has to sit inside the field the user is editing.
    @Expect(INLINE_FIELD.contains(first.x, first.y), true)
    let _ = testHost.frame(INLINE_TEST_VIEWPORT, events: [UiEvent.TextInput("中文abc")]) {=> probe.build()}
    let second = match (testHost.context.textInputAnchorRect()) {
        case Some(rect) => rect
        case None =>
            @Expect("a caret anchor after typing", "none")
            return
    }
    // Typing moves the caret right: the candidate window must move with it, not stay put.
    @Expect(second.x > first.x, true)
    @Expect(INLINE_FIELD.contains(second.x, second.y), true)
}

@Test
func inlineEditorClampsAMultilineFieldToTheWindow(): Unit {
    let tokens = tokensOf(texturaLight())
    let draft = State<String>("多行")
    // A description field taller than 40vh must be capped, not overflow the window.
    let frame = InlineEditFrame(tokens, "clamp", "clamp", Rect(40.0, 80.0, 300.0, 900.0), true, draft, {_ => ()},
        {=> ()})
    let ctx = WidgetTestHost().context
    ctx.viewportWidth = 1024.0
    ctx.viewportHeight = 640.0
    let rect = frame.resolve(ctx)
    @Expect(rect.h <= 640.0 * 0.40 + 0.01, true)
    @Expect(rect.bottom() <= 640.0, true)
    @Expect(rect.w, Float32(300.0))
}

/**
 * 原位 = 真的落在字段矩形上。这是「下方又弹出一个一样的框」的第二种成因：编辑器本身比画上去的
 * 盒子高、或者被多包了一层容器，就会在原字段下面多出一块。断言用语义节点的绝对 bounds 对矩形，
 * 不用编辑器自己的返回值——返回值永远和输入一致，抓不到错位。
 */
private func inlineEditorBoundsOf(rect: Rect, multiline: Bool, key: String, viewport!: Rect = INLINE_TEST_VIEWPORT): Rect {
    let draft = State<String>("值")
    let request = FocusRequest()
    request.request(key)
    let testHost = WidgetTestHost()
    let _ = testHost.frame(viewport) {
        => Ui.inlineEditor(texturaLight(), draft, rect, true, key: key, multiline: multiline, placeholder: "占位",
            focus: request, onCommit: {_ => ()}, onCancel: {=> ()})
    }
    var bounds = Rect(0.0, 0.0, -1.0, -1.0)
    for (node in testHost.context.semanticsSnapshot()) {
        if (node.id == key) {
            bounds = node.bounds
        }
    }
    bounds
}

/** `Rect` 不是 `Equatable`，用字符串比较把四个数值一起打出来（失败时看得出差在哪）。 */
private func rectText(rect: Rect): String {
    "x=${rect.x} y=${rect.y} w=${rect.w} h=${rect.h}"
}

@Test
func inlineEditorCoversTheFieldRectangle(): Unit {
    // 单行字段（SOP 名称/负责人/耗时、OKR 标题、GTD 行）：34px 高。
    let line = Rect(360.0, 240.0, 220.0, 34.0)
    @Expect(rectText(inlineEditorBoundsOf(line, false, "cover-line")), rectText(line))
    // 检查器滚过之后的字段（`inspectorRects(..., scroll:)`）：y 不再是 240，仍要逐像素对上。
    let scrolled = Rect(392.0, 118.0, 268.0, 34.0)
    @Expect(rectText(inlineEditorBoundsOf(scrolled, false, "cover-scrolled")), rectText(scrolled))
    // 多行描述区（SOP 描述 92px）：高度等于画上去的盒子，不撑到 40vh。
    let area = Rect(360.0, 300.0, 220.0, 92.0)
    @Expect(rectText(inlineEditorBoundsOf(area, true, "cover-area")), rectText(area))
    // 检查项/分支文案那种 30px 的小行：单行高度，绝不按多行最小值撑高。
    let short = Rect(360.0, 120.0, 180.0, 30.0)
    @Expect(rectText(inlineEditorBoundsOf(short, true, "cover-short")), rectText(short))
}

@Test
func inlineEditorKeepsAFieldAtItsOwnHeight(): Unit {
    // 分档规则：只有「多行且 anchor.h ≥ 40」才按内容；
    // 其余一律用字段自身高度（下限一行 28），这样编辑器永远和画上去的盒子重合。
    let tokens = tokensOf(texturaLight())
    let ctx = WidgetTestHost().context
    ctx.viewportWidth = 1440.0
    ctx.viewportHeight = 900.0
    let single = InlineEditFrame(tokens, "h1", "h1", Rect(40.0, 80.0, 200.0, 34.0), false, State<String>(""), {_ => ()},
        {=> ()})
    @Expect(single.resolve(ctx).h, Float32(34.0))
    let tiny = InlineEditFrame(tokens, "h2", "h2", Rect(40.0, 80.0, 200.0, 18.0), false, State<String>(""), {_ => ()},
        {=> ()})
    @Expect(tiny.resolve(ctx).h, Float32(28.0))
    let shortArea = InlineEditFrame(tokens, "h3", "h3", Rect(40.0, 80.0, 200.0, 30.0), true, State<String>(""),
        {_ => ()}, {=> ()})
    @Expect(shortArea.resolve(ctx).h, Float32(30.0))
    let area = InlineEditFrame(tokens, "h4", "h4", Rect(40.0, 80.0, 200.0, 120.0), true, State<String>(""), {_ => ()},
        {=> ()})
    @Expect(area.resolve(ctx).h, Float32(120.0))
}
