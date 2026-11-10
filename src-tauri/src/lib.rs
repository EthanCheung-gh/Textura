mod ai_proxy;
mod commands;
mod lifecycle;
mod model;
mod storage;

use std::sync::Arc;
use tauri::{Manager, RunEvent, WindowEvent};

pub fn run() {
    // 诊断日志必须早于 Builder：builder 构造、资源加载、setup 都可能失败并表现为
    // 「静默退出」，没有这一步就永远看不到是谁先倒下。
    lifecycle::init();

    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let data_dir = app.path().app_data_dir()?;
            app.manage(Arc::new(storage::Storage::new(data_dir)));
            // 记录此刻已存在的 webview：labels 为空说明窗口/前端资源在进入 setup 前
            // 就没建起来，可与「setup 之后 webview 被销毁」直接区分。
            let mut labels: Vec<String> = app.webview_windows().keys().cloned().collect();
            labels.sort();
            lifecycle::log(
                "setup",
                &format!("webviews={} labels=[{}]", labels.len(), labels.join(",")),
            );
            Ok(())
        })
        .on_page_load(|webview, payload| {
            // 页面加载完成是「webview 真的活着」的第一个信号；只记 label，不记 URL
            // 与页面内容（避免把工作区路径写进日志）。
            if payload.event() == tauri::webview::PageLoadEvent::Finished {
                lifecycle::log("page_load", &format!("label={}", webview.label()));
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::load_workspace,
            commands::save_workspace,
            commands::storage_info,
            commands::list_backups,
            commands::restore_backup,
            commands::export_workspace,
            commands::import_workspace,
            commands::save_repaired_workspace,
            // AI 代理通道：桌面端绕开 CSP / CORS 直连模型网关。
            ai_proxy::ai_proxy,
        ]);

    // build() 与 run() 拆开：原来 `.run(context).expect(...)` 在构建失败时会 panic，
    // 而 release 下 `panic = "abort"` 连一行输出都没有。这里先落日志，再维持原行为。
    let app = match builder.build(tauri::generate_context!()) {
        Ok(app) => app,
        Err(err) => {
            lifecycle::log("run_returned", &format!("Err({err})"));
            panic!("error while running Textura: {err}");
        }
    };

    // 用 run_return 而不是 run：`App::run` 的文档明确写着「永不返回，结束时直接
    // std::process::exit」，那样 run_returned / process_exit 这两行就永远写不出来。
    // run_return 返回的正是原先 run 内部拿去 exit 的同一个退出码，这里原样交给
    // std::process::exit，退出码与原来完全一致（行为中性）。
    let exit_code = app.run_return(|_app_handle, event| match event {
        // 事件循环真正开始跑：与 setup 之间出现空档，说明卡在资源/窗口创建阶段。
        RunEvent::Ready => lifecycle::log("ready", ""),
        RunEvent::WindowEvent { label, event, .. } => match event {
            // (a) WM/用户点关闭：这一步之后如果没有 exit_requested，说明是被拦截或卡住。
            WindowEvent::CloseRequested { .. } => lifecycle::log(
                "window_event",
                &format!("label={label} event=close_requested"),
            ),
            // (c) 窗口真正消失（可能是谁调用了 destroy，也可能是崩溃）。
            WindowEvent::Destroyed => {
                lifecycle::log("window_event", &format!("label={label} event=destroyed"))
            }
            // Moved / Resized / Focused / ScaleFactorChanged / ThemeChanged 等噪声过大，
            // 全量记录会把真正有用的几行淹没在千行日志里，故过滤掉。
            _ => {}
        },
        // (b) 退出请求：code=None 表示用户/系统发起，code=Some(_) 表示代码里调了 exit()。
        RunEvent::ExitRequested { code, .. } => lifecycle::log(
            "exit_requested",
            &match code {
                Some(code) => format!("code={code}"),
                None => "code=None".to_string(),
            },
        ),
        RunEvent::Exit => lifecycle::log("exit", ""),
        _ => {}
    });

    // (e) 走到这里说明事件循环自己返回了，而不是被信号打死或 abort——
    // 这是「静默退出」最关键的分叉点：有 run_returned 就说明是正常收尾。
    lifecycle::log("run_returned", &format!("Ok code={exit_code}"));
    lifecycle::log("process_exit", &format!("code={exit_code} path=main-exit"));
    std::process::exit(exit_code);
}
