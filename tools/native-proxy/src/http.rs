// ===== http.rs: HTTP 请求模块 =====
//
// 基于 reqwest + tokio，提供异步 HTTP 请求能力
// 对应 Legado 的 java.ajax/java.get/java.post API
//
// 添加新的 HTTP 功能（如下载、WebSocket 等）：
//   1. 写一个 pub async fn，标注 #[napi]
//   2. 在 Cargo.toml 添加需要的 feature（如 reqwest 的 stream）
//   3. 在 index.js 的 http 分组中添加 JS 降级实现

use napi::bindgen_prelude::*;
use napi_derive::napi;
use std::collections::HashMap;

/// HTTP 响应
#[napi(object)]
pub struct HttpResponse {
    /// HTTP 状态码
    pub status: u16,
    /// 响应体
    pub body: String,
    /// 响应头
    pub headers: HashMap<String, String>,
}

/// 异步 HTTP GET 请求
///
/// @example
/// ```js
/// const resp = await native.httpGet('https://example.com/api', { 'Accept': 'application/json' });
/// // { status: 200, body: '...', headers: { ... } }
/// ```
#[napi]
pub async fn http_get(url: String, headers: Option<HashMap<String, String>>) -> Result<HttpResponse> {
    let client = reqwest::Client::new();
    let mut req = client.get(&url);

    if let Some(h) = headers {
        for (key, value) in h {
            req = req.header(&key, &value);
        }
    }

    let resp = req
        .send()
        .await
        .map_err(|e| Error::from_reason(format!("HTTP GET error: {}", e)))?;

    let status = resp.status().as_u16();
    let mut resp_headers = HashMap::new();
    for (key, value) in resp.headers() {
        if let Ok(v) = value.to_str() {
            resp_headers.insert(key.to_string(), v.to_string());
        }
    }

    let body = resp
        .text()
        .await
        .map_err(|e| Error::from_reason(format!("Read body error: {}", e)))?;

    Ok(HttpResponse {
        status,
        body,
        headers: resp_headers,
    })
}

/// 异步 HTTP POST 请求
///
/// @example
/// ```js
/// const resp = await native.httpPost('https://example.com/api', 'key=value', { 'Content-Type': 'application/x-www-form-urlencoded' });
/// ```
#[napi]
pub async fn http_post(
    url: String,
    body: String,
    headers: Option<HashMap<String, String>>,
) -> Result<HttpResponse> {
    let client = reqwest::Client::new();
    let mut req = client.post(&url).body(body);

    if let Some(h) = headers {
        for (key, value) in h {
            req = req.header(&key, &value);
        }
    }

    let resp = req
        .send()
        .await
        .map_err(|e| Error::from_reason(format!("HTTP POST error: {}", e)))?;

    let status = resp.status().as_u16();
    let mut resp_headers = HashMap::new();
    for (key, value) in resp.headers() {
        if let Ok(v) = value.to_str() {
            resp_headers.insert(key.to_string(), v.to_string());
        }
    }

    let resp_body = resp
        .text()
        .await
        .map_err(|e| Error::from_reason(format!("Read body error: {}", e)))?;

    Ok(HttpResponse {
        status,
        body: resp_body,
        headers: resp_headers,
    })
}
