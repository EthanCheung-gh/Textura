//! 工作区领域模型。字段与前端 `src/core/model.ts` 一一对应。
//! 所有结构体使用 camelCase 序列化，与 TypeScript 契约保持一致。

use serde::{Deserialize, Serialize};

pub const WORKSPACE_VERSION: u32 = 1;

fn default_version() -> u32 {
    WORKSPACE_VERSION
}

pub fn now_iso() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Workspace {
    /// 低版本会在 load 时迁移到当前版本。
    #[serde(default = "default_version")]
    pub version: u32,
    #[serde(default)]
    pub items: Vec<Item>,
    #[serde(default)]
    pub edges: Vec<Edge>,
    #[serde(default)]
    pub areas: Vec<Area>,
    #[serde(default)]
    pub runs: Vec<SopRunEntry>,
    #[serde(default)]
    pub updated_at: String,
}

impl Default for Workspace {
    fn default() -> Self {
        Self {
            version: WORKSPACE_VERSION,
            items: Vec::new(),
            edges: Vec::new(),
            areas: Vec::new(),
            runs: Vec::new(),
            updated_at: now_iso(),
        }
    }
}

impl Workspace {
    pub fn empty() -> Self {
        Self::default()
    }

    /// 单向迁移：只处理 version < 当前版本的工作区。
    /// v0 -> v1 没有结构性字段变化，仅补齐缺失集合并提升版本号。
    pub fn migrate(mut self) -> Self {
        if self.version < WORKSPACE_VERSION {
            self.version = WORKSPACE_VERSION;
        }
        if self.updated_at.is_empty() {
            self.updated_at = now_iso();
        }
        self
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Item {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub notes: String,
    pub parent_id: Option<String>,
    pub order: f64,
    pub status: String,
    pub tags: Vec<String>,
    pub area_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub completed_at: Option<String>,
    pub okr: Option<OkrData>,
    pub sop: Option<SopData>,
    pub gtd: Option<GtdData>,
    pub gantt: Option<GanttData>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct OkrData {
    pub period: String,
    pub confidence: u8,
    pub metric: Option<Metric>,
    pub kr_owner: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Metric {
    pub start: f64,
    pub target: f64,
    pub current: f64,
    pub unit: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SopData {
    pub node_type: String,
    pub canvas: Canvas,
    pub checklist: Vec<ChecklistEntry>,
    pub owner: Option<String>,
    pub duration_min: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Canvas {
    pub x: f64,
    pub y: f64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ChecklistEntry {
    pub id: String,
    pub text: String,
    pub done: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct GtdData {
    pub captured_at: String,
    pub clarified: bool,
    pub context: Option<String>,
    pub energy: Option<String>,
    pub waiting_for: Option<String>,
    pub two_minute_candidate: Option<bool>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct GanttData {
    pub start: Option<String>,
    pub end: Option<String>,
    pub progress: f64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Edge {
    pub id: String,
    pub from: String,
    pub to: String,
    #[serde(rename = "type")]
    pub edge_type: String,
    pub label: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Area {
    pub id: String,
    pub name: String,
    pub color: String,
    pub order: f64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SopRunEntry {
    pub id: String,
    pub sop_id: String,
    pub step_id: String,
    pub at: String,
    pub result: String,
    pub note: String,
}
