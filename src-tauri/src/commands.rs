//! Tauri 命令：前端通过 `@tauri-apps/api/core.invoke` 调用。
//! 参数与返回值均使用 camelCase（结构体由 serde 统一处理）。

use std::sync::Arc;
use tauri::State;

use crate::model::Workspace;
use crate::storage::{BackupInfo, LoadResult, SaveInfo, Storage, StorageInfo};

fn err(error: impl std::fmt::Display) -> String {
    error.to_string()
}

fn join_error(context: &str, error: impl std::fmt::Display) -> String {
    format!("{context}：{error}")
}

#[tauri::command]
pub async fn load_workspace(storage: State<'_, Arc<Storage>>) -> Result<LoadResult, String> {
    let storage = storage.inner().clone();
    tauri::async_runtime::spawn_blocking(move || storage.load())
        .await
        .map_err(|error| join_error("加载工作区任务失败", error))?
        .map_err(err)
}

#[tauri::command]
pub async fn save_workspace(
    storage: State<'_, Arc<Storage>>,
    workspace: Workspace,
) -> Result<SaveInfo, String> {
    let storage = storage.inner().clone();
    tauri::async_runtime::spawn_blocking(move || storage.save(&workspace))
        .await
        .map_err(|error| join_error("保存工作区任务失败", error))?
        .map_err(err)
}

#[tauri::command]
pub fn storage_info(storage: State<'_, Arc<Storage>>) -> StorageInfo {
    storage.info()
}

#[tauri::command]
pub fn list_backups(storage: State<'_, Arc<Storage>>) -> Vec<BackupInfo> {
    storage.list_backups()
}

#[tauri::command]
pub async fn restore_backup(
    storage: State<'_, Arc<Storage>>,
    name: String,
) -> Result<Workspace, String> {
    let storage = storage.inner().clone();
    tauri::async_runtime::spawn_blocking(move || storage.restore(&name))
        .await
        .map_err(|error| join_error("恢复备份任务失败", error))?
        .map_err(err)
}

#[tauri::command]
pub async fn save_repaired_workspace(
    storage: State<'_, Arc<Storage>>,
    workspace: Workspace,
) -> Result<String, String> {
    let storage = storage.inner().clone();
    tauri::async_runtime::spawn_blocking(move || storage.save_repaired(&workspace))
        .await
        .map_err(|error| join_error("保存修复副本任务失败", error))?
        .map_err(err)
}

#[tauri::command]
pub fn export_workspace(
    storage: State<'_, Arc<Storage>>,
    json: String,
    path: String,
) -> Result<(), String> {
    storage.export(&json, &path).map_err(err)
}

#[tauri::command]
pub fn import_workspace(storage: State<'_, Arc<Storage>>, path: String) -> Result<String, String> {
    storage.import(&path).map_err(err)
}
