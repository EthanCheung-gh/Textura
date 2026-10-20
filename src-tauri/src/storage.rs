//! 单文档持久化：原子写 + 单次回滚备份 + 轮换备份（保留 30 份）。

use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::hash::{Hash, Hasher};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use chrono::{DateTime, Local, Utc};
use serde::{Deserialize, Serialize};

use crate::model::{now_iso, Workspace, WORKSPACE_VERSION};

pub const MAX_BACKUPS: usize = 30;
const WORKSPACE_FILE: &str = "workspace.json";
const BACKUP_FILE: &str = "workspace.json.bak";
const TMP_FILE: &str = "workspace.json.tmp";

#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("无法访问 {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("JSON 解析失败: {0}")]
    Json(#[from] serde_json::Error),
    #[error("非法备份名称: {0}")]
    InvalidBackupName(String),
    #[error("备份不存在: {0}")]
    BackupNotFound(String),
    #[error("工作区版本 {version} 高于当前应用支持的版本 {supported}；已保留副本：{copy}")]
    FutureVersion {
        version: u64,
        supported: u32,
        copy: String,
    },
}

fn io_error(path: &Path, source: std::io::Error) -> StorageError {
    StorageError::Io {
        path: path.display().to_string(),
        source,
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveInfo {
    pub saved_at: String,
    pub bytes: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageInfo {
    pub data_dir: String,
    pub workspace_path: String,
    pub backup_count: usize,
    pub revision: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupInfo {
    pub name: String,
    pub size: u64,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoadResult {
    pub workspace: Workspace,
    pub fresh_install: bool,
}

#[derive(Default)]
struct CacheState {
    hash: Option<u64>,
    saved_at: Option<String>,
    bytes: usize,
    revision: u64,
}

pub struct Storage {
    dir: PathBuf,
    state: Mutex<CacheState>,
    /// 串行化整段 save 临界区（备份、tmp、fsync、rename、rotation、缓存更新）。
    save_lock: Mutex<()>,
}

impl Storage {
    pub fn new(dir: PathBuf) -> Self {
        let storage = Self {
            dir,
            state: Mutex::new(CacheState::default()),
            save_lock: Mutex::new(()),
        };
        let _ = fs::create_dir_all(storage.data_dir());
        let _ = fs::create_dir_all(storage.backups_dir());
        storage
    }

    pub fn data_dir(&self) -> &Path {
        &self.dir
    }

    pub fn workspace_path(&self) -> PathBuf {
        self.dir.join(WORKSPACE_FILE)
    }

    fn rollback_path(&self) -> PathBuf {
        self.dir.join(BACKUP_FILE)
    }

    fn tmp_path(&self) -> PathBuf {
        self.dir.join(TMP_FILE)
    }

    pub fn backups_dir(&self) -> PathBuf {
        self.dir.join("backups")
    }

    fn backup_path_for_name(&self, name: &str) -> Result<PathBuf, StorageError> {
        let is_plain = !name.is_empty()
            && !name.contains('/')
            && !name.contains('\\')
            && !name.contains("..")
            && Path::new(name).components().count() == 1;
        if !is_plain || !name.starts_with("textura-") || !name.ends_with(".json") {
            return Err(StorageError::InvalidBackupName(name.to_string()));
        }
        let path = self.backups_dir().join(name);
        if !path.is_file() {
            return Err(StorageError::BackupNotFound(name.to_string()));
        }
        Ok(path)
    }

    /// 读取顺序：主文件 -> .bak -> 最新轮换备份 -> 空工作区。
    /// 未来版本文件会被拒绝（复制保留后返回错误），绝不回退并覆盖。
    pub fn load(&self) -> Result<LoadResult, StorageError> {
        let _guard = self.save_lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let main = self.workspace_path();
        let rollback = self.rollback_path();
        let backups = self.backup_files_newest_first();
        let has_any_source =
            main.is_file() || rollback.is_file() || !backups.is_empty();

        let mut candidates = vec![main, rollback];
        candidates.extend(backups);

        for path in candidates {
            if !path.is_file() {
                continue;
            }
            match read_workspace(&path) {
                Ok(workspace) => {
                    return Ok(LoadResult {
                        workspace: workspace.migrate(),
                        fresh_install: false,
                    })
                }
                Err(StorageError::FutureVersion { version, .. }) => {
                    let copy = self.copy_future_version(&path, version)?;
                    return Err(StorageError::FutureVersion {
                        version,
                        supported: WORKSPACE_VERSION,
                        copy: copy.display().to_string(),
                    });
                }
                Err(error) => {
                    eprintln!("[textura] 跳过无法读取的工作区 {}: {error}", path.display());
                }
            }
        }

        Ok(LoadResult {
            workspace: Workspace::empty(),
            fresh_install: !has_any_source,
        })
    }

    fn copy_future_version(&self, source: &Path, version: u64) -> Result<PathBuf, StorageError> {
        fs::create_dir_all(self.data_dir()).map_err(|e| io_error(self.data_dir(), e))?;
        let target = self
            .data_dir()
            .join(format!("workspace.future-v{version}.json"));
        if source != target {
            fs::copy(source, &target).map_err(|e| io_error(&target, e))?;
            if let Ok(file) = fs::File::open(&target) {
                let _ = file.sync_all();
            }
        }
        eprintln!(
            "[textura] 拒绝加载未来版本 {version}（支持 {WORKSPACE_VERSION}），副本：{}",
            target.display()
        );
        Ok(target)
    }

    /// 原子写：tmp -> fsync -> rename；写前把旧文件复制成 .bak。
    /// 内容哈希与上次成功写入一致时直接返回缓存结果，避免重复落盘。
    pub fn save(&self, workspace: &Workspace) -> Result<SaveInfo, StorageError> {
        // 整个写入过程持锁：避免并发 save 交替执行 backup/tmp/rename/rotation。
        let _guard = self.save_lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let json = serde_json::to_string(workspace)?;
        let hash = hash_bytes(json.as_bytes());
        let path = self.workspace_path();

        {
            let state = self.state.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            if state.hash == Some(hash) && path.is_file() {
                if let Some(saved_at) = state.saved_at.clone() {
                    return Ok(SaveInfo {
                        saved_at,
                        bytes: state.bytes,
                    });
                }
            }
        }

        fs::create_dir_all(self.data_dir()).map_err(|e| io_error(self.data_dir(), e))?;
        fs::create_dir_all(self.backups_dir())
            .map_err(|e| io_error(&self.backups_dir(), e))?;

        if path.is_file() {
            let rollback = self.rollback_path();
            if rollback.is_file() {
                fs::remove_file(&rollback).map_err(|e| io_error(&rollback, e))?;
            }
            fs::copy(&path, &rollback).map_err(|e| io_error(&rollback, e))?;
        }

        let tmp = self.tmp_path();
        {
            let mut file = fs::File::create(&tmp).map_err(|e| io_error(&tmp, e))?;
            file.write_all(json.as_bytes())
                .map_err(|e| io_error(&tmp, e))?;
            file.sync_all().map_err(|e| io_error(&tmp, e))?;
        }
        fs::rename(&tmp, &path).map_err(|e| io_error(&path, e))?;
        if let Ok(dir) = fs::File::open(self.data_dir()) {
            let _ = dir.sync_all();
        }

        self.write_rotation_backup(&json)?;
        self.rotate_backups()?;

        let saved_at = now_iso();
        let mut state = self.state.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        state.hash = Some(hash);
        state.saved_at = Some(saved_at.clone());
        state.bytes = json.len();
        state.revision += 1;
        Ok(SaveInfo {
            saved_at,
            bytes: json.len(),
        })
    }

    fn write_rotation_backup(&self, json: &str) -> Result<(), StorageError> {
        let dir = self.backups_dir();
        fs::create_dir_all(&dir).map_err(|e| io_error(&dir, e))?;
        let stamp = Local::now().format("%Y%m%d-%H%M%S").to_string();
        let mut name = format!("textura-{stamp}.json");
        let mut counter = 2;
        while dir.join(&name).exists() {
            name = format!("textura-{stamp}-{counter}.json");
            counter += 1;
        }
        let path = dir.join(&name);
        let tmp = dir.join(format!("{name}.tmp"));
        {
            let mut file = fs::File::create(&tmp).map_err(|e| io_error(&tmp, e))?;
            file.write_all(json.as_bytes())
                .map_err(|e| io_error(&tmp, e))?;
            file.sync_all().map_err(|e| io_error(&tmp, e))?;
        }
        fs::rename(&tmp, &path).map_err(|e| io_error(&path, e))?;
        Ok(())
    }

    fn backup_files_newest_first(&self) -> Vec<PathBuf> {
        let Ok(entries) = fs::read_dir(self.backups_dir()) else {
            return Vec::new();
        };
        let mut files: Vec<(std::time::SystemTime, PathBuf)> = entries
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| is_backup_file(path))
            .map(|path| {
                let modified = fs::metadata(&path)
                    .and_then(|meta| meta.modified())
                    .unwrap_or(std::time::UNIX_EPOCH);
                (modified, path)
            })
            .collect();
        files.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| b.1.cmp(&a.1)));
        files.into_iter().map(|(_, path)| path).collect()
    }

    fn rotate_backups(&self) -> Result<(), StorageError> {
        let mut files: Vec<(std::time::SystemTime, PathBuf)> = self
            .backup_files_newest_first()
            .into_iter()
            .filter_map(|path| {
                fs::metadata(&path)
                    .and_then(|meta| meta.modified())
                    .ok()
                    .map(|modified| (modified, path))
            })
            .collect();
        // 新 -> 旧；删除第 31 份之后的所有文件。
        files.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| b.1.cmp(&a.1)));
        for (_, path) in files.into_iter().skip(MAX_BACKUPS) {
            fs::remove_file(&path).map_err(|e| io_error(&path, e))?;
        }
        Ok(())
    }

    pub fn list_backups(&self) -> Vec<BackupInfo> {
        self.backup_files_newest_first()
            .into_iter()
            .filter_map(|path| {
                let meta = fs::metadata(&path).ok()?;
                let created_at = meta
                    .modified()
                    .map(|time| {
                        let datetime: DateTime<Utc> = time.into();
                        datetime.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
                    })
                    .unwrap_or_else(|_| now_iso());
                Some(BackupInfo {
                    name: path.file_name()?.to_string_lossy().to_string(),
                    size: meta.len(),
                    created_at,
                })
            })
            .collect()
    }

    /// 另存一份修复后的工作区快照；绝不触碰主文件、.bak、轮换备份或缓存。
    pub fn save_repaired(&self, workspace: &Workspace) -> Result<String, StorageError> {
        let _guard = self
            .save_lock
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let json = format!("{}\n", serde_json::to_string_pretty(workspace)?);
        fs::create_dir_all(self.data_dir()).map_err(|e| io_error(self.data_dir(), e))?;

        let stamp = Local::now().format("%Y%m%d-%H%M%S").to_string();
        let mut name = format!("workspace.repaired-{stamp}.json");
        let mut counter = 2;
        while self.data_dir().join(&name).exists() {
            name = format!("workspace.repaired-{stamp}-{counter}.json");
            counter += 1;
        }
        let target = self.data_dir().join(&name);
        let tmp = self.data_dir().join(format!("{name}.tmp"));
        {
            let mut file = fs::File::create(&tmp).map_err(|e| io_error(&tmp, e))?;
            file.write_all(json.as_bytes())
                .map_err(|e| io_error(&tmp, e))?;
            file.sync_all().map_err(|e| io_error(&tmp, e))?;
        }
        fs::rename(&tmp, &target).map_err(|e| io_error(&target, e))?;
        if let Ok(dir) = fs::File::open(self.data_dir()) {
            let _ = dir.sync_all();
        }
        Ok(target.display().to_string())
    }

    pub fn restore(&self, name: &str) -> Result<Workspace, StorageError> {
        let path = self.backup_path_for_name(name)?;
        let workspace = match read_workspace(&path) {
            Ok(workspace) => workspace.migrate(),
            Err(StorageError::FutureVersion { version, .. }) => {
                let copy = self.copy_future_version(&path, version)?;
                return Err(StorageError::FutureVersion {
                    version,
                    supported: WORKSPACE_VERSION,
                    copy: copy.display().to_string(),
                });
            }
            Err(error) => return Err(error),
        };
        self.save(&workspace)?;
        Ok(workspace)
    }

    pub fn info(&self) -> StorageInfo {
        let (revision, _) = {
            let state = self.state.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            (state.revision, state.hash)
        };
        StorageInfo {
            data_dir: self.data_dir().display().to_string(),
            workspace_path: self.workspace_path().display().to_string(),
            backup_count: self.list_backups().len(),
            revision,
        }
    }

    /// 导出到用户选定路径，缩进 2 空格并校验 JSON 合法性。
    pub fn export(&self, json: &str, path: &str) -> Result<(), StorageError> {
        let value: serde_json::Value = serde_json::from_str(json)?;
        let pretty = format!("{}\n", serde_json::to_string_pretty(&value)?);
        let target = PathBuf::from(path);
        if let Some(parent) = target.parent() {
            if !parent.as_os_str().is_empty() {
                fs::create_dir_all(parent).map_err(|e| io_error(parent, e))?;
            }
        }
        {
            let mut file = fs::File::create(&target).map_err(|e| io_error(&target, e))?;
            file.write_all(pretty.as_bytes())
                .map_err(|e| io_error(&target, e))?;
            file.sync_all().map_err(|e| io_error(&target, e))?;
        }
        Ok(())
    }

    pub fn import(&self, path: &str) -> Result<String, StorageError> {
        let target = PathBuf::from(path);
        fs::read_to_string(&target).map_err(|e| io_error(&target, e))
    }
}

