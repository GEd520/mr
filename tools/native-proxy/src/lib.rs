// ===== native-proxy: Rust 原生桥接模块 =====
//
// 模块化架构，方便后来人添加新功能：
//
//   src/
//   ├── lib.rs          ← 模块入口（你在这里）
//   ├── jsoup.rs        ← HTML 解析（CSS 选择器）
//   ├── crypto.rs       ← 加密/哈希（MD5/SHA/AES/Base64/HMAC）
//   ├── url_parser.rs   ← URL 解析/拼接
//   ├── http.rs         ← HTTP 请求（GET/POST）
//   ├── js.rs           ← JS 引擎（boa_engine，QuickJS 降级）
//   └── [你的新模块].rs ← 新增模块只需三步：
//         1. 创建 src/[模块名].rs，用 #[napi] 标注导出函数
//         2. 在本文件添加 mod [模块名];
//         3. 在 index.js 添加对应的 JS 降级实现
//
// 所有导出到 Node.js 的函数必须标注 #[napi]
// 返回值用 Result<T> 包装错误，napi-rs 自动转为 JS Error

pub mod jsoup;
pub mod crypto;
pub mod url_parser;
pub mod http;
pub mod js;
