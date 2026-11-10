//! 启动 / 退出生命周期诊断日志。
//!
//! 为什么需要这个模块：应用偶尔会在启动后 5–120 秒内自行以 code 0 退出，
//! 且 stderr 与 journal 里**一行都没有**。没有日志时，以下几种原因完全无法区分：
//!
//! * (a) 窗口管理器 / 用户请求关闭；
//! * (b) Tauri 的 `ExitRequested` / `Exit`；
//! * (c) webview / window 被销毁；
//! * (d) Rust panic（release 下 `panic = "abort"`，默认什么都不打印）；
//! * (e) 事件循环自己返回（`run()` 回到 `main`，进程正常结束）。
//!
//! 本模块只做一件事：把上述每个节点各写一行到 `$HOME/.textura/logs/app.log`
//! 并同时镜像到 stderr。它**不改变**任何行为——不改退出码、不干预窗口逻辑、
//! 不捕获 panic 的后果，只留下证据。
//!
//! 约束：
//! * 不记录工作区内容、token、AI key；环境变量只采集白名单里的渲染相关项。
//! * 任何 IO 都必须 `let _ = ...` / `if let Ok(..)`，日志绝不 panic、绝不 abort
//!   （若日志自身 panic，`panic = "abort"` 会再造一次无法解释的静默退出）。

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

/// 单个日志文件的上限：512 KiB。超过即单次轮转到 `app.log.1`。
const MAX_LOG_BYTES: u64 = 512 * 1024;
const LOG_FILE_NAME: &str = "app.log";
const LOG_DIR_UNDER: &str = ".textura/logs";

/// 会改变渲染后端行为的环境变量白名单。
///
/// 只放这几个：它们决定 Wayland/X11、GDK 后端与 WebKit 合成路径，
/// 一旦「某些会话下必崩、另一些会话正常」，第一嫌疑就是它们。
/// 刻意**不含**任何 `*_KEY` / `*_TOKEN` 之类的变量。
const ENV_KEYS: &[&str] = &[
    "WAYLAND_DISPLAY",
    "DISPLAY",
    "XDG_SESSION_TYPE",
    "GDK_BACKEND",
    "WEBKIT_DISABLE_DMABUF_RENDERER",
    "WEBKIT_DISABLE_COMPOSITING_MODE",
    "HOME",
];

/// 解析后的日志文件路径：首次使用时确定，之后复用。
static LOG_PATH: OnceLock<PathBuf> = OnceLock::new();

/// 日志总开关。默认 `true`：即使 `init()` 没被调用（库被别处复用、单测）也保持
/// 「照旧写日志」，行为不变。
///
/// 唯一会关掉它的是 `init()` 里的探测性启动判断（见 `is_probe_launch`）。
static LOG_ENABLED: AtomicBool = AtomicBool::new(true);

/// 日志当前是否启用。探测性启动下为 `false`，此时 `log()` 连 `format_line` 都不做。
fn log_enabled() -> bool {
    LOG_ENABLED.load(Ordering::Relaxed)
}

// ---------------------------------------------------------------------------
// 纯函数部分（可离线、确定性单测）
// ---------------------------------------------------------------------------

