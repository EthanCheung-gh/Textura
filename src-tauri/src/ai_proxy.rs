//! AI 代理通道：桌面端（Tauri）通过 IPC 让 Rust 侧发起模型网关请求。
//!
//! 为什么需要它：webview 里的 `fetch` 既受 CSP `connect-src` 约束，也受浏览器
//! CORS 约束，直连模型网关常常直接失败。Rust 侧不受这两条限制，因此桌面端
//! 改走 `invoke('ai_proxy', ...)`；浏览器模式仍然走 `fetch`。
//!
//! 契约（与 `src/modules/ai/client.ts` 的传输层对齐）：
//! - **非 2xx 也是成功**：状态码与响应体原样带回，错误分类由前端 `mapFailure`
//!   统一决定（只有一套映射，不在 Rust 侧再分一套）；
//! - **失败是结构化的**：`Err` 一律是 `AiProxyError { kind, message }`，
//!   `kind ∈ { timeout, url, network }`，前端据此把「超时」与「地址/配置问题」
//!   分开提示，而不是一律当网络故障；
//! - `url` 只允许 `http` / `https`，拒绝空地址、无主机名、无法解析、
//!   链路本地 / 云元数据地址（不 panic）；
//! - `timeout_ms` 夹到 1_000..=180_000 毫秒，由 reqwest 总超时兜底；
//!   前端另有自己的超时竞争，这里只是防止请求永远挂着；
//! - **响应体上限 20 MiB**：流式累积，超限立即中止（坏网关不能撑爆内存）；
//! - **不得泄露密钥**：`headers`（尤其 `Authorization` / `x-api-key`）与请求
//!   `body` 绝不写日志、绝不进错误串；错误只说失败类别，不回显 URL 查询串。

use std::collections::HashMap;
use std::net::{IpAddr, Ipv6Addr};
use std::time::Duration;

use serde::{Deserialize, Serialize};

/// `timeout_ms` 下界（毫秒）：再短基本必然失败，没有意义。
pub const MIN_TIMEOUT_MS: u64 = 1_000;
/// `timeout_ms` 上界（毫秒）：3 分钟，覆盖长上下文补全但不至于永久占用连接。
pub const MAX_TIMEOUT_MS: u64 = 180_000;
/// 响应体上限（字节）：20 MiB。超过即中止，避免坏网关把进程内存吃光。
pub const MAX_BODY_BYTES: usize = 20 * 1024 * 1024;

/// 前端 `invoke('ai_proxy', { request })` 的入参。
///
/// `headers` 里可能含 `Authorization` / `x-api-key`，任何路径都不得回显。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiProxyRequest {
    pub url: String,
    pub headers: HashMap<String, String>,
    pub body: String,
    pub timeout_ms: u64,
}

/// 响应：状态码 + 原样响应体文本（非 2xx 也走这条成功路径）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiProxyResponse {
    pub status: u16,
    pub body: String,
}

/// 失败分类（wire 值即 `"timeout"` / `"url"` / `"network"`）。
///
/// - `Timeout`：本次请求超时，重试有意义；
/// - `Url`：目标地址或请求构造有问题（空地址 / 无主机 / 协议不支持 / 链路本地地址 /
///   header 非法），重试没有意义，应引导用户去设置里改配置；
/// - `Network`：连不上、TLS 失败、响应体过大等传输层问题。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum AiProxyErrorKind {
    Timeout,
    Url,
    Network,
}

/// 结构化错误：`{ "kind": "...", "message": "..." }`。
///
/// `message` 只描述失败类别，绝不含 headers（含 API Key）与请求 body。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiProxyError {
    pub kind: AiProxyErrorKind,
    pub message: String,
}

impl AiProxyError {
    fn new(kind: AiProxyErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }

    /// 地址 / 配置类错误（重试无意义）。
    fn url(message: impl Into<String>) -> Self {
        Self::new(AiProxyErrorKind::Url, message)
    }

    /// 传输类错误（可重试）。
    fn network(message: impl Into<String>) -> Self {
        Self::new(AiProxyErrorKind::Network, message)
    }
}

/* ------------------------------------------------------------------ */
/* URL 校验                                                            */
/* ------------------------------------------------------------------ */

