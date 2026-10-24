package textura.views.gtd

import std.collection.*
import cui.*
import textura.ui.FocusRequest
import textura.views.gtd.logic as gl

/*
 * 视图内状态（跨帧保留）。
 *
 * 对应 Web 版各组件的 `useState`：GtdPage（view / clarifyId / highlight）、
 * InboxList（limit / activeId）、NextActions（dueSoonOnly / areaFilter / collapsed /
 * editingId / draft / page）、WaitingList / SomedayList（limit）、WeeklyReview（reviewed）、
 * ClarifyDialog（form / errors）。
 *
 * 规则（CUI-PRIMER §2）：`rememberState` 的 key 必须稳定且同级唯一；业务选择存业务 id，
 * 不用下标代替。所有 key 带 `gtd-` 前缀，避免与 shell 的 key 撞车。
 */
class GtdState {
    /** 0 = 流程台，1 = 周回顾（GtdPage.tsx `view`）。 */
    var viewMode: State<Int64>
    /** 澄清弹窗目标条目；空串表示关闭。 */
    var clarifyId: State<String>
    /** 分区聚焦高亮（GtdPage.tsx `highlight`）：inbox / next / waiting / someday / projects。 */
    var highlight: State<String>

    // ---------------- 收件箱 ----------------
    var inboxLimit: State<Int64>
    var activeInbox: State<String>

    // ---------------- 下一步 ----------------
    var nextLimit: State<Int64>
    /** 分页 key：筛选/搜索/折叠变化时回到第一页（NextActions.tsx `pageKey`）。 */
    var nextPageKey: State<String>
    var dueSoonOnly: State<Bool>
    var areaFilter: State<String>
    /** 换行分隔的折叠场景集合（NextActions.tsx `collapsed`）；场景名不含换行。 */
    var collapsed: State<String>
    var activeNext: State<String>
    /** 键盘目标列表："inbox" | "next"（由最后一次点击决定）。 */
    var keyTarget: State<String>
    /** 行内标题编辑目标；空串表示没有编辑中的行。 */
    var editId: State<String>
    var titleDraft: State<String>

    // ---------------- 侧栏列表 ----------------
    var waitingLimit: State<Int64>
    var somedayLimit: State<Int64>

    // ---------------- 周回顾 ----------------
    /** 换行分隔的已回顾卡片 id。 */
    var reviewed: State<String>

    // ---------------- 浮层 ----------------
    /** 选择器目标："" | "filter-context" | "filter-area" | "row-context:<id>"。 */
    var picker: State<String>
    /** 日期编辑目标条目 id；空串表示关闭。 */
    var dateTarget: State<String>
    var dateDraft: State<String>
    /** 日期编辑器的绝对矩形（行内日期盒 layout 时记录），原位摆放用。 */
    var dateRect: Rect
    var dateFocus: FocusRequest
    /** 场景（context）原位编辑目标条目 id；空串表示关闭。 */
    var sceneTarget: State<String>
    var sceneDraft: State<String>
    var sceneRect: Rect
    var sceneFocus: FocusRequest

    // ---------------- 澄清表单 ----------------
    var clarifyType: State<Int64>
    var clarifyEnergy: State<Int64>
    var clarifyContext: State<Int64>
    var clarifyEstimate: State<Int64>
    var clarifyArea: State<Int64>
    var clarifyTitle: State<String>
    var clarifyNotes: State<String>
    var clarifyTags: State<String>
    var clarifyCustomContext: State<String>
    var clarifyDue: State<String>
    var clarifyWaitingFor: State<String>
    var clarifyDelegated: State<Bool>
    var clarifySomeday: State<Bool>
    var clarifyTwoMinute: State<Bool>
    /** 是否已经点过一次「完成澄清」（决定是否显示校验错误）。 */
    var clarifySubmitted: State<Bool>

