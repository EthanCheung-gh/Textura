mod ai_proxy;
mod commands;
mod model;
mod storage;

use std::sync::Arc;
use tauri::Manager;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let data_dir = app.path().app_data_dir()?;
            app.manage(Arc::new(storage::Storage::new(data_dir)));
            Ok(())
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
        ])
        .run(tauri::generate_context!())
        .expect("error while running Textura");
}