/// `scheme://` 之后是否有主机名。
///
/// **只用于挑更精确的错误文案**：主机是否为空最终由 `Url::parse` 保证
/// （空 host 会解析失败），因此这里宁可简单，不重复实现 URL 语法。
fn missing_host(raw: &str) -> bool {
    let Some((scheme, rest)) = raw.split_once("://") else {
        return false;
    };
    if scheme.is_empty() {
        return false;
    }
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = authority
        .rsplit_once('@')
        .map(|(_, host)| host)
        .unwrap_or(authority);
    host.is_empty() || host.starts_with(':')
}

/// 取 URL 主机里的字面量 IP（IPv6 会带方括号）。域名返回 `None`。
fn literal_ip(host: &str) -> Option<IpAddr> {
    let bare = host
        .strip_prefix('[')
        .and_then(|rest| rest.strip_suffix(']'))
        .unwrap_or(host);
    bare.parse::<IpAddr>().ok()
}

/// 链路本地 / 云元数据地址：只拦这类「内网元数据」地址。
///
/// 刻意**不**封禁 `localhost` / `127.0.0.1` / 私有网段：自建网关（Ollama、
/// 内网 vLLM 等）是正常用法。
fn is_link_local_or_metadata(ip: IpAddr) -> bool {
    match ip {
        // 169.254.0.0/16（含 169.254.169.254 云元数据）。
        IpAddr::V4(v4) => {
            let octets = v4.octets();
            octets[0] == 169 && octets[1] == 254
        }
        IpAddr::V6(v6) => {
            // fe80::/10 链路本地。
            (v6.segments()[0] & 0xffc0) == 0xfe80
                // AWS IMDS：[fd00:ec2::254]。
                || v6 == Ipv6Addr::new(0xfd00, 0x0ec2, 0, 0, 0, 0, 0, 0x0254)
        }
    }
}

/// 只允许 http / https，且主机必须存在、不能是链路本地 / 元数据地址。
///
/// 三类地址错误各有**不同文案**（空 / 无法解析 / 缺主机），便于前端与用户区分；
/// 错误串**不含原始 url**（Base URL 可能带 `?key=...` 之类的查询串），
/// 也不含 headers / body。
fn validate_url(raw: &str) -> Result<reqwest::Url, AiProxyError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(AiProxyError::url("请求地址为空，请检查 Base URL"));
    }
    let url = match reqwest::Url::parse(trimmed) {
        Ok(url) => url,
        Err(_) if missing_host(trimmed) => {
            return Err(AiProxyError::url("请求地址缺少主机名，请检查 Base URL"))
        }
        Err(_) => {
            return Err(AiProxyError::url(
                "请求地址无法解析，请检查 Base URL 是否为完整 URL",
            ))
        }
    };
    match url.scheme() {
        "http" | "https" => {}
        other => {
            return Err(AiProxyError::url(format!(
                "不支持的请求协议：{other}（AI 代理仅允许 http / https）"
            )))
        }
    }
    // `Url::parse` 已保证 host 非空（空 host 直接解析失败），所以这里不再判空，
    // 改为拦链路本地 / 元数据地址。注意：不做 DNS 预解析，因此「解析到链路本地
    // 地址的域名」不在此处拦截。
    if let Some(ip) = literal_ip(url.host_str().unwrap_or("")) {
        if is_link_local_or_metadata(ip) {
            return Err(AiProxyError::url(
                "请求地址指向链路本地 / 云元数据地址，AI 代理已拒绝",
            ));
        }
    }
    Ok(url)
}

/// 把调用方给超时夹到 [`MIN_TIMEOUT_MS`, `MAX_TIMEOUT_MS`]。
fn clamp_timeout(timeout_ms: u64) -> u64 {
    timeout_ms.clamp(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)
}

/* ------------------------------------------------------------------ */
/* 传输错误分类（纯函数，便于单测）                                     */
/* ------------------------------------------------------------------ */

/// 从 `reqwest::Error` 提取的判定事实。
///
/// 真实的 `reqwest::Error` 无法在单测里构造，所以把「分类」与「取事实」拆开：
/// 分类与文案是纯函数，可以逐分支覆盖。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
struct TransportFacts {
    timeout: bool,
    connect: bool,
    redirect: bool,
    body: bool,
    request: bool,
}