/// 是否为「探测性启动」，即命令行带了 `--version` / `-V` / `--help` / `-h`。
///
/// 背景：本应用没有 argv 处理，`textura --version` 照样会把 GUI 拉起来。有人（脚本、
/// 打包检查、手工排查）戳一下版本号，就会在**用户真实的** `app.log` 里留下一整个
/// `start/setup/ready/page_load` 块，把真正的启动记录稀释掉。这类启动不承载诊断信息，
/// 因此不写日志。
///
/// 匹配口径（只看 argv[0] 之后的参数，且必须**整串精确相等**）：
/// * 命中：`--version`、`-V`、`--help`、`-h`——即 clap 默认的 version/help 短长写法；
/// * 不命中 `-v` / `--verbose`：这两个是「啰嗦输出」而不是「打印版本就退出」，扩展名
///   或者日志级别开关一旦被误判成探针，用户正常启动就会莫名其妙没有日志——宁可漏判，
///   不可错判。同理 `--version=…`、`--helpx` 这类前缀不做模糊匹配。
/// * argv[0] 本身不参与判断（它是程序路径，哪怕恰好叫 `--version` 也不算）。
///
/// 判断本身**不改变**行为：调用方仍然照常启动 GUI、退出码不变。
fn is_probe_launch(args: &[String]) -> bool {
    args.iter()
        .skip(1)
        .any(|arg| matches!(arg.as_str(), "--version" | "-V" | "--help" | "-h"))
}

/// 把任意 detail 压成单行：换行/回车/制表符转义，其余字符**原样保留**（不做脱敏，
/// 脱敏由调用方保证不传入敏感内容）。多行 detail 会把「一行一个事件」的日志拆坏，
/// 轮转与 grep 都会失效，所以在写盘前统一转义。
fn escape_inline(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            other => out.push(other),
        }
    }
    out
}

/// 组装一行日志，不含结尾换行：
/// `2026-11-10T16:40:12.345+08:00 [pid 1234] start version=0.2.0 ...`
fn format_line(
    ts: &chrono::DateTime<chrono::Local>,
    pid: u32,
    event: &str,
    detail: &str,
) -> String {
    // 固定毫秒精度：既能看出事件先后顺序，又不会因为纳秒位数不同而破坏列对齐。
    let stamp = ts.to_rfc3339_opts(chrono::SecondsFormat::Millis, false);
    let detail = escape_inline(detail);
    if detail.is_empty() {
        format!("{stamp} [pid {pid}] {}", escape_inline(event))
    } else {
        format!("{stamp} [pid {pid}] {} {detail}", escape_inline(event))
    }
}

/// 是否该轮转。用 `>=` 而不是 `>`：文件恰好等于阈值时也轮转，避免边界抖动。
fn should_rotate(current_len: u64, max_bytes: u64) -> bool {
    current_len >= max_bytes
}

/// `app.log` -> `app.log.1`。用 OsString 追加后缀，避免非 UTF-8 路径被破坏。
fn rotated_path(path: &Path) -> PathBuf {
    let mut raw = path.as_os_str().to_os_string();
    raw.push(".1");
    PathBuf::from(raw)
}

/// 候选日志目录，按优先级排列：`$HOME/.textura/logs`，其次 `<tmp>/.textura/logs`。
///
/// 纯函数，只决定「顺序」，是否可写由调用方实测。HOME 缺失、为空、或与 tmp 相同
/// 时自动去重，保证返回的候选列表里没有重复项。
fn candidate_dirs(home: Option<&Path>, temp: &Path) -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    if let Some(home) = home {
        if !home.as_os_str().is_empty() {
            dirs.push(home.join(LOG_DIR_UNDER));
        }
    }
    let temp_dir = temp.join(LOG_DIR_UNDER);
    if !dirs.iter().any(|d| d == &temp_dir) {
        dirs.push(temp_dir);
    }
    dirs
}

// ---------------------------------------------------------------------------
// 路径解析 / 写盘
// ---------------------------------------------------------------------------

/// 逐个尝试候选目录：能建目录、且能真正以追加方式打开日志文件的才采用。
/// 全部失败时退回 `temp_dir()`（此时写盘会静默失败，但绝不会 panic）。
fn pick_log_dir() -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let temp = std::env::temp_dir();
    for dir in candidate_dirs(home.as_deref(), &temp) {
        let probe = dir.join(LOG_FILE_NAME);
        // create_dir_all 对已存在但只读的目录也会返回 Ok，所以必须再试开一次文件，
        // 否则「HOME 可读不可写」会被误判为可用，日志就彻底丢了。
        if fs::create_dir_all(&dir).is_ok()
            && fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&probe)
                .is_ok()
        {
            return dir;
        }
    }
    temp
}

