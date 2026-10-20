//! Tauri 命令：前端通过 `@tauri-apps/api/core.invoke` 调用。
//! 参数与返回值均使用 camelCase（结构体由 serde 统一处理）。

use tauri::State;

use crate::model::Workspace;
use crate::storage::{BackupInfo, SaveInfo, Storage, StorageInfo};

fn err(error: impl std::fmt::Display) -> String {
    error.to_string()
}

#[tauri::command]
pub fn load_workspace(storage: State<'_, Storage>) -> Workspace {
    storage.load()
}

#[tauri::command]
pub fn save_workspace(
    storage: State<'_, Storage>,
    workspace: Workspace,
) -> Result<SaveInfo, String> {
    storage.save(&workspace).map_err(err)
}

#[tauri::command]
pub fn storage_info(storage: State<'_, Storage>) -> StorageInfo {
    storage.info()
}

#[tauri::command]
pub fn list_backups(storage: State<'_, Storage>) -> Vec<BackupInfo> {
    storage.list_backups()
}

#[tauri::command]
pub fn restore_backup(storage: State<'_, Storage>, name: String) -> Result<Workspace, String> {
    storage.restore(&name).map_err(err)
}

#[tauri::command]
pub fn export_workspace(
    storage: State<'_, Storage>,
    json: String,
    path: String,
) -> Result<(), String> {
    storage.export(&json, &path).map_err(err)
}

#[tauri::command]
pub fn import_workspace(storage: State<'_, Storage>, path: String) -> Result<String, String> {
    storage.import(&path).map_err(err)
}