fn transport_facts(error: &reqwest::Error) -> TransportFacts {
    TransportFacts {
        timeout: error.is_timeout(),
        connect: error.is_connect(),
        redirect: error.is_redirect(),
        body: error.is_body() || error.is_decode(),
        request: error.is_request(),
    }
}

/// 事实 → `kind`：超时单独成一档（前端提示「可重试」而不是「检查网络」），
/// 其余一律 `network`。
fn classify(facts: TransportFacts) -> AiProxyErrorKind {
    if facts.timeout {
        AiProxyErrorKind::Timeout
    } else {
        AiProxyErrorKind::Network
    }
}

/// 事实 → 中文文案。
///
/// 刻意不使用 `reqwest::Error` 的 `Display`（它会带出完整 URL，可能含查询串里的
/// 凭据），只按类别给文案；headers 与 body 一律不提。
fn describe(facts: TransportFacts, timeout: Duration) -> String {
    if facts.timeout {
        return format!(
            "请求超时（{} 毫秒），请检查网络或稍后重试",
            timeout.as_millis()
        );
    }
    if facts.connect {
        return "无法连接模型网关（DNS 解析、TLS 握手失败或网络不可达）".to_string();
    }
    if facts.redirect {
        return "模型网关返回了过多重定向，请检查 Base URL".to_string();
    }
    if facts.body {
        return "读取模型响应体失败".to_string();
    }
    if facts.request {
        return "请求发送失败，请检查 Base URL 与请求头".to_string();
    }
    "模型网关请求失败".to_string()
}

fn transport_error(error: &reqwest::Error, timeout: Duration) -> AiProxyError {
    let facts = transport_facts(error);
    AiProxyError::new(classify(facts), describe(facts, timeout))
}

/* ------------------------------------------------------------------ */
/* 响应体读取（带上限）                                                 */
/* ------------------------------------------------------------------ */

/// 响应体字节预算：超过上限即拒收，避免坏网关撑爆内存。
struct BodyBudget {
    limit: usize,
    used: usize,
}

impl BodyBudget {
    fn new(limit: usize) -> Self {
        Self { limit, used: 0 }
    }

    /// 收下 `len` 字节；会超限时返回 `false` 且不改变已用额度。
    fn take(&mut self, len: usize) -> bool {
        let next = self.used.saturating_add(len);
        if next > self.limit {
            return false;
        }
        self.used = next;
        true
    }
}

/// 流式读取响应体，超过 [`MAX_BODY_BYTES`] 立即中止。
async fn read_body(
    response: &mut reqwest::Response,
    timeout: Duration,
) -> Result<String, AiProxyError> {
    let mut budget = BodyBudget::new(MAX_BODY_BYTES);
    let mut collected: Vec<u8> = Vec::new();
    loop {
        match response.chunk().await {
            Ok(Some(chunk)) => {
                if !budget.take(chunk.len()) {
                    return Err(AiProxyError::network(format!(
                        "响应体过大（>{} MiB），已中止读取",
                        MAX_BODY_BYTES / (1024 * 1024)
                    )));
                }
                collected.extend_from_slice(&chunk);
            }
            Ok(None) => break,
            Err(error) => return Err(transport_error(&error, timeout)),
        }
    }
    Ok(String::from_utf8_lossy(&collected).into_owned())
}

/* ------------------------------------------------------------------ */
/* 命令                                                                */
/* ------------------------------------------------------------------ */

/// 桌面端 AI 代理：发一个 POST，把状态码与响应体原样带回。
///
/// 非 2xx 不算命令失败（前端沿用既有 `mapFailure` / `httpError` 分流），
/// 只有 URL 非法、请求头非法、传输层失败才返回 `Err(AiProxyError)`。
#[tauri::command]
pub async fn ai_proxy(request: AiProxyRequest) -> Result<AiProxyResponse, AiProxyError> {
    let url = validate_url(&request.url)?;
    let timeout = Duration::from_millis(clamp_timeout(request.timeout_ms));

    let client = reqwest::Client::builder()
        .timeout(timeout)
        .build()
        .map_err(|_| AiProxyError::network("初始化 HTTP 客户端失败"))?;

    let mut builder = client.post(url).body(request.body);
    for (name, value) in &request.headers {
        // 请求构造问题归 `url`（前端映射成 config：去设置改配置，而不是重试）。
        let header_name = reqwest::header::HeaderName::from_bytes(name.as_bytes())
            .map_err(|_| AiProxyError::url(format!("请求头名称不合法：{name}")))?;
        let header_value = reqwest::header::HeaderValue::from_str(value).map_err(|_| {
            // 只报头名，不回显头的值（可能是 API Key）。
            AiProxyError::url(format!("请求头 {name} 的值包含非法字符"))
        })?;
        builder = builder.header(header_name, header_value);
    }

    let mut response = builder
        .send()
        .await
        .map_err(|error| transport_error(&error, timeout))?;
    let status = response.status().as_u16();
    let body = read_body(&mut response, timeout).await?;

    Ok(AiProxyResponse { status, body })
}

