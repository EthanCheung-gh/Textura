package textura.views.okr

import std.unittest.*
import std.unittest.testmacro.*
import cui.*
import cui.testing.*
import textura.core.data.*

/*
 * OkrPage 的「内容高度」必须在不依赖上一帧布局的情况下可得（真机证据见 docs/DEVICE-NOTES.md §12）。
 *
 * 现象：从别的路由进入 OKR 后整页空白，直接启动到 OKR 正常。根因是 `measure()` 返回上一轮
 * `layout()` 写回的 `contentHeight`：新实例第一次被量时它是 0，ScrollView 于是按 0 高布局，
 * 内容被裁掉，而这一帧之后没有任何脏标记再触发一次测量。
 */

private func okrPageViewContext(store: AppStore): ViewContext {
    ViewContext(store, "light", "2026-03-16", 1440, 900, {_ => ()})
}

private class MeasuredHeight {
    var value: Float32 = 0.0
}

@Test
func measureReportsIntrinsicHeightBeforeAnyLayout(): Unit {
    let clock = FixedClock(1773626400000)
    let store = AppStore(clock: clock)
    store.loadFromText(encodeWorkspaceDocument(createSeedWorkspace(clock)))
    let viewCtx = okrPageViewContext(store)
    let testHost = WidgetTestHost()
    let height = MeasuredHeight()
    let _ = testHost.frame(Rect(0.0, 0.0, 1440.0, 900.0),
        body: {=>
            let page = OkrPage(viewCtx, okrUiState())
            height.value = page.measure(testHost.context, Size(1152.0, 100000.0)).h
        })
    // The seeded workspace has one objective with three KRs; the page is several hundred vp tall.
    @Expect(height.value > 100.0, true)
}