fn ensure_log_path() -> &'static PathBuf {
    LOG_PATH.get_or_init(|| pick_log_dir().join(LOG_FILE_NAME))
}

/// 超过阈值时轮转一次：先删旧的 `.1`，再把当前文件改名成 `.1`。
/// 失败（比如另一个进程正占用）时直接忽略，继续往原文件追加——
/// 宁可日志大一点，也不能因为轮转失败而停止记录。
fn rotate_if_needed(path: &Path) {
    let Ok(meta) = fs::metadata(path) else {
        return;
    };
    if !should_rotate(meta.len(), MAX_LOG_BYTES) {
        return;
    }
    let backup = rotated_path(path);
    let _ = fs::remove_file(&backup);
    let _ = fs::rename(path, &backup);
}

/// 追加一行到指定 sink。`enabled == false` 时**立即返回** `false`：不格式化、不写
/// stderr、不碰文件系统（连日志目录都不会被创建），因此对 `~/.textura/logs/app.log`
/// 是严格的零字节、零副作用。
///
/// `path` 作为参数而不是直接取全局路径，是为了让单测能指定一个临时 sink，从而确定性地
/// 断言「禁用时一个字都没写、启用时确实写了」。
fn log_to_path(path: &Path, enabled: bool, event: &str, detail: &str) -> bool {
    if !enabled {
        return false;
    }

    let line = format_line(&chrono::Local::now(), std::process::id(), event, detail);

    // 镜像到 stderr：终端启动时直接可见，不必去翻日志文件。
    // 用 writeln! 而不是 eprintln!：stderr 被关闭（EPIPE）时 eprintln! 自身会 panic，
    // 而「日志绝不能 panic」是硬约束。
    let _ = writeln!(std::io::stderr(), "{line}");

    rotate_if_needed(path);
    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(path) {
        // 每行单独 flush：进程被 SIGKILL / abort 时，缓冲区里的最后几行必须已经在盘上。
        let _ = file.write_all(line.as_bytes());
        let _ = file.write_all(b"\n");
        let _ = file.flush();
    }
    true
}

/// 追加一行。`event` 为事件名（`start` / `setup` / `ready` / ...），`detail` 为
/// `key=value` 形式的人类可读补充信息。
///
/// 即使 `init()` 没被调用也会工作（懒解析路径），这样任何早于 init 的日志都不会丢。
/// 但探测性启动（`--version` / `--help` 等）下整个函数是 no-op：一次 stderr 写、
/// 一次 `ensure_log_path()` 都不会发生。
pub fn log(event: &str, detail: &str) {
    // 开关判断必须在 `ensure_log_path()` 之前：那个函数会 create_dir_all。
    if !log_enabled() {
        return;
    }
    let _ = log_to_path(ensure_log_path(), true, event, detail);
}

// ---------------------------------------------------------------------------
// 初始化
// ---------------------------------------------------------------------------

/// 启动头部信息：版本、argv、cwd 与渲染相关环境变量。
fn start_detail() -> String {
    // pid 已在行首 `[pid N]` 里，这里不重复。
    let argv: Vec<String> = std::env::args()
        .map(|a| format!("\"{}\"", escape_inline(&a)))
        .collect();
    let cwd = std::env::current_dir()
        .map(|p| p.display().to_string())
        .unwrap_or_else(|_| "<unknown>".to_string());

    let mut parts = vec![
        format!("version={}", env!("CARGO_PKG_VERSION")),
        format!("argv=[{}]", argv.join(" ")),
        format!("cwd={cwd}"),
    ];
    for key in ENV_KEYS {
        // 未设置的显式写成 <unset>，而不是省略：缺失本身就是线索。
        let value = std::env::var(key).unwrap_or_else(|_| "<unset>".to_string());
        parts.push(format!("{key}={}", escape_inline(&value)));
    }
    parts.join(" ")
}

