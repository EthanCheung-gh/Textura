package textura.shell

import cui.*
import std.math.*
import textura.core.data.*
import textura.ui.*

/*
 * AppShell status screens, ported verbatim from `src/app/AppShell.tsx`,
 * `RouteErrorBoundary.tsx` + `.css`, and `shell.css` `.loading-screen`.
 *
 * The Web build renders the loading screen while `store.status === 'loading'` and a
 * full-window error screen (with a retry button) on load failure; a crashed route keeps
 * the chrome and shows the recovery card inside `.shell-content`.
 */

/** `.loading-screen { place-items: center; gap: 12px; color: text-muted; font-size: 13px }`. */
public class LoadingScreenView <: Widget {
    private let tokens: ThemeTokens
    private let message: String
    private var frame = Rect.zero()

    public init(tokens: ThemeTokens, message: String) {
        this.tokens = tokens
        this.message = message
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        fillRect(ctx, frame, tokens.color.bg)
        let fontSize = fpSize(ctx, 13.0)
        let textLine = lineBox(13.0)
        // 34px spinner + 12px gap + one 13px line, centred as a column.
        let total = 34.0 + 12.0 + textLine
        let top = frame.y + (frame.h - total) / 2.0
        spinner(ctx, frame.centerX(), top + 17.0, 34.0, tokens)
        textCentered(ctx, message, Rect(frame.x, top + 46.0, frame.w, textLine), tokens.color.textMuted, fontSize, 400)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

/** `.loading-mark { 34x34; border: 2px solid border; border-top-color: accent; radius: 50% }`. */
func spinner(ctx: UiContext, cx: Float32, cy: Float32, side: Float32, tokens: ThemeTokens): Unit {
    let radius = side / 2.0 - 1.0
    ctx.renderer.strokeCircle(cx, cy, radius, Pen(width: 2.0, color: tokens.color.border))
    // CSS paints the top border arc; approximate that quarter with short strokes.
    var index = 0
    while (index < 12) {
        let a0 = -2.3561945 + Float32(index) * 0.13089969
        let a1 = a0 + 0.13089969
        ctx.renderer.strokeLine(
            cx + cosF(a0) * radius,
            cy + sinF(a0) * radius,
            cx + cosF(a1) * radius,
            cy + sinF(a1) * radius,
            Pen(width: 2.0, color: tokens.color.accent)
        )
        index += 1
    }
}

func cosF(value: Float32): Float32 {
    Float32(cos(Float64(value)))
}

func sinF(value: Float32): Float32 {
    Float32(sin(Float64(value)))
}

/** `AppShell` load-error branch: `<strong>工作区加载失败</strong>` + muted reason + 重试. */
public func buildWorkspaceErrorScreen(theme: Theme, message: String, onRetry: () -> Unit): Unit {
    let tokens = tokensOf(theme)
    let c = tokens.color
    ZStack {
        LoadingScreenView(tokens, "")
        VStack(spacing: vp(12.0)) {
            Label("工作区加载失败").fontSize(Length(13.0, LengthUnit.Fp)).fontWeight(FontWeight(700))
                .foregroundColor(c.text)
            Label(message).fontSize(Length(13.0, LengthUnit.Fp)).foregroundColor(c.textMuted).wrap()
            Ui.button(theme, "重试", onRetry, variant: ButtonVariant.Secondary)
        }
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
    }.fillWidth().fillHeight()
}

/**
 * `RouteErrorBoundary.css`: 620px card, `margin: 8vh auto 0`, 32px padding, 14 radius,
 * 1px border + 3px danger left rule, `--shadow-1`, 12px column gap.
 */
public func buildRouteError(theme: Theme, message: String, store: AppStore): Unit {
    let tokens = tokensOf(theme)
    let c = tokens.color
    VStack(spacing: vp(0.0)) {
        HStack(spacing: vp(0.0)) {
            Spacer()
            ZStack {
                ErrorCardBackdrop(tokens)
                VStack(spacing: vp(tokens.space.s3)) {
                    // .route-error-eyebrow { 11px; 650; letter-spacing: .08em; danger-ink }
                    Label("视图渲染失败")
                        .fontSize(Length(11.0, LengthUnit.Fp))
                        .fontWeight(FontWeight(650))
                        .foregroundColor(c.dangerInk)
                    // .route-error-title { font-size: 20px; line-height: 1.3 }
                    Label("这个视图暂时无法显示")
                        .fontSize(Length(20.0, LengthUnit.Fp))
                        .fontWeight(FontWeight(650))
                        .foregroundColor(c.text)
                    Label("工作区数据仍在。可以返回今日、重新加载工作区，或查看数据目录后手动备份。")
                        .fontSize(Length(13.0, LengthUnit.Fp))
                        .foregroundColor(c.textMuted)
                        .wrap()
                    Label(message)
                        .fontSize(Length(11.0, LengthUnit.Fp))
                        .foregroundColor(c.textMuted)
                        .wrap()
                        .padding(vp(tokens.space.s3))
                        .background(c.surface2, tokens.radius.md)
                        .border(c.border, width: CHROME_BORDER, radius: tokens.radius.md)
                    HStack(spacing: vp(tokens.space.s2)) {
                        Ui.button(theme, "返回今日", {=> store.setRoute("dashboard")},
                            variant: ButtonVariant.Primary, size: ControlSize.Sm)
                        Ui.button(theme, "重新加载工作区", {=>
                            if (store.save()) {
                                store.reload()
                            }
                        }, variant: ButtonVariant.Secondary, size: ControlSize.Sm)
                        Ui.button(theme, "查看数据目录", {=>
                            let path = match (store.path()) {
                                case Some(value) => value
                                case None => "(未指定)"
                            }
                            store.notify("数据目录：${path}", tone: NoticeTone.Info)
                        }, variant: ButtonVariant.Ghost, size: ControlSize.Sm)
                    }.hug().padding(0.0, 4.0, 0.0, 0.0)
                }
                    .hug()
                    .fillWidth()
                    .padding(vp(tokens.space.s6))
            }.maxWidth(620.0).fillWidth()
            Spacer()
        }.fillWidth()
        Spacer()
    }.fillWidth().padding(0.0, 72.0, 0.0, 0.0)
}

/** Paints the `.route-error` surface under the card content (3px danger left rule). */
class ErrorCardBackdrop <: Widget {
    private let tokens: ThemeTokens
    private var frame = Rect.zero()

    init(tokens: ThemeTokens) {
        this.tokens = tokens
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(max(available.w, 0.0), max(available.h, 0.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let radius = tokens.radius.lg
        shadow1(ctx, tokens, frame, radius)
        fillRound(ctx, frame, radius, tokens.color.surface)
        // border-left: 3px solid var(--danger)
        fillRound(ctx, Rect(frame.x, frame.y, tokens.radius.md, frame.h), radius, tokens.color.danger)
        fillRound(ctx, Rect(frame.x + 3.0, frame.y, frame.w - 3.0, frame.h), radius, tokens.color.surface)
        strokeRound(ctx, frame, radius, CHROME_BORDER, tokens.color.border)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
