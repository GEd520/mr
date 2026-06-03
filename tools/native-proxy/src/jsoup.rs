// ===== jsoup.rs: HTML 解析模块 =====
//
// 基于 scraper crate，提供 CSS 选择器解析能力
// 对应 Legado 的 java.jsoup.* API
//
// 添加新的 HTML 解析函数：
//   1. 写一个 pub fn，标注 #[napi]
//   2. 参数和返回值用 napi 类型（String, Result<T>, #[napi(object)] struct）
//   3. 在 index.js 的 jsoup 分组中添加 JS 降级实现

use napi::bindgen_prelude::*;
use napi_derive::napi;
use scraper::{Html, Selector};

/// CSS 选择器查询结果
#[napi(object)]
pub struct JsoupResult {
    /// 元素内文本
    pub text: String,
    /// 元素 HTML
    pub html: String,
    /// 元素属性（需通过 jsoup_get_attr 单独获取）
    pub attr: String,
    /// 元素标签名
    pub tag: String,
}

/// 解析 HTML，按 CSS 选择器提取所有匹配元素
///
/// @example
/// ```js
/// const results = native.jsoupSelect('<div class="item">hello</div>', '.item');
/// // [{ text: 'hello', html: '<div class="item">hello</div>', attr: '', tag: 'div' }]
/// ```
#[napi]
pub fn jsoup_select(html: String, selector: String) -> Result<Vec<JsoupResult>> {
    let document = Html::parse_document(&html);
    let sel = Selector::parse(&selector)
        .map_err(|e| Error::from_reason(format!("Invalid selector: {}", e)))?;

    let results: Vec<JsoupResult> = document
        .select(&sel)
        .map(|el| JsoupResult {
            text: el.text().collect::<Vec<_>>().join(""),
            html: el.html(),
            attr: String::new(),
            tag: el.value().name().to_string(),
        })
        .collect();

    Ok(results)
}

/// 解析 HTML，按 CSS 选择器提取第一个匹配元素
#[napi]
pub fn jsoup_select_first(html: String, selector: String) -> Result<JsoupResult> {
    let document = Html::parse_document(&html);
    let sel = Selector::parse(&selector)
        .map_err(|e| Error::from_reason(format!("Invalid selector: {}", e)))?;

    let el = document
        .select(&sel)
        .next()
        .ok_or_else(|| Error::from_reason("No element found"))?;

    Ok(JsoupResult {
        text: el.text().collect::<Vec<_>>().join(""),
        html: el.html(),
        attr: String::new(),
        tag: el.value().name().to_string(),
    })
}

/// 提取元素的指定属性值
#[napi]
pub fn jsoup_get_attr(html: String, selector: String, attr_name: String) -> Result<String> {
    let document = Html::parse_document(&html);
    let sel = Selector::parse(&selector)
        .map_err(|e| Error::from_reason(format!("Invalid selector: {}", e)))?;

    let el = document
        .select(&sel)
        .next()
        .ok_or_else(|| Error::from_reason("No element found"))?;

    el.value()
        .attr(&attr_name)
        .map(|v| v.to_string())
        .ok_or_else(|| Error::from_reason(format!("Attribute '{}' not found", attr_name)))
}

/// 清理 HTML：提取纯文本，移除 script/style 标签
#[napi]
pub fn jsoup_clean(html: String) -> String {
    let document = Html::parse_document(&html);
    let mut result = String::new();
    for node in document.tree.nodes() {
        if let Some(text) = node.value().as_text() {
            let trimmed = text.text.trim();
            if !trimmed.is_empty() {
                result.push_str(trimmed);
                result.push(' ');
            }
        }
    }
    result.trim().to_string()
}