/// 安装 panic hook 并写启动头。
///
/// **必须**在 `tauri::Builder` 之前调用：builder 构造、`generate_context!` 资源校验、
/// `.setup()` 里都可能失败，这些阶段的失败同样会表现为「静默退出」。
///
/// 探测性启动（`--version` / `-V` / `--help` / `-h`）是唯一的例外：**什么都不装**
/// （不装 panic hook、不解析日志路径、不写启动头），并关掉日志开关，让后续 `log()`
/// 全部变成 no-op。目的是不往用户真实的 `app.log` 里写探针足迹。行为本身不变——
/// 进程照旧起 GUI、照旧走原来的退出码。
pub fn init() {
    if is_probe_launch(&std::env::args().collect::<Vec<_>>()) {
        LOG_ENABLED.store(false, Ordering::Relaxed);
        return;
    }

    // 先确保路径解析完成，失败也只体现在「日志写到 tmp」上，不影响启动。
    let _ = ensure_log_path();

    // 取回原有 hook 并在末尾调用它：只追加日志，不吞掉 panic 的既有行为
    // （release 下 `panic = "abort"`，退出码仍是原来的 abort 语义）。
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let payload = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| (*s).to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "<non-string panic payload>".to_string());
        let location = info
            .location()
            .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
            .unwrap_or_else(|| "<unknown>".to_string());

        // backtrace 只在用户显式要求时抓取：`force_capture` 开销不小（release 下
        // 一条 backtrace 可以长到几 KB），默认路径必须保持零成本。
        // `RUST_BACKTRACE=`（空串）与 `RUST_BACKTRACE=0` 都按「关闭」处理。
        let backtrace_enabled = std::env::var_os("RUST_BACKTRACE")
            .map(|v| {
                let v = v.to_string_lossy().into_owned();
                !v.is_empty() && v != "0"
            })
            .unwrap_or(false);
        let backtrace = if backtrace_enabled {
            format!("backtrace={:?}", std::backtrace::Backtrace::force_capture())
        } else {
            String::new()
        };

        log(
            "panic",
            &format!("payload={payload} location={location} {backtrace}").trim_end(),
        );
        previous(info);
    }));

    log("start", &start_detail());
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Local, TimeZone};

    fn fixed_ts() -> chrono::DateTime<Local> {
        Local
            .with_ymd_and_hms(2026, 11, 10, 16, 40, 12)
            .single()
            .expect("fixed local timestamp must be unambiguous")
    }

    #[test]
    fn format_line_has_expected_shape() {
        let line = format_line(&fixed_ts(), 1234, "start", "version=0.2.0");
        assert!(line.starts_with("2026-11-10T16:40:12.000"), "{line}");
        assert!(line.ends_with(" [pid 1234] start version=0.2.0"), "{line}");
        assert!(!line.contains('\n'));
    }

    #[test]
    fn format_line_keeps_detail_verbatim() {
        // 「不脱敏」是刻意的：日志只记录白名单字段，detail 原样落盘便于 grep。
        let detail = "label=main code=Some(0) a=b=c --flag";
        let line = format_line(&fixed_ts(), 7, "exit_requested", detail);
        assert!(
            line.ends_with(&format!("] exit_requested {detail}")),
            "{line}"
        );
        assert!(line.contains("a=b=c"));
    }

    #[test]
    fn format_line_escapes_control_characters() {
        let line = format_line(&fixed_ts(), 1, "panic", "msg=line1\nline2\r\ttab");
        assert!(!line.contains('\n'), "{line}");
        assert!(!line.contains('\r'), "{line}");
        assert!(!line.contains('\t'), "{line}");
        assert!(line.contains("msg=line1\\nline2\\r\\ttab"), "{line}");
    }

    #[test]
    fn format_line_without_detail_has_no_trailing_space() {
        let line = format_line(&fixed_ts(), 42, "exit", "");
        assert!(line.ends_with(" [pid 42] exit"), "{line}");
        assert!(!line.ends_with(' '));
    }

    #[test]
    fn should_rotate_only_at_or_above_threshold() {
        assert!(!should_rotate(0, MAX_LOG_BYTES));
        assert!(!should_rotate(MAX_LOG_BYTES - 1, MAX_LOG_BYTES));
        assert!(should_rotate(MAX_LOG_BYTES, MAX_LOG_BYTES));
        assert!(should_rotate(MAX_LOG_BYTES + 1, MAX_LOG_BYTES));
    }

    #[test]
    fn rotated_path_appends_single_rotation_suffix() {
        assert_eq!(
            rotated_path(Path::new("/home/u/.textura/logs/app.log")),
            PathBuf::from("/home/u/.textura/logs/app.log.1")
        );
        // 只保留一份历史：即使已是 .1 也只会再加后缀，不会被复用成 `.2` 之外的东西。
        assert_eq!(
            rotated_path(Path::new("/tmp/x/app.log.1")),
            PathBuf::from("/tmp/x/app.log.1.1")
        );
    }

    #[test]
    fn candidate_dirs_prefers_home_then_temp() {
        let dirs = candidate_dirs(Some(Path::new("/home/u")), Path::new("/tmp"));
        assert_eq!(
            dirs,
            vec![
                PathBuf::from("/home/u/.textura/logs"),
                PathBuf::from("/tmp/.textura/logs"),
            ]
        );
    }

    #[test]
    fn candidate_dirs_falls_back_to_temp_without_home() {
        assert_eq!(
            candidate_dirs(None, Path::new("/tmp")),
            vec![PathBuf::from("/tmp/.textura/logs")]
        );
        // 空 HOME（某些 systemd/容器环境下会是空串）同样视为缺失。
        assert_eq!(
            candidate_dirs(Some(Path::new("")), Path::new("/tmp")),
            vec![PathBuf::from("/tmp/.textura/logs")]
        );
    }

    #[test]
    fn candidate_dirs_dedupes_when_home_is_temp() {
        let dirs = candidate_dirs(Some(Path::new("/tmp")), Path::new("/tmp"));
        assert_eq!(dirs, vec![PathBuf::from("/tmp/.textura/logs")]);
    }

    #[test]
    fn env_keys_are_render_only_and_secret_free() {
        // 白名单守卫：有人往里面加 HTTP_PROXY 里的凭据或 AI key 时立刻红灯。
        assert_eq!(
            ENV_KEYS,
            &[
                "WAYLAND_DISPLAY",
                "DISPLAY",
                "XDG_SESSION_TYPE",
                "GDK_BACKEND",
                "WEBKIT_DISABLE_DMABUF_RENDERER",
                "WEBKIT_DISABLE_COMPOSITING_MODE",
                "HOME",
            ]
        );
        for key in ENV_KEYS {
            let upper = key.to_ascii_uppercase();
            assert!(!upper.contains("KEY"), "{key}");
            assert!(!upper.contains("TOKEN"), "{key}");
            assert!(!upper.contains("SECRET"), "{key}");
            assert!(!upper.contains("PROXY"), "{key}");
        }
    }

    #[test]
    fn start_detail_carries_version_and_env_subset() {
        let detail = start_detail();
        assert!(
            detail.contains(&format!("version={}", env!("CARGO_PKG_VERSION"))),
            "{detail}"
        );
        assert!(detail.contains("argv=["), "{detail}");
        assert!(detail.contains("cwd="), "{detail}");
        for key in ENV_KEYS {
            assert!(
                detail.contains(&format!("{key}=")),
                "missing {key}: {detail}"
            );
        }
        // 单行保证：detail 里不能出现真实换行。
        assert!(!detail.contains('\n'), "{detail}");
    }

    /// 表驱动的 argv 构造：避免每条用例都写一遍 `to_string()`。
    fn argv(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| (*s).to_string()).collect()
    }

    #[test]
    fn is_probe_launch_matches_version_and_help_only() {
        // (argv, 期望是否探针)。argv[0] 一律是程序路径。
        let cases: Vec<(Vec<&str>, bool)> = vec![
            // 空 argv：连 argv[0] 都没有，自然不是探针。
            (vec![], false),
            // 只有程序路径：正常启动。
            (vec!["/usr/bin/textura"], false),
            (vec!["textura"], false),
            // 四种命中写法。
            (vec!["/usr/bin/textura", "--version"], true),
            (vec!["/usr/bin/textura", "-V"], true),
            (vec!["/usr/bin/textura", "--help"], true),
            (vec!["/usr/bin/textura", "-h"], true),
            // 混在路径/其它参数里也命中（只看是否某个参数整串相等）。
            (vec!["/usr/bin/textura", "--version", "/tmp/ws"], true),
            (vec!["/usr/bin/textura", "/home/u/notes.md", "--help"], true),
            (vec!["/home/u/--version", "x"], false),
            // `-v` / `--verbose` 是「啰嗦输出」，不是「打印版本就退出」：必须为 false。
            (vec!["/usr/bin/textura", "--verbose"], false),
            (vec!["/usr/bin/textura", "-v"], false),
            (vec!["/usr/bin/textura", "--verbose", "-v"], false),
            // 不做前缀 / 模糊匹配。
            (vec!["/usr/bin/textura", "--versionx"], false),
            (vec!["/usr/bin/textura", "--version=0.2.0"], false),
            (vec!["/usr/bin/textura", "--help-all"], false),
            // argv[0] 本身不参与判断，哪怕它恰好长得像探针参数。
            (vec!["--version"], false),
            (vec!["-h", "--version"], true),
        ];

        for (args, expected) in &cases {
            assert_eq!(
                is_probe_launch(&argv(args)),
                *expected,
                "argv={args:?} 期望 is_probe_launch={expected}"
            );
        }
    }

    #[test]
    fn disabled_logger_writes_zero_bytes_to_sink() {
        use std::sync::atomic::AtomicUsize;
        static SEQ: AtomicUsize = AtomicUsize::new(0);

        let dir = std::env::temp_dir().join(format!(
            "textura-lifecycle-test-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("temp dir");
        let path = dir.join(LOG_FILE_NAME);

        // 禁用：不留文件、不留轮转档，返回值也明确告知「没写」。
        assert!(!log_to_path(&path, false, "start", "version=0.2.0"));
        assert!(!path.exists(), "禁用时不应创建 {}", path.display());
        assert!(!rotated_path(&path).exists());

        // 同一 sink、同一行入参，启用后必须写进去——证明上面「没写」确实来自开关。
        assert!(log_to_path(&path, true, "start", "version=0.2.0"));
        let content = fs::read_to_string(&path).expect("log file");
        assert_eq!(content.lines().count(), 1, "{content}");
        assert!(content.contains("] start version=0.2.0"), "{content}");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn probe_launch_disables_log_without_resolving_path() {
        // 全局开关的端到端效果：关掉之后 `log()` 连路径都不解析，
        // 因此 `LOG_PATH` 保持未初始化（没有 create_dir_all，也就没有零字节文件）。
        let path_was_set = LOG_PATH.get().is_some();
        let previous = LOG_ENABLED.swap(false, Ordering::Relaxed);

        log("start", "probe-should-not-write");
        log("page_load", "label=main");

        LOG_ENABLED.store(previous, Ordering::Relaxed);
        assert_eq!(
            LOG_PATH.get().is_some(),
            path_was_set,
            "禁用期间不应解析日志路径"
        );
        assert_eq!(log_enabled(), previous, "开关必须被还原");
    }
}
