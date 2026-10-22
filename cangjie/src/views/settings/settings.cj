package textura.views.settings

import std.collection.*
import std.fs.*
import cui.*
import textura.core.data.*
import textura.ui.*
import textura.views.settings.logic.*

/*
 * Settings view — 1:1 port of `src/modules/appshell/SettingsPage.tsx` (622 lines) with the
 * page geometry of `appshell.css` (`.settings-*`, lines 319-515) and `shell.css` (`.page*`,
 * lines 255-296).
 *
 * Layout contract (1440x900, the shell supplies the `.shell-content` 24px padding):
 *
 *   .page          max-width 1280, gap 24 (shell.css:262-268)
 *   .page-header   56.5 tall: h1 22/650/33 + 4 + p 13/19.5
 *   .settings-grid 1.25fr | 1fr, gap 16, align start (appshell.css:326-331)
 *   .settings-card surface + 1px border + radius 14 + shadow-1, head 16/16 with a 1px rule,
 *                  body 16 with a 12px stack (appshell.css:340-385)
 *
 * Desktop capability differences (documented in the UI, never faked):
 *   - No Tauri IPC: the workspace is a single JSON file written atomically by
 *     `AppStore.save()`; rotating `.bak` backups do not exist in `core.data`, so the
 *     backup list/restore modal is replaced by a note plus the import path as recovery.
 *   - No native file picker is reachable from a view (`DesktopApp.openFileDialog` lives in
 *     the shell), so import reads the clipboard or `<workspace dir>/textura-import.json`
 *     and says so before touching data.
 *   - CUI fixes the window `Theme` at `DesktopApp` creation, so the appearance switch only
 *     records the preference (`ui.theme`) and tells the user it applies after a restart.
 */

/** `.settings-page` badge in the page header — `SettingsPage.tsx:210-212`. */
struct BadgeSpec {
    let text: String
    let tone: BadgeTone

    init(text: String, tone: BadgeTone) {
        this.text = text
        this.tone = tone
    }
}

/** `.badge` box: 11px * 1.6 line + 2*2 padding + 2*1 border = 23.6 (ui.css:243-254). */
func badgeHeight(tokens: ThemeTokens): Float32 {
    TextSize.micro * 1.6 + tokens.space.s1 + tokens.metrics.borderWidth * 2.0
}

func storageBadge(store: AppStore): BadgeSpec {
    match (store.saveStatus()) {
        case SaveState.Error => BadgeSpec("保存失败", BadgeTone.Danger)
        case SaveState.Saving => BadgeSpec("正在保存", BadgeTone.Warn)
        case SaveState.Saved => BadgeSpec("已保存", BadgeTone.Ok)
        case _ => BadgeSpec("自动保存", BadgeTone.Ok)
    }
}

/** Badge widget with the CSS box height (the kit's `BadgeView` measures 21.6). */
func badge(tokens: ThemeTokens, spec: BadgeSpec): Unit {
    BadgeView(tokens, spec.text, tone: spec.tone, dot: true).height(badgeHeight(tokens))
}

/** Reads a UTF-8 text file; `None` when the path is missing or unreadable. */
func readTextFile(path: String): ?String {
    try {
        Some(String.fromUtf8(File.readFrom(path)))
    } catch (_: Exception) {
        None
    }
}

func errorText(store: AppStore): String {
    match (store.error()) {
        case Some(message) => message
        case None => "工作区尚未就绪"
    }
}

func workspacePathText(store: AppStore): String {
    match (store.path()) {
        case Some(path) => path
        case None => "（尚未指定工作区路径）"
    }
}

func dataDirectoryText(store: AppStore): String {
    match (store.path()) {
        case Some(path) =>
            let dir = parentDirectory(path)
            if (dir.isEmpty()) {
                "（当前目录）"
            } else {
                dir
            }
        case None => "—"
    }
}

func exportPath(store: AppStore): ?String {
    match (store.path()) {
        case Some(path) =>
            let dir = parentDirectory(path)
            if (dir.isEmpty()) {
                Some(exportFileName(store.clock))
            } else {
                Some("${dir}/${exportFileName(store.clock)}")
            }
        case None => None
    }
}