#[cfg(test)]
mod tests {
    use super::{
        clamp_timeout, classify, describe, is_link_local_or_metadata, literal_ip, missing_host,
        validate_url, AiProxyError, AiProxyErrorKind, AiProxyRequest, BodyBudget, TransportFacts,
        MAX_BODY_BYTES, MAX_TIMEOUT_MS, MIN_TIMEOUT_MS,
    };
    use std::net::IpAddr;
    use std::time::Duration;

    fn kind_of(raw: &str) -> (AiProxyErrorKind, String) {
        let error = validate_url(raw).expect_err("应被拒绝");
        (error.kind, error.message)
    }

    #[test]
    fn accepts_http_and_https() {
        assert_eq!(
            validate_url("https://api.example.com/v1/chat/completions")
                .expect("https 应通过")
                .host_str(),
            Some("api.example.com")
        );
        assert_eq!(
            validate_url("  http://gw.internal:8080/openai/v1/messages  ")
                .expect("http 应通过")
                .host_str(),
            Some("gw.internal")
        );
    }

    #[test]
    fn allows_loopback_and_private_hosts() {
        // 自建网关是正常用法：localhost / 127.0.0.1 / 私有网段都不拦。
        for raw in [
            "http://localhost:11434/v1/chat/completions",
            "http://127.0.0.1:8000/v1/chat/completions",
            "http://192.168.1.10:8080/v1/chat/completions",
            "http://10.0.0.5/v1/chat/completions",
            "http://172.16.0.9/v1/chat/completions",
            "http://[::1]:8080/v1/chat/completions",
        ] {
            assert!(validate_url(raw).is_ok(), "{raw} 应被允许（自建网关）");
        }
    }

    #[test]
    fn rejects_non_http_schemes() {
        for raw in [
            "file:///etc/passwd",
            "ftp://example.com/model",
            "data:text/plain,hi",
            "ws://example.com/socket",
        ] {
            let (kind, message) = kind_of(raw);
            assert_eq!(kind, AiProxyErrorKind::Url);
            assert!(
                message.starts_with("不支持的请求协议："),
                "错误串应说明协议不支持：{message}"
            );
        }
    }

    #[test]
    fn rejects_blank_url_with_exact_message() {
        for raw in ["", "   ", "\n\t"] {
            let (kind, message) = kind_of(raw);
            assert_eq!(kind, AiProxyErrorKind::Url);
            assert_eq!(message, "请求地址为空，请检查 Base URL");
        }
    }

    #[test]
    fn rejects_missing_host_with_exact_message() {
        // 注意：`https:///v1/x` 会被 URL 规范化成 host=`v1`（合法 URL，放行），
        // 这里只覆盖真正解析不出主机名的形态。
        for raw in ["http://", "https://?q=1", "http://:8080/v1"] {
            let (kind, message) = kind_of(raw);
            assert_eq!(kind, AiProxyErrorKind::Url, "{raw}");
            assert_eq!(message, "请求地址缺少主机名，请检查 Base URL", "{raw}");
        }
    }

    #[test]
    fn rejects_unparseable_url_with_exact_message() {
        for raw in ["api.example.com", "not a url", "://nope"] {
            let (kind, message) = kind_of(raw);
            assert_eq!(kind, AiProxyErrorKind::Url, "{raw}");
            assert_eq!(
                message, "请求地址无法解析，请检查 Base URL 是否为完整 URL",
                "{raw}"
            );
            // 错误串不回显原始输入（可能含查询串凭据）。
            assert!(!message.contains(raw), "错误串不应回显原始地址：{message}");
        }
    }

