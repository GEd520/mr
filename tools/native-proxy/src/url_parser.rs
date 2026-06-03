// ===== url_parser.rs: URL 解析模块 =====
//
// 基于 url crate，提供 URL 解析和拼接能力
// 对应 Legado 的 URL/URI 处理需求
//
// 添加新的 URL 处理函数：
//   1. 写一个 pub fn，标注 #[napi]
//   2. 在 index.js 的 url 分组中添加 JS 降级实现

use napi::bindgen_prelude::*;
use napi_derive::napi;

/// URL 解析结果
#[napi(object)]
pub struct ParsedUrl {
    pub href: String,
    pub protocol: String,
    pub host: String,
    pub hostname: String,
    pub port: String,
    pub pathname: String,
    pub search: String,
    pub hash: String,
    pub origin: String,
}

/// 解析 URL，提取各组成部分
///
/// @example
/// ```js
/// const result = native.parseUrl('https://example.com:8080/path?q=1#hash');
/// // { href: '...', protocol: 'https:', hostname: 'example.com', port: '8080', ... }
/// ```
#[napi]
pub fn parse_url(raw_url: String) -> Result<ParsedUrl> {
    let parsed = url::Url::parse(&raw_url)
        .map_err(|e| Error::from_reason(format!("URL parse error: {}", e)))?;

    Ok(ParsedUrl {
        href: parsed.to_string(),
        protocol: parsed.scheme().to_string(),
        host: parsed.host_str().unwrap_or("").to_string(),
        hostname: parsed.host_str().unwrap_or("").to_string(),
        port: parsed.port().map(|p| p.to_string()).unwrap_or_default(),
        pathname: parsed.path().to_string(),
        search: parsed.query().map(|q| format!("?{}", q)).unwrap_or_default(),
        hash: parsed.fragment().map(|f| format!("#{}", f)).unwrap_or_default(),
        origin: parsed.origin().ascii_serialization(),
    })
}

/// 拼接 URL：基于 base 解析相对路径
///
/// @example
/// ```js
/// native.resolveUrl('https://example.com/base/', '../other')
/// // 'https://example.com/other'
/// ```
#[napi]
pub fn resolve_url(base: String, relative: String) -> Result<String> {
    let base_url = url::Url::parse(&base)
        .map_err(|e| Error::from_reason(format!("Base URL parse error: {}", e)))?;
    let resolved = base_url
        .join(&relative)
        .map_err(|e| Error::from_reason(format!("URL resolve error: {}", e)))?;
    Ok(resolved.to_string())
}