fn is_backup_file(path: &Path) -> bool {
    path.is_file()
        && path
            .file_name()
            .map(|name| {
                let name = name.to_string_lossy();
                name.starts_with("textura-") && name.ends_with(".json")
            })
            .unwrap_or(false)
}

fn read_workspace(path: &Path) -> Result<Workspace, StorageError> {
    let text = fs::read_to_string(path).map_err(|e| io_error(path, e))?;
    let value: serde_json::Value = serde_json::from_str(&text)?;
    let version = value.get("version").and_then(|value| value.as_u64()).unwrap_or(0);
    if version > WORKSPACE_VERSION as u64 {
        return Err(StorageError::FutureVersion {
            version,
            supported: WORKSPACE_VERSION,
            copy: String::new(),
        });
    }
    let workspace: Workspace = serde_json::from_value(value)?;
    Ok(workspace)
}

fn hash_bytes(bytes: &[u8]) -> u64 {
    let mut hasher = DefaultHasher::new();
    bytes.hash(&mut hasher);
    hasher.finish()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Item, WORKSPACE_VERSION};
    use tempfile::TempDir;

    fn workspace_named(title: &str) -> Workspace {
        Workspace {
            version: WORKSPACE_VERSION,
            items: vec![Item {
                id: "item_1".to_string(),
                kind: "action".to_string(),
                title: title.to_string(),
                notes: String::new(),
                parent_id: None,
                order: 1.0,
                status: "next".to_string(),
                tags: vec!["test".to_string()],
                area_id: None,
                created_at: now_iso(),
                updated_at: now_iso(),
                completed_at: None,
                okr: None,
                sop: None,
                gtd: None,
                gantt: None,
            }],
            ..Workspace::default()
        }
    }

    #[test]
    fn round_trip_preserves_workspace_and_rollback() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));

        let first = workspace_named("第一版");
        let info = storage.save(&first).unwrap();
        assert!(info.bytes > 0);
        assert!(storage.workspace_path().is_file());
        assert!(!storage.tmp_path().exists());

        let loaded = storage.load().unwrap().workspace;
        assert_eq!(loaded.items.len(), 1);
        assert_eq!(loaded.items[0].title, "第一版");

        // 同样的内容重复保存不落盘（哈希缓存）。
        let again = storage.save(&first).unwrap();
        assert_eq!(again.saved_at, info.saved_at);

        let second = workspace_named("第二版");
        storage.save(&second).unwrap();
        assert!(storage.rollback_path().is_file(), "旧文件应复制为 .bak");
        assert_eq!(storage.load().unwrap().workspace.items[0].title, "第二版");
    }

    #[test]
    fn corrupt_workspace_falls_back_to_rollback_then_backup() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));

        storage.save(&workspace_named("第一版")).unwrap();
        storage.save(&workspace_named("第二版")).unwrap();

        fs::write(storage.workspace_path(), "{ 这不是 JSON").unwrap();
        let recovered = storage.load().unwrap().workspace;
        assert_eq!(recovered.items[0].title, "第一版", "应回退到 .bak");

        fs::write(storage.rollback_path(), "broken").unwrap();
        let recovered = storage.load().unwrap().workspace;
        assert_eq!(recovered.items[0].title, "第二版", "应回退到最新轮换备份");
    }

    #[test]
    fn corrupt_everything_returns_empty_workspace() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));
        fs::create_dir_all(storage.data_dir()).unwrap();
        fs::write(storage.workspace_path(), "nope").unwrap();
        fs::write(storage.rollback_path(), "nope").unwrap();

        let result = storage.load().unwrap();
        assert!(result.workspace.items.is_empty());
        assert_eq!(result.workspace.version, WORKSPACE_VERSION);
        assert!(!result.fresh_install, "文件存在但损坏不等于首次安装");
    }

    #[test]
    fn rotates_backups_at_thirty() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));

        for index in 0..35 {
            storage
                .save(&workspace_named(&format!("版本 {index}")))
                .unwrap();
        }
        let backups = storage.list_backups();
        assert_eq!(backups.len(), MAX_BACKUPS);
        assert!(backups.iter().all(|backup| backup.name.ends_with(".json")));

        // 每份备份都可被恢复。
        let restored = storage.restore(&backups[0].name).unwrap();
        assert!(restored.items[0].title.starts_with("版本"));
    }

    #[test]
    fn migrates_older_version_on_load() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));
        fs::create_dir_all(storage.data_dir()).unwrap();
        fs::write(
            storage.workspace_path(),
            r#"{"version":0,"items":[],"edges":[],"areas":[],"runs":[],"updatedAt":""}"#,
        )
        .unwrap();

        let loaded = storage.load().unwrap().workspace;
        assert_eq!(loaded.version, WORKSPACE_VERSION);
        assert!(!loaded.updated_at.is_empty());
    }

    #[test]
    fn reports_fresh_install_only_when_no_source_exists() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));

        let first = storage.load().unwrap();
        assert!(first.fresh_install);
        assert!(first.workspace.items.is_empty());

        storage.save(&workspace_named("已有数据")).unwrap();
        let existing = storage.load().unwrap();
        assert!(!existing.fresh_install);
        assert_eq!(existing.workspace.items[0].title, "已有数据");

        // 空工作区文件存在时也不是首次安装，前端不得自动播种。
        storage.save(&Workspace::empty()).unwrap();
        let empty_but_existing = storage.load().unwrap();
        assert!(!empty_but_existing.fresh_install);
        assert!(empty_but_existing.workspace.items.is_empty());
    }

    #[test]
    fn rejects_future_version_and_preserves_a_copy() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));
        fs::create_dir_all(storage.data_dir()).unwrap();
        let future = r#"{"version":999,"items":[],"edges":[],"areas":[],"runs":[],"updatedAt":""}"#;
        fs::write(storage.workspace_path(), future).unwrap();

        let error = storage.load().unwrap_err();
        match error {
            StorageError::FutureVersion {
                version,
                supported,
                copy,
            } => {
                assert_eq!(version, 999);
                assert_eq!(supported, WORKSPACE_VERSION);
                assert!(copy.contains("workspace.future-v999.json"));
            }
            other => panic!("期望 FutureVersion，得到 {other:?}"),
        }

        let copy = storage.data_dir().join("workspace.future-v999.json");
        assert!(copy.is_file());
        assert_eq!(fs::read_to_string(&copy).unwrap(), future);
        assert_eq!(
            fs::read_to_string(storage.workspace_path()).unwrap(),
            future,
            "未来版本主文件不得被覆盖"
        );

        // 即使有可用旧备份，也不能回退覆盖。
        fs::write(
            storage.rollback_path(),
            serde_json::to_string(&workspace_named("旧版")).unwrap(),
        )
        .unwrap();
        assert!(matches!(
            storage.load(),
            Err(StorageError::FutureVersion { version: 999, .. })
        ));
    }

    #[test]
    fn rejects_invalid_confidence_and_metric_before_save() {
        let invalid_confidence = r#"{
            "version": 1,
            "items": [{
                "id": "kr", "kind": "keyresult", "title": "KR", "notes": "",
                "parentId": null, "order": 0, "status": "next", "tags": [],
                "areaId": null, "createdAt": "", "updatedAt": "", "completedAt": null,
                "okr": { "period": "2026-Q1", "confidence": 999 }
            }],
            "edges": [], "areas": [], "runs": [], "updatedAt": ""
        }"#;
        assert!(serde_json::from_str::<Workspace>(invalid_confidence).is_err());

        let invalid_metric = invalid_confidence.replace("999", "5").replace(
            r#""confidence": 5"#,
            r#""confidence": 5, "metric": { "start": "a", "target": 10, "current": 1, "unit": "%" }"#,
        );
        assert!(serde_json::from_str::<Workspace>(&invalid_metric).is_err());
    }

    #[test]
    fn concurrent_saves_are_serialized_and_never_mix() {
        use std::sync::Arc;
        use std::thread;

        let dir = TempDir::new().unwrap();
        let storage = Arc::new(Storage::new(dir.path().join("app-data")));
        let first = workspace_named("并发 A");
        let second = workspace_named("并发 B");

        let a_storage = Arc::clone(&storage);
        let a = thread::spawn(move || a_storage.save(&first).unwrap());
        let b_storage = Arc::clone(&storage);
        let b = thread::spawn(move || b_storage.save(&second).unwrap());
        a.join().unwrap();
        b.join().unwrap();

        let loaded = storage.load().unwrap().workspace;
        assert_eq!(loaded.items.len(), 1, "主文件不应被截断或混合");
        assert!(
            matches!(loaded.items[0].title.as_str(), "并发 A" | "并发 B"),
            "主文件应等于其中一次完整写入，实际：{}",
            loaded.items[0].title
        );
        assert_eq!(loaded.version, WORKSPACE_VERSION);
    }

    #[test]
    fn save_repaired_never_touches_the_main_workspace() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));
        storage.save(&workspace_named("主文件")).unwrap();
        let main_before = fs::read_to_string(storage.workspace_path()).unwrap();

        let repaired_path = storage
            .save_repaired(&workspace_named("环修复副本"))
            .unwrap();
        assert!(repaired_path.contains("workspace.repaired-"));
        assert!(std::path::Path::new(&repaired_path).is_file());
        let repaired: Workspace =
            serde_json::from_str(&fs::read_to_string(&repaired_path).unwrap()).unwrap();
        assert_eq!(repaired.items[0].title, "环修复副本");

        assert_eq!(
            fs::read_to_string(storage.workspace_path()).unwrap(),
            main_before,
            "修复副本不得覆盖主文件"
        );
        assert_eq!(
            storage.load().unwrap().workspace.items[0].title,
            "主文件"
        );
    }

    #[test]
    fn recovers_from_poisoned_locks_instead_of_panicking_forever() {
        use std::panic::{catch_unwind, AssertUnwindSafe};

        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));
        storage.save(&workspace_named("前置")).unwrap();

        let _ = catch_unwind(AssertUnwindSafe(|| {
            let _guard = storage.save_lock.lock().unwrap();
            panic!("poison save lock");
        }));
        let _ = catch_unwind(AssertUnwindSafe(|| {
            let _guard = storage.state.lock().unwrap();
            panic!("poison cache lock");
        }));

        // 锁中毒后仍应可读可写，而不是永久 panic。
        let info = storage.info();
        assert_eq!(info.revision, 1);
        storage.save(&workspace_named("恢复后")).unwrap();
        let loaded = storage.load().unwrap().workspace;
        assert_eq!(loaded.items[0].title, "恢复后");
    }

    #[test]
    fn rejects_path_traversal_in_backup_names() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));
        assert!(matches!(
            storage.restore("../workspace.json"),
            Err(StorageError::InvalidBackupName(_))
        ));
        assert!(matches!(
            storage.restore("textura-missing.json"),
            Err(StorageError::BackupNotFound(_))
        ));
    }

    #[test]
    fn export_writes_pretty_json_and_import_reads_it_back() {
        let dir = TempDir::new().unwrap();
        let storage = Storage::new(dir.path().join("app-data"));
        let ws = workspace_named("导出");
        let json = serde_json::to_string(&ws).unwrap();
        let target = dir.path().join("export/workspace.json");
        storage
            .export(&json, target.to_str().unwrap())
            .expect("export");

        let text = storage.import(target.to_str().unwrap()).unwrap();
        assert!(text.contains("\n  \"version\""));
        let parsed: Workspace = serde_json::from_str(&text).unwrap();
        assert_eq!(parsed.items[0].title, "导出");
    }
}