    #[test]
    fn rejects_link_local_and_metadata_addresses() {
        for raw in [
            "http://169.254.169.254/latest/meta-data/",
            "http://169.254.1.1/v1/chat/completions",
            "http://[fd00:ec2::254]/latest/meta-data/",
            "http://[fe80::1]/v1/chat/completions",
        ] {
            let (kind, message) = kind_of(raw);
            assert_eq!(kind, AiProxyErrorKind::Url, "{raw}");
            assert_eq!(
                message, "请求地址指向链路本地 / 云元数据地址，AI 代理已拒绝",
                "{raw}"
            );
        }
    }

    #[test]
    fn classifies_literal_ip_and_brackets() {
        assert_eq!(
            literal_ip("169.254.169.254").map(is_link_local_or_metadata),
            Some(true)
        );
        assert_eq!(
            literal_ip("[fd00:ec2::254]").map(is_link_local_or_metadata),
            Some(true)
        );
        assert_eq!(
            literal_ip("[::1]").map(is_link_local_or_metadata),
            Some(false)
        );
        assert_eq!(
            literal_ip("127.0.0.1").map(is_link_local_or_metadata),
            Some(false)
        );
        // 域名不做 DNS 预解析。
        assert_eq!(literal_ip("gateway.local"), None);
    }

    #[test]
    fn missing_host_helper_matches_only_authorityless_urls() {
        assert!(missing_host("http://"));
        assert!(missing_host("http:///v1"));
        assert!(missing_host("http://:8080/v1"));
        assert!(!missing_host("http://example.com/v1"));
        assert!(!missing_host("http://user:pass@example.com/v1"));
        assert!(!missing_host("api.example.com"));
    }

    #[test]
    fn clamps_timeout_bounds() {
        assert_eq!(clamp_timeout(0), MIN_TIMEOUT_MS);
        assert_eq!(clamp_timeout(1), MIN_TIMEOUT_MS);
        assert_eq!(clamp_timeout(MIN_TIMEOUT_MS), MIN_TIMEOUT_MS);
        assert_eq!(clamp_timeout(60_000), 60_000);
        assert_eq!(clamp_timeout(MAX_TIMEOUT_MS), MAX_TIMEOUT_MS);
        assert_eq!(clamp_timeout(MAX_TIMEOUT_MS + 1), MAX_TIMEOUT_MS);
        assert_eq!(clamp_timeout(u64::MAX), MAX_TIMEOUT_MS);
    }

    #[test]
    fn timeout_fact_classifies_as_timeout_kind() {
        // 纯函数分类：超时单独一档，其余都是 network。
        assert_eq!(
            classify(TransportFacts {
                timeout: true,
                ..TransportFacts::default()
            }),
            AiProxyErrorKind::Timeout
        );
        assert_eq!(
            classify(TransportFacts {
                timeout: true,
                connect: true,
                ..TransportFacts::default()
            }),
            AiProxyErrorKind::Timeout
        );
        for facts in [
            TransportFacts::default(),
            TransportFacts {
                connect: true,
                ..TransportFacts::default()
            },
            TransportFacts {
                redirect: true,
                ..TransportFacts::default()
            },
            TransportFacts {
                body: true,
                ..TransportFacts::default()
            },
            TransportFacts {
                request: true,
                ..TransportFacts::default()
            },
        ] {
            assert_eq!(
                classify(facts),
                AiProxyErrorKind::Network,
                "非超时一律 network：{facts:?}"
            );
        }
    }

    #[test]
    fn describes_each_failure_class_distinctly() {
        let timeout = Duration::from_millis(60_000);
        let timeout_message = describe(
            TransportFacts {
                timeout: true,
                ..TransportFacts::default()
            },
            timeout,
        );
        assert!(timeout_message.contains("超时"), "{timeout_message}");
        assert!(timeout_message.contains("60000"), "{timeout_message}");

        let connect_message = describe(
            TransportFacts {
                connect: true,
                ..TransportFacts::default()
            },
            timeout,
        );
        assert!(connect_message.contains("无法连接"), "{connect_message}");

        let redirect_message = describe(
            TransportFacts {
                redirect: true,
                ..TransportFacts::default()
            },
            timeout,
        );
        assert!(redirect_message.contains("重定向"), "{redirect_message}");

        let body_message = describe(
            TransportFacts {
                body: true,
                ..TransportFacts::default()
            },
            timeout,
        );
        assert!(body_message.contains("响应体"), "{body_message}");

        let request_message = describe(
            TransportFacts {
                request: true,
                ..TransportFacts::default()
            },
            timeout,
        );
        assert!(
            request_message.contains("请求发送失败"),
            "{request_message}"
        );

        let fallback = describe(TransportFacts::default(), timeout);
        assert_eq!(fallback, "模型网关请求失败");

        // 六种文案互不相同，用户能区分到底哪一步失败。
        let all = [
            timeout_message,
            connect_message,
            redirect_message,
            body_message,
            request_message,
            fallback,
        ];
        for (index, left) in all.iter().enumerate() {
            for right in &all[index + 1..] {
                assert_ne!(left, right);
            }
        }
    }

