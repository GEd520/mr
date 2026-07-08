/**
 * bridge_init.c — 原生函数注册入口
 *
 * 本文件是 native_core 模块的统一注册入口。
 * 所有 __native* 全局对象的注册在 quickjs_bridge.c 的
 * quickjs_bridge_create_with_config() 中完成（包括 __nativeCrypto、
 * __nativeLz、__nativeBase64、__nativeConv、__nativeHtml）。
 *
 * 本文件提供 bridge_init() 桩函数，保留作为未来扩展入口：
 * 当需要在不修改 quickjs_bridge.c 的情况下注册新的原生函数时，
 * 可在此文件中实现并通过 bridge_init() 调用。
 *
 * 架构：
 *   quickjs_bridge_create_with_config()
 *     → 注册 __nativeCrypto / __nativeLz / __nativeBase64 / __nativeConv / __nativeHtml
 *     → bridge_init(ctx)  ← 未来扩展点
 *
 * 当前已注册的 C 原生函数（通过 QuickJS JS_NewCFunction）：
 *   __nativeCrypto:
 *     - aesDecrypt / aesEncrypt (字符串路径，走 Dart crypto_callback)
 *     - md5 / sha256 / hmacSHA256 / sha1 (字符串路径)
 *     - *Bin 系列 (ArrayBuffer 零拷贝路径)
 *     - *Native 系列 (纯 C 计算，零 Dart 回调)
 *     - *FromBase64 / *Batch 系列 (全 C 直通链路)
 *     - aesDecryptThenLzDecompress / *Batch / *Bin (AES+LZ 原子组合)
 *   __nativeLz:
 *     - decompressFromBase64 / *Batch / *Bin
 *   __nativeBase64:
 *     - decode / encode / decodeToBytes / uint8ToStr / b64FromBytes
 *   __nativeConv:
 *     - charsetUrlEncode / charsetDetect / charsetDecode
 *   __nativeHtml:
 *     - select(html, selector, attr) → 第一个匹配的字符串
 *     - selectAll(html, selector, attr) → JSON 数组字符串
 *     - getAttr(html, selector, attr) → 第一个匹配元素的属性值
 */

/**
 * bridge_init — 原生函数注册扩展入口
 *
 * 当前为空实现，所有 __native* 注册已在 quickjs_bridge_create_with_config() 中完成。
 * 未来新增原生模块时，可在此函数中添加注册逻辑，并在 quickjs_bridge.c 中调用。
 *
 * @param ctx  QuickJS 上下文
 */
void bridge_init(void *ctx) {
    (void)ctx;  // 当前为桩函数，避免未使用参数警告
}