func importPath(store: AppStore): ?String {
    match (store.path()) {
        case Some(path) =>
            let dir = parentDirectory(path)
            if (dir.isEmpty()) {
                Some(importFileName())
            } else {
                Some("${dir}/${importFileName()}")
            }
        case None => None
    }
}

func fileSize(path: String): ?Int64 {
    try {
        Some(Int64(File.readFrom(path).size))
    } catch (_: Exception) {
        None
    }
}

/**
 * One-row storage digest: document version, record count, byte size and last write time.
 * Keeping it in the existing fourth row (instead of adding rows) preserves the reference
 * card height, which is what the pixel gate measures.
 */
func storageSummaryText(workspace: Workspace, bytes: Int64): String {
    "v${workspace.version} · ${workspace.items.size} 条记录 · ${formatSize(bytes)} · ${lastWriteText(workspace.updatedAt)}"
}

/* ------------------------------------------------------------------ */
/* Page sections                                                       */
/* ------------------------------------------------------------------ */

/**
 * `.page-header` (shell.css:270-296) with the settings badge and the 快捷键 action
 * (`SettingsPage.tsx:204-222`).
 */
func pageHeader(theme: Theme, tokens: ThemeTokens, onShortcuts: () -> Unit): Unit {
    let c = tokens.color
    HStack(spacing: vp(tokens.space.s4)) {
        VStack(spacing: vp(tokens.space.s1)) {
            // `.page-header h1 { font-size: 22px }` + `h1 { font-weight: 650; line-height: 1.5 }`
            Paragraph("设置", sizePx: 22.0, lineHeightPx: 33.0, ink: c.text, weight: 650)
            // `.page-header p { color: text-muted; font-size: 13px }`
            Paragraph("存储、备份与工作区。", sizePx: 13.0, lineHeightPx: 19.5, ink: c.textMuted)
        }.hug()
        Spacer()
        // `.page-actions { align-items: center; gap: var(--space-2) }`
        HStack(spacing: vp(tokens.space.s2)) {
            badge(tokens, BadgeSpec("桌面模式", BadgeTone.Ok))
            Ui.button(theme, "快捷键", onShortcuts, size: ControlSize.Sm, iconLeft: IconGlyph.Flag)
        }.crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }.crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

/**
 * `.settings-card` (appshell.css:340-357): surface, 1px border, radius 14, shadow-1,
 * head = 16px padding + title/desc column (+ optional trailing) and a 1px bottom rule,
 * body = 16px padding around a 12px stack.
 */
func card(
    theme: Theme,
    tokens: ThemeTokens,
    title: String,
    glyph: IconGlyph,
    desc: String,
    trailing!: ?() -> Unit = None,
    body!: () -> Unit
): Unit {
    let c = tokens.color
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(tokens.space.s4)) {
            VStack(spacing: vp(0.0)) {
                // `.settings-card-title { gap: 8; font-size: 13.5px; font-weight: 650 }`
                HStack(spacing: vp(tokens.space.s2)) {
                    IconView(glyph, side: 15.0, color: c.textFaint)
                    Paragraph(title, sizePx: 13.5, lineHeightPx: 20.25, ink: c.text, weight: 650)
                }.hug()
                // `.settings-card-desc { margin-top: 2px; font-size: 11.5px; line-height: 1.55;
                //  color: text-faint; max-width: 46ch }` — 46ch resolves to 293.59px on the
                //  reference (Chromium "0" advance 6.3825px at 11.5px); pin it so CUI's slightly
                //  different advance cannot change where the description wraps.
                Paragraph(desc, sizePx: 11.5, lineHeightPx: 17.825, ink: c.textFaint, maxWidthPx: 293.59).padding(0.0,
                    2.0, 0.0, 0.0)
            }.hug()
            Spacer()
            match (trailing) {
                case Some(build) => build()
                case None => ()
            }
        }.crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(vp(tokens.space.s4)).fillWidth()
        Hairline(tokens)
        VStack(spacing: vp(tokens.space.s3)) {
            body()
        }.hug().padding(vp(tokens.space.s4)).fillWidth()
    }
        // `border: 1px` is part of the CSS border box, so content starts 1px inside the frame.
        .hug()
        .padding(vp(tokens.metrics.borderWidth))
        .fillWidth()
        .background(c.surface, tokens.radius.lg)
        .border(c.border, width: tokens.metrics.borderWidth, radius: tokens.radius.lg)
        .shadow(cardShadow(tokens), radius: tokens.radius.lg)
}