    #[test]
    fn body_budget_rejects_over_limit_incrementally() {
        let mut budget = BodyBudget::new(10);
        assert!(budget.take(4));
        assert!(budget.take(6), "恰好等于上限应收下");
        assert!(!budget.take(1), "超过上限必须拒收");
        assert_eq!(MAX_BODY_BYTES, 20 * 1024 * 1024);

        // 超大分片不能靠加法溢出绕过上限。
        let mut budget = BodyBudget::new(1024);
        assert!(!budget.take(usize::MAX));
        assert!(budget.take(1024));
    }

    #[test]
    fn request_deserializes_from_camel_case_wire_format() {
        // 字段名契约：前端必须发 camelCase（timeoutMs）。
        let request: AiProxyRequest = serde_json::from_value(serde_json::json!({
            "url": "https://api.example.com/v1/chat/completions",
            "headers": { "authorization": "Bearer sk-test", "content-type": "application/json" },
            "body": "{\"model\":\"gpt-test\"}",
            "timeoutMs": 60_000u64,
        }))
        .expect("camelCase 字段名契约");

        assert_eq!(request.url, "https://api.example.com/v1/chat/completions");
        assert_eq!(
            request.headers.get("authorization").map(String::as_str),
            Some("Bearer sk-test")
        );
        assert_eq!(request.timeout_ms, 60_000);
        assert!(request.body.contains("gpt-test"));

        // 只认 camelCase：snake_case 会被拒（避免字段静默丢失）。
        assert!(serde_json::from_value::<AiProxyRequest>(serde_json::json!({
            "url": "https://api.example.com/v1/chat/completions",
            "headers": {},
            "body": "{}",
            "timeout_ms": 60_000u64,
        }))
        .is_err());
    }

    #[test]
    fn error_serializes_to_kind_and_message_only() {
        for (kind, wire) in [
            (AiProxyErrorKind::Timeout, "timeout"),
            (AiProxyErrorKind::Url, "url"),
            (AiProxyErrorKind::Network, "network"),
        ] {
            let value = serde_json::to_value(AiProxyError::new(kind, "文案")).expect("可序列化");
            assert_eq!(
                value,
                serde_json::json!({ "kind": wire, "message": "文案" })
            );
            // 只暴露 kind + message 两个键：绝不带 headers / body / url。
            assert_eq!(value.as_object().map(|object| object.len()), Some(2));
        }
    }

    #[test]
    fn response_serializes_status_and_body() {
        let value = serde_json::to_value(super::AiProxyResponse {
            status: 401,
            body: "{\"error\":\"invalid key\"}".to_string(),
        })
        .expect("可序列化");
        assert_eq!(
            value,
            serde_json::json!({ "status": 401, "body": "{\"error\":\"invalid key\"}" })
        );
    }

    #[test]
    fn link_local_predicate_covers_documented_ranges() {
        let blocked = ["169.254.0.1", "169.254.255.255", "fe80::1", "fd00:ec2::254"];
        for raw in blocked {
            let ip: IpAddr = raw.parse().expect("合法 IP");
            assert!(is_link_local_or_metadata(ip), "{raw} 应被拦");
        }
        let allowed = [
            "8.8.8.8",
            "127.0.0.1",
            "192.168.0.1",
            "::1",
            "fd00:ec2::253",
        ];
        for raw in allowed {
            let ip: IpAddr = raw.parse().expect("合法 IP");
            assert!(!is_link_local_or_metadata(ip), "{raw} 不应被拦");
        }
    }
}