    init() {
        viewMode = rememberState<Int64>("gtd-view-mode") {0}
        clarifyId = rememberState<String>("gtd-clarify-id") {""}
        highlight = rememberState<String>("gtd-highlight") {""}
        inboxLimit = rememberState<Int64>("gtd-inbox-limit") {gl.LIST_PAGE_SIZE}
        activeInbox = rememberState<String>("gtd-active-inbox") {""}
        nextLimit = rememberState<Int64>("gtd-next-limit") {gl.LIST_PAGE_SIZE}
        nextPageKey = rememberState<String>("gtd-next-page-key") {""}
        dueSoonOnly = rememberState<Bool>("gtd-due-soon") {false}
        areaFilter = rememberState<String>("gtd-area-filter") {""}
        collapsed = rememberState<String>("gtd-collapsed") {""}
        activeNext = rememberState<String>("gtd-active-next") {""}
        keyTarget = rememberState<String>("gtd-key-target") {"inbox"}
        editId = rememberState<String>("gtd-edit-id") {""}
        titleDraft = rememberState<String>("gtd-title-draft") {""}
        waitingLimit = rememberState<Int64>("gtd-waiting-limit") {gl.LIST_PAGE_SIZE}
        somedayLimit = rememberState<Int64>("gtd-someday-limit") {gl.LIST_PAGE_SIZE}
        reviewed = rememberState<String>("gtd-reviewed") {""}
        picker = rememberState<String>("gtd-picker") {""}
        dateTarget = rememberState<String>("gtd-date-target") {""}
        dateDraft = rememberState<String>("gtd-date-draft") {""}
        dateRect = Rect.zero()
        dateFocus = FocusRequest()
        sceneTarget = rememberState<String>("gtd-scene-target") {""}
        sceneDraft = rememberState<String>("gtd-scene-draft") {""}
        sceneRect = Rect.zero()
        sceneFocus = FocusRequest()
        clarifyType = rememberState<Int64>("gtd-clarify-type") {0}
        clarifyEnergy = rememberState<Int64>("gtd-clarify-energy") {1}
        clarifyContext = rememberState<Int64>("gtd-clarify-context") {0}
        clarifyEstimate = rememberState<Int64>("gtd-clarify-estimate") {0}
        clarifyArea = rememberState<Int64>("gtd-clarify-area") {0}
        clarifyTitle = rememberState<String>("gtd-clarify-title") {""}
        clarifyNotes = rememberState<String>("gtd-clarify-notes") {""}
        clarifyTags = rememberState<String>("gtd-clarify-tags") {""}
        clarifyCustomContext = rememberState<String>("gtd-clarify-custom-context") {""}
        clarifyDue = rememberState<String>("gtd-clarify-due") {""}
        clarifyWaitingFor = rememberState<String>("gtd-clarify-waiting-for") {""}
        clarifyDelegated = rememberState<Bool>("gtd-clarify-delegated") {false}
        clarifySomeday = rememberState<Bool>("gtd-clarify-someday") {false}
        clarifyTwoMinute = rememberState<Bool>("gtd-clarify-two-minute") {false}
        clarifySubmitted = rememberState<Bool>("gtd-clarify-submitted") {false}
    }
}

/** 每次渲染调用一次；`rememberState` 在同一帧内可重复读取同一个 key。 */
func gtdState(): GtdState {
    GtdState()
}

/**
 * 选中行解析：状态为空时退回首行（`useRowKeyboard.ts` 的 `useState(ids[0] ?? null)`）。
 * 构建期只读状态、不写状态，避免渲染循环。
 */
func resolvedActiveId(current: String, items: Array<gl.GtdItem>): String {
    if (!current.isEmpty()) {
        return current
    }
    if (items.isEmpty()) {
        return ""
    }
    items[0].id
}

/* ---------------------------------------------------------------- 集合辅助 */

/** 换行分隔集合的成员判断。 */
func setHas(encoded: String, value: String): Bool {
    if (encoded.isEmpty() || value.isEmpty()) {
        return false
    }
    for (part in encoded.split("\n")) {
        if (part == value) {
            return true
        }
    }
    false
}

/** 切换集合成员，返回新的编码串。 */
func setToggle(encoded: String, value: String): String {
    let parts = ArrayList<String>()
    var present = false
    if (!encoded.isEmpty()) {
        for (part in encoded.split("\n")) {
            if (part == value) {
                present = true
            } else if (!part.isEmpty()) {
                parts.add(part)
            }
        }
    }
    if (!present && !value.isEmpty()) {
        parts.add(value)
    }
    var result = ""
    var index = 0
    for (part in parts) {
        if (index > 0) {
            result += "\n"
        }
        result += part
        index += 1
    }
    result
}

/** 集合大小。 */
func setSize(encoded: String): Int64 {
    if (encoded.isEmpty()) {
        return 0
    }
    var count: Int64 = 0
    for (part in encoded.split("\n")) {
        if (!part.isEmpty()) {
            count += 1
        }
    }
    count
}
