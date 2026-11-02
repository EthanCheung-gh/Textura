package textura.views.gtd

import std.collection.*
import cui.*
import textura.ui.*
import textura.views.gtd.logic as gl

/*
 * 项目健康度（ProjectPanel.tsx 1-95 + gtd.css:575-632）。
 *
 * 每个项目：名称 13/620 + 停滞/健康徽标 → `n / m 动作完成` · `k 未完成` · `p%`
 * → 5px 进度条 → 动作区（停滞时补「新建下一步」，恒有「查看下一步」）。
 */

func gtdProjectsSection(scene: GtdScene): Unit {
    let tokens = scene.tokens
    gtdSectionShell(scene, "projects") {
        gtdSectionHeader(scene, IconGlyph.Folder, "项目健康度", scene.projectCount)
        let health = gl.projectHealth(scene.gws)
        if (health.isEmpty()) {
            gtdEmptyBlock(scene, "还没有项目", "把需要多个动作完成的结果升级为项目。", IconGlyph.Folder)
        } else {
            VStack(spacing: vp(0.0)) {
                ForEachIndexed(health) {index, entry => projectRow(scene, entry, index == health.size - 1)}
            }.hug().fillWidth()
        }
    }
}

func projectRow(scene: GtdScene, entry: gl.ProjectHealth, last: Bool): Unit {
    let tokens = scene.tokens
    let progress = Float32(entry.progress)
    VStack(spacing: vp(0.0)) {
        // `.gtd-project { gap: 6px; padding: 12px 16px }`（gtd.css:581-587）
        VStack(spacing: vp(PROJECT_GAP)) {
            HStack(spacing: vp(SECTION_HEADING_GAP)) {
                GtdText(entry.project.title, PROJECT_NAME_SIZE, PROJECT_NAME_WEIGHT, tokens.color.text,
                    boxHeight: PROJECT_NAME_SIZE * LINE_HEIGHT, maxWidth: 200.0)
                Spacer()
                if (entry.stuck) {
                    gtdBadge(tokens, "停滞", BadgeTone.Danger, dot: true)
                } else {
                    gtdBadge(tokens, "健康", BadgeTone.Ok, dot: true)
                }
            }
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .hug()
                .fillWidth()
            HStack(spacing: vp(PROJECT_STATS_GAP)) {
                GtdText("${entry.done} / ${entry.total} 动作完成", PROJECT_STATS_SIZE, 400,
                    tokens.color.textFaint, boxHeight: PROJECT_STATS_SIZE * LINE_HEIGHT)
                Spacer()
                GtdText("${entry.open} 未完成", PROJECT_STATS_SIZE, 400, tokens.color.textFaint,
                    boxHeight: PROJECT_STATS_SIZE * LINE_HEIGHT)
                GtdText("${entry.progress}%", PROJECT_STATS_SIZE, 400, tokens.color.textMuted,
                    boxHeight: PROJECT_STATS_SIZE * LINE_HEIGHT)
            }
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .hug()
                .fillWidth()
            HStack(spacing: vp(0.0)) {
                Ui.progress(scene.theme, progress, tone: if (entry.stuck) {
                    ProgressTone.Danger
                } else if (entry.progress >= 100) {
                    ProgressTone.Ok
                } else {
                    ProgressTone.Accent
                }, size: ControlSize.Sm)
            }.hug().fillWidth()
            HStack(spacing: vp(PROJECT_ACTIONS_GAP)) {
                if (entry.stuck) {
                    Ui.button(scene.theme, "新建下一步",
                        {=> scene.run(gl.createNextActionForProject(entry.project, scene.placeholder("act"),
                            scene.now()))},
                        variant: ButtonVariant.Secondary, size: ControlSize.Sm, iconLeft: IconGlyph.Plus)
                }
                Ui.button(scene.theme, "查看下一步", {=> scene.focusSection("next")},
                    variant: ButtonVariant.Ghost, size: ControlSize.Sm)
                Spacer()
            }
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .hug()
                .fillWidth()
                .padding(vp(0.0), vp(PROJECT_ACTIONS_MT), vp(0.0), vp(0.0))
        }
            .hug()
            .fillWidth()
            .padding(vp(PROJECT_PAD_H), vp(PROJECT_PAD_V), vp(PROJECT_PAD_H), vp(PROJECT_PAD_V))
        if (!last) {
            gtdRule(tokens.color.border)
        }
    }.hug().fillWidth()
}
