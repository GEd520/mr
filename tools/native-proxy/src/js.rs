// ===== js.rs: JS 引擎模块 =====
//
// 基于 boa_engine（纯 Rust 实现的 JS 引擎，支持 ES6+）
// 作为 QuickJS/Dart 侧的降级引擎：
//   QuickJS 解析失败 → 自动发到 Rust boa 引擎重试
//
// 添加新的 JS 引擎功能：
//   1. 写一个 pub fn，标注 #[napi]
//   2. 在 index.js 的 js 分组中添加 JS 降级实现
//   3. 在 cors-proxy.js 的 /api/js/* 路由中添加

use napi::bindgen_prelude::*;
use napi_derive::napi;
use std::collections::HashMap;
use boa_engine::{Context, Source, JsValue, JsResult};
use boa_engine::object::ObjectInitializer;
use boa_engine::property::Attribute;

/// JS 执行结果
#[napi(object)]
pub struct JsExecResult {
    /// 执行是否成功
    pub success: bool,
    /// 返回值（成功时为结果字符串，失败时为错误信息）
    pub result: String,
    /// 输出类型: "string" | "number" | "boolean" | "null" | "undefined" | "object" | "error"
    pub value_type: String,
}

/// 执行 JS 代码（同步，无上下文注入）
///
/// @example
/// ```js
/// const result = native.jsEvaluate('1 + 2 * 3');
/// // { success: true, result: '7', value_type: 'number' }
/// ```
#[napi]
pub fn js_evaluate(code: String) -> JsExecResult {
    let mut context = Context::default();

    match context.eval(Source::from_bytes(&code)) {
        Ok(value) => {
            let (result_str, value_type) = js_value_to_string(&value, &mut context);
            JsExecResult {
                success: true,
                result: result_str,
                value_type,
            }
        }
        Err(err) => JsExecResult {
            success: false,
            result: format!("{}", err),
            value_type: "error".to_string(),
        },
    }
}

/// 执行 JS 代码（带变量注入）
///
/// @param code     JS 代码
/// @param variables 注入的变量（key=变量名, value=JSON字符串）
///
/// @example
/// ```js
/// const result = native.jsEvaluateWithVars(
///   'result.toUpperCase()',
///   { result: '"hello world"' }
/// );
/// // { success: true, result: 'HELLO WORLD', value_type: 'string' }
/// ```
#[napi]
pub fn js_evaluate_with_vars(code: String, variables: HashMap<String, String>) -> JsExecResult {
    let mut context = Context::default();

    // 注入变量到全局作用域
    for (key, value_json) in &variables {
        // 尝试解析为 JS 值
        let js_value = match context.eval(Source::from_bytes(value_json)) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let key_atom = boa_engine::JsString::from(key.as_str());
        if let Err(_) = context.register_global_property(
            key_atom,
            js_value,
            Attribute::all(),
        ) {
            continue;
        }
    }

    match context.eval(Source::from_bytes(&code)) {
        Ok(value) => {
            let (result_str, value_type) = js_value_to_string(&value, &mut context);
            JsExecResult {
                success: true,
                result: result_str,
                value_type,
            }
        }
        Err(err) => JsExecResult {
            success: false,
            result: format!("{}", err),
            value_type: "error".to_string(),
        },
    }
}

/// 执行 JS 代码（带书源上下文：result/baseUrl/content/book/chapter）
///
/// 对应 JsEngine 的 processJsRule / executeSync 的降级路径
///
/// @param code     JS 代码
/// @param result   当前结果（通常是 HTML 或 JSON）
/// @param base_url 基础 URL
/// @param content  内容（同 result）
/// @param book_json  书籍信息 JSON（可选）
/// @param chapter_json 章节信息 JSON（可选）
#[napi]
pub fn js_evaluate_with_context(
    code: String,
    result: String,
    base_url: String,
    content: String,
    book_json: Option<String>,
    chapter_json: Option<String>,
) -> JsExecResult {
    let mut context = Context::default();

    // 注入 result 变量
    let result_value = context.eval(Source::from_bytes(&format!(
        "(function() {{ try {{ return JSON.parse({}); }} catch(e) {{ return {}; }} }})()",
        json_escape(&result),
        json_escape(&result)
    )));

    if let Ok(val) = result_value {
        let _ = context.register_global_property(
            boa_engine::JsString::from("result"),
            val,
            Attribute::all(),
        );
    }

    // 注入 baseUrl
    let _ = context.register_global_property(
        boa_engine::JsString::from("baseUrl"),
        JsValue::from(base_url.as_str()),
        Attribute::all(),
    );

    // 注入 content（同 result）
    if let Ok(val) = result_value {
        let _ = context.register_global_property(
            boa_engine::JsString::from("content"),
            val,
            Attribute::all(),
        );
    }

    // 注入 book
    if let Some(bj) = book_json {
        let book_val = context.eval(Source::from_bytes(&bj));
        if let Ok(val) = book_val {
            let _ = context.register_global_property(
                boa_engine::JsString::from("book"),
                val,
                Attribute::all(),
            );
        }
    }

    // 注入 chapter
    if let Some(cj) = chapter_json {
        let chapter_val = context.eval(Source::from_bytes(&cj));
        if let Ok(val) = chapter_val {
            let _ = context.register_global_property(
                boa_engine::JsString::from("chapter"),
                val,
                Attribute::all(),
            );
        }
    }

    match context.eval(Source::from_bytes(&code)) {
        Ok(value) => {
            let (result_str, value_type) = js_value_to_string(&value, &mut context);
            JsExecResult {
                success: true,
                result: result_str,
                value_type,
            }
        }
        Err(err) => JsExecResult {
            success: false,
            result: format!("{}", err),
            value_type: "error".to_string(),
        },
    }
}

// ===== 辅助函数 =====

/// 将 JS 值转为字符串和类型标识
fn js_value_to_string(value: &JsValue, context: &mut Context) -> (String, String) {
    match value {
        JsValue::Null => ("null".to_string(), "null".to_string()),
        JsValue::Undefined => ("undefined".to_string(), "undefined".to_string()),
        JsValue::Bool(b) => (b.to_string(), "boolean".to_string()),
        JsValue::Rational(n) => {
            let s = if *n == (*n as i64) as f64 {
                (*n as i64).to_string()
            } else {
                n.to_string()
            };
            (s, "number".to_string())
        }
        JsValue::Integer(n) => (n.to_string(), "number".to_string()),
        JsValue::BigInt(_) => ("[BigInt]".to_string(), "number".to_string()),
        JsValue::String(s) => (s.to_std_string_escaped(), "string".to_string()),
        JsValue::Object(_) => {
            // 尝试 JSON.stringify
            match context.eval(Source::from_bytes("JSON.stringify")) {
                Ok(stringify_fn) => {
                    // 简单方式：直接用 to_string
                    (format!("{}", value.display()), "object".to_string())
                }
                Err(_) => (format!("{}", value.display()), "object".to_string()),
            }
        }
        JsValue::Symbol(_) => ("[Symbol]".to_string(), "object".to_string()),
    }
}

/// 转义字符串为 JS 字符串字面量
fn json_escape(s: &str) -> String {
    let escaped = s
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t");
    format!("\"{}\"", escaped)
}