/* ------------------------------------------------------------------ */
/* Entry point                                                         */
/* ------------------------------------------------------------------ */

public func bootstrapTitle(): String {
    "设置"
}

public func bootstrapNote(): String {
    "设置视图占位：由后续 worker 按 docs/STRUCTURE.md 实现，并提交 parity 截图。"
}

public func render(ctx: ViewContext): Unit {
    let isDark = ctx.theme == "dark"
    let theme = if (isDark) {
        texturaDark()
    } else {
        texturaLight()
    }
    let tokens = tokensOf(theme)
    let c = tokens.color
    let store = ctx.store
    let workspace = store.state.value()

    /* -------- transient state (stable keys, one entry per interaction) -------- */
    let importSourceOpen = rememberState<Bool>("settings-import-source") {false}
    let importConfirmOpen = rememberState<Bool>("settings-import-confirm") {false}
    let resetOpen = rememberState<Bool>("settings-reset") {false}
    let clearOpen = rememberState<Bool>("settings-clear") {false}
    let pendingText = rememberState<String>("settings-pending-text") {""}
    let pendingSource = rememberState<String>("settings-pending-source") {""}
    let pendingCounts = rememberState<String>("settings-pending-counts") {""}
    let pendingEmpty = rememberState<Bool>("settings-pending-empty") {false}
    let importError = rememberState<String>("settings-import-error") {""}
    let resetError = rememberState<String>("settings-reset-error") {""}
    let clearError = rememberState<String>("settings-clear-error") {""}
    let themeChoice = rememberState<Int64>("settings-theme-choice") {
        if (isDark) {
        1
    } else {
        0
    }
    }
    let themeSynced = rememberState<Int64>("settings-theme-synced") {
        if (isDark) {
        1
    } else {
        0
    }
    }
    /** -1 until 「刷新信息」 reads the file from disk. */
    let diskBytes = rememberState<Int64>("settings-disk-bytes") {-1}

    /* -------- appearance preference (CUI themes are fixed per window) -------- */
    let storedTheme = store.ui.value().theme
    let storedIndex: Int64 = if (storedTheme == THEME_DARK) {
        1
    } else {
        0
    }
    if (themeChoice.value != themeSynced.value) {
        let target = if (themeChoice.value == 1) {
            THEME_DARK
        } else {
            THEME_LIGHT
        }
        if (storedTheme != target) {
            store.setTheme(target)
            let label = if (target == THEME_DARK) {
                "深色"
            } else {
                "浅色"
            }
            store.notify("主题偏好已记录为${label}；CUI 主题在窗口创建时固定，重启后生效。", tone: NoticeTone.Info)
        }
        themeSynced.value = themeChoice.value
    } else if (themeChoice.value != storedIndex) {
        themeChoice.value = storedIndex
        themeSynced.value = storedIndex
    }

    let openShortcuts = {
        => store.setUi({state => state.shortcutsOpen = true})
    }

    let saveNow = {
        =>
            if (store.save()) {
                store.notify("工作区已保存", tone: NoticeTone.Success)
            } else {
                store.notify("保存失败：${errorText(store)}", tone: NoticeTone.Error)
            }
            ()
    }

    let refreshInfo = {
        =>
            match (store.path()) {
                case Some(path) => match (fileSize(path)) {
                    case Some(bytes) =>
                        diskBytes.value = bytes
                        store.notify("已读取存储信息：${formatSize(bytes)}", tone: NoticeTone.Info)
                    case None => store.notify("读取存储信息失败：文件不可读", tone: NoticeTone.Error)
                }
                case None => store.notify("读取存储信息失败：尚未指定工作区路径", tone: NoticeTone.Error)
            }
            ()
    }

    let exportNow = {
        =>
            match (exportPath(store)) {
                case Some(path) => try {
                    File.writeTo(path, store.exportDocument().toArray())
                    store.notify("已导出到 ${path}", tone: NoticeTone.Success)
                } catch (error: Exception) {
                    store.notify("导出失败：${error.message}", tone: NoticeTone.Error)
                }
                case None => store.notify("导出失败：尚未指定工作区路径", tone: NoticeTone.Error)
            }
            ()
    }

    let importFromClipboard = {
        =>
            match (TextClipboard.system.readText()) {
                case Some(text) =>
                    let parsed = parseImportText(text, store.clock)
                    match (parsed.workspace) {
                        case Some(parsedWorkspace) =>
                            let summary = summarizeImport(parsedWorkspace)
                            pendingText.value = text
                            pendingSource.value = "剪贴板"
                            pendingCounts.value = summary.countsText()
                            pendingEmpty.value = summary.isEmptyWorkspace()
                            importError.value = ""
                            importSourceOpen.value = false
                            importConfirmOpen.value = true
                        case None => importError.value = parsed.error
                    }
                case None => store.notify("导入失败：无法读取剪贴板", tone: NoticeTone.Error)
            }
            ()
    }

    let importFromFile = {
        =>
            match (importPath(store)) {
                case Some(path) => match (readTextFile(path)) {
                    case Some(text) =>
                        let parsed = parseImportText(text, store.clock)
                        match (parsed.workspace) {
                            case Some(parsedWorkspace) =>
                                let summary = summarizeImport(parsedWorkspace)
                                pendingText.value = text
                                pendingSource.value = path
                                pendingCounts.value = summary.countsText()
                                pendingEmpty.value = summary.isEmptyWorkspace()
                                importError.value = ""
                                importSourceOpen.value = false
                                importConfirmOpen.value = true
                            case None => importError.value = parsed.error
                        }
                    case None => importError.value = "读不到 ${path}；请把 JSON 文件放到该路径，或用剪贴板导入。"
                }
                case None => importError.value = "尚未指定工作区路径，无法定位 ${importFileName()}。"
            }
            ()
    }

    let applyImport = {
        =>
            if (pendingText.value.isEmpty()) {
                importConfirmOpen.value = false
            } else {
                match (store.importDocument(pendingText.value)) {
                    case None =>
                        store.notify("已导入 ${pendingCounts.value}；可用 Ctrl+Z 回退整次导入", tone: NoticeTone.Success)
                        importConfirmOpen.value = false
                        pendingText.value = ""
                    case Some(message) =>
                        importError.value = message
                        store.notify("导入失败：${message}", tone: NoticeTone.Error)
                }
            }
            ()
    }

    let applyReset = {
        =>
            let text = encodeWorkspaceDocument(buildDemoWorkspace(store.clock))
            match (store.importDocument(text)) {
                case None =>
                    store.notify("已重置为演示数据；可用 Ctrl+Z 回退整次重置", tone: NoticeTone.Success)
                    resetOpen.value = false
                case Some(message) =>
                    resetError.value = message
                    store.notify("重置失败：${message}", tone: NoticeTone.Error)
            }
            ()
    }

    let applyClear = {
        =>
            let text = encodeWorkspaceDocument(emptyWorkspace(store.clock))
            match (store.importDocument(text)) {
                case None =>
                    store.notify("已清空工作区；可用 Ctrl+Z 回退整次清空", tone: NoticeTone.Success)
                    clearOpen.value = false
                case Some(message) =>
                    clearError.value = message
                    store.notify("清空失败：${message}", tone: NoticeTone.Error)
            }
            ()
    }

    let doUndo = {
        =>
            if (store.undo()) {
                store.notify("已撤销上一步", tone: NoticeTone.Success)
            } else {
                store.notify("没有可撤销的操作", tone: NoticeTone.Info)
            }
            ()
    }

    let doRedo = {
        =>
            if (store.redo()) {
                store.notify("已重做一步", tone: NoticeTone.Success)
            } else {
                store.notify("没有可重做的操作", tone: NoticeTone.Info)
            }
            ()
    }

    let undoable = store.canUndo()
    let redoable = store.canRedo()
    let disk = if (diskBytes.value >= 0) {
        diskBytes.value
    } else {
        documentBytes(workspace)
    }
    let saveSpec = storageBadge(store)

    VStack(spacing: vp(tokens.space.s5)) {
        pageHeader(theme, tokens, openShortcuts)

        // `.settings-grid { grid-template-columns: minmax(0,1.25fr) minmax(0,1fr); gap: 16px;
        //  align-items: start }` (appshell.css:326-331).
        // CUI's flex pass absorbs `gap * (weightTotal - childCount)` before splitting the
        // remainder, so the CSS 1.25fr/1fr share is expressed as weights that already carry
        // the gap: share = 631.111 / (1152 - 16) = 0.554033. At the parity width this lands on
        // the exact CSS column boxes (631.111 / 504.889).
        HStack(spacing: vp(tokens.space.s4)) {
            /* ---- left column: appearance / storage / transfer ---- */
            Flexible(weight: 0.554033) {
                VStack(spacing: vp(tokens.space.s4)) {
                    card(theme, tokens, "外观", if (isDark) {
                        IconGlyph.Moon
                    } else {
                        IconGlyph.Sun
                    }, "主题偏好记录在 ui 状态（textura.theme）；CUI 主题在窗口创建时固定，重启后生效。", trailing: {
                        => Ui.segmentedWithGlyphs(
                            theme,
                            [
                                SegmentedItem("浅色", glyph: IconGlyph.Sun),
                                SegmentedItem("深色", glyph: IconGlyph.Moon)
                            ],
                            themeChoice,
                            size: ControlSize.Sm
                        )
                    }, body: {
                        => NoteBox(tokens, "浅色是暖纸感的工作台，深色适合夜间复盘。主题只影响界面，不改动工作区数据。")
                    })

                    card(
                        theme,
                        tokens,
                        "数据与备份",
                        IconGlyph.Folder,
                        "单文件原子写入：.tmp 后改名覆盖；不提供轮换备份。",
                        trailing: {
                            => badge(tokens, saveSpec)
                        },
                        body: {
                            =>
                                VStack(spacing: vp(6.0)) {
                                    KeyValueRow(tokens, "运行模式", "桌面（文件持久化）")
                                    KeyValueRow(tokens, "数据目录", dataDirectoryText(store))
                                    KeyValueRow(tokens, "工作区文件", workspacePathText(store))
                                    KeyValueRow(tokens, "存储概况", storageSummaryText(workspace, disk))
                                }.hug().fillWidth()
                                HStack(spacing: vp(tokens.space.s2)) {
                                    Ui.button(theme, "立即保存", saveNow, size: ControlSize.Sm,
                                        iconLeft: IconGlyph.Check)
                                    Ui.button(theme, "刷新信息", refreshInfo, variant: ButtonVariant.Ghost,
                                        size: ControlSize.Sm)
                                }.hug()
                                NoteBox(tokens, "桌面重写暂不提供轮换备份；恢复请用下方「导入 JSON…」载入备份文件。")
                        }
                    )

                    card(
                        theme,
                        tokens,
                        "导入 / 导出",
                        IconGlyph.Link,
                        "导出一份完整 JSON；导入会整份替换当前工作区（items / edges / areas / runs）。",
                        body: {
                            =>
                                HStack(spacing: vp(tokens.space.s2)) {
                                    Ui.button(theme, "导出 JSON", exportNow, size: ControlSize.Sm,
                                        iconLeft: IconGlyph.Folder)
                                    Ui.button(theme, "导入 JSON…", {=> importSourceOpen.value = true},
                                        size: ControlSize.Sm, iconLeft: IconGlyph.Link)
                                }.hug()
                                NoteBox(tokens,
                                    "导入会先校验 JSON，再通过 importDocument 整份替换并立即原子保存；导入前会记录一次历史快照，可用 Ctrl+Z 回退整次导入。当前工作区：${workspace.items.size} 条记录 · ${workspace.areas.size} 个领域 · ${workspace.runs.size} 条 SOP 运行记录。")
                        }
                    )
                }.hug().fillWidth()
            }
            /* ---- right column: maintenance / about ---- */
            Flexible(weight: 0.445967) {
                VStack(spacing: vp(tokens.space.s4)) {
                    card(
                        theme,
                        tokens,
                        "维护",
                        IconGlyph.Workflow,
                        "历史栈最多 80 步；撤销 / 重做只改内存，需手动保存落盘。",
                        body: {
                            =>
                                KeyValueRow(tokens, "可撤销", if (undoable) {
                                    "有历史记录"
                                } else {
                                    "没有可撤销的操作"
                                })
                                KeyValueRow(tokens, "可重做", if (redoable) {
                                    "有重做记录"
                                } else {
                                    "没有可重做的操作"
                                })
                                HStack(spacing: vp(tokens.space.s2)) {
                                    Ui.button(theme, "撤销", doUndo, size: ControlSize.Sm,
                                        iconLeft: IconGlyph.ChevronLeft, enabled: undoable)
                                    Ui.button(theme, "重做", doRedo, size: ControlSize.Sm,
                                        iconLeft: IconGlyph.ChevronRight, enabled: redoable)
                                }.hug()
                                NoteBox(tokens,
                                    "重置会通过 importDocument 用内置演示数据整份替换并立即保存，可用 Ctrl+Z 回退整次重置。")
                                HStack(spacing: vp(tokens.space.s2)) {
                                    Ui.button(
                                        theme,
                                        "重置为演示数据",
                                        {
                                            =>
                                                resetError.value = ""
                                                resetOpen.value = true
                                        },
                                        variant: ButtonVariant.Danger,
                                        size: ControlSize.Sm,
                                        iconLeft: IconGlyph.Trash
                                    )
                                    Ui.button(
                                        theme,
                                        "清空工作区…",
                                        {
                                            =>
                                                clearError.value = ""
                                                clearOpen.value = true
                                        },
                                        variant: ButtonVariant.Danger,
                                        size: ControlSize.Sm,
                                        iconLeft: IconGlyph.Trash
                                    )
                                }.hug()
                        }
                    )

                    card(theme, tokens, "关于", IconGlyph.Settings, "Textura · 织理 — 单机优先的结构化执行工作台。",
                        body: {
                            => VStack(spacing: vp(8.0)) {
                                AboutRow(tokens, "版本", "0.1.0")
                                AboutRow(tokens, "技术栈", "仓颉 1.2.0 · CUI 0.9.6 · SDL3 · 自绘控件")
                                AboutRow(tokens, "数据模型",
                                    "统一 Item 内核：OKR / GTD / 甘特 / SOP 共享同一实体，各视图读取不同的数据块。")
                                HStack(spacing: vp(12.0)) {
                                    Paragraph("快捷键", sizePx: 12.5, lineHeightPx: 18.75, ink: c.textFaint)
                                        .width(76.0)
                                        .padding(0.0, 4.625, 0.0, 0.0)
                                    Ui.button(theme, "查看快捷键帮助", openShortcuts, variant: ButtonVariant.Ghost,
                                        size: ControlSize.Sm)
                                    Spacer()
                                }.crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
                            }.hug().fillWidth()
                        })
                }.hug().fillWidth()
            }
        }.crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
    }.hug().fillWidth()

    /* ---------------- import source (desktop fallback) ---------------- */
    Ui.modal(
        theme,
        importSourceOpen,
        {=> importSourceOpen.value = false},
        title: "导入工作区 JSON",
        description: "桌面重写暂未接入原生文件选择器",
        width: 480.0,
        footer: {
            =>
                Ui.button(theme, "取消", {=> importSourceOpen.value = false}, variant: ButtonVariant.Ghost,
                    size: ControlSize.Sm)
                Ui.button(theme, "读取目录文件", importFromFile, size: ControlSize.Sm)
                Ui.button(theme, "从剪贴板导入", importFromClipboard, variant: ButtonVariant.Primary,
                    size: ControlSize.Sm)
        },
        body: {
            =>
                WarningText(tokens,
                    "导入会整份替换当前工作区。CUI 视图拿不到 DesktopApp.openFileDialog，所以这里提供两条真实的读取路径：系统剪贴板，或工作区同目录下的 ${importFileName()}。")
                if (!importError.value.isEmpty()) {
                    Paragraph(importError.value, sizePx: 12.0, lineHeightPx: 18.0, ink: c.danger).padding(0.0, 12.0, 0.0,
                        0.0)
                }
        }
    )

    /* ---------------- import confirmation ---------------- */
    Ui.modal(
        theme,
        importConfirmOpen,
        {
            =>
                importConfirmOpen.value = false
                pendingText.value = ""
                importError.value = ""
        },
        title: "导入并覆盖工作区？",
        description: pendingSource.value,
        width: 480.0,
        footer: {
            =>
                Ui.button(
                    theme,
                    "取消",
                    {
                        =>
                            importConfirmOpen.value = false
                            pendingText.value = ""
                    },
                    variant: ButtonVariant.Ghost,
                    size: ControlSize.Sm
                )
                Ui.button(theme, "覆盖并导入", applyImport, variant: ButtonVariant.Danger, size: ControlSize.Sm)
        },
        body: {
            =>
                WarningText(tokens,
                    "导入会通过 importDocument 整份替换当前工作区；导入前会记录一次历史快照，可用 Ctrl+Z 回退整次导入。请确认这是你要导入的文件。")
                if (pendingEmpty.value) {
                    Paragraph("注意：这份文件是空工作区，导入后工作区将为空（不会自动播种演示数据）。", sizePx: 11.5,
                        lineHeightPx: 18.975, ink: c.textFaint).padding(0.0, 12.0, 0.0, 0.0)
                }
                if (!importError.value.isEmpty()) {
                    Paragraph("导入失败：${importError.value}", sizePx: 12.0, lineHeightPx: 18.0, ink: c.danger)
                        .padding(0.0, 12.0, 0.0, 0.0)
                }
                VStack(spacing: vp(8.0)) {
                    Divider(color: c.border)
                    AboutRow(tokens, "摘要", pendingCounts.value)
                }.hug().fillWidth().padding(0.0, 16.0, 0.0, 0.0)
        }
    )

    /* ---------------- reset to demo data ---------------- */
    Ui.modal(
        theme,
        resetOpen,
        {=> resetOpen.value = false},
        title: "重置为演示数据？",
        width: 480.0,
        footer: {
            =>
                Ui.button(theme, "取消", {=> resetOpen.value = false}, variant: ButtonVariant.Ghost,
                    size: ControlSize.Sm)
                Ui.button(theme, "覆盖并重置", applyReset, variant: ButtonVariant.Danger, size: ControlSize.Sm)
        },
        body: {
            =>
                WarningText(tokens,
                    "这会通过 importDocument 覆盖当前工作区，写入内置演示数据（目标、关键结果、SOP、官网改版项目与收件箱）。重置前会记录一次历史快照，可用 Ctrl+Z 回退整次重置。")
                if (!resetError.value.isEmpty()) {
                    Paragraph("重置失败：${resetError.value}", sizePx: 12.0, lineHeightPx: 18.0, ink: c.danger)
                        .padding(0.0, 12.0, 0.0, 0.0)
                }
        }
    )

    /* ---------------- clear workspace (danger, two-step) ---------------- */
    Ui.modal(
        theme,
        clearOpen,
        {=> clearOpen.value = false},
        title: "清空工作区？",
        width: 480.0,
        footer: {
            =>
                Ui.button(theme, "取消", {=> clearOpen.value = false}, variant: ButtonVariant.Ghost,
                    size: ControlSize.Sm)
                Ui.button(theme, "清空并保存", applyClear, variant: ButtonVariant.Danger, size: ControlSize.Sm)
        },
        body: {
            =>
                WarningText(tokens,
                    "清空会删除全部条目、领域、边与 SOP 运行记录，并立即原子保存到工作区文件。清空前会记录一次历史快照，可用 Ctrl+Z 回退整次清空。")
                if (!clearError.value.isEmpty()) {
                    Paragraph("清空失败：${clearError.value}", sizePx: 12.0, lineHeightPx: 18.0, ink: c.danger)
                        .padding(0.0, 12.0, 0.0, 0.0)
                }
        }
    )
}
