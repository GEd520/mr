#ifndef QUICKJS_BRIDGE_H
#define QUICKJS_BRIDGE_H

#include "quickjs.h"

#ifdef __cplusplus
extern "C" {
#endif

// 简化的 QuickJS 桥接 API
// Swift 通过这些函数调用 QuickJS，避免直接处理 JSValue
typedef struct QuickJSBridge QuickJSBridge;

// 创建 QuickJS 运行时
QuickJSBridge *quickjs_bridge_create(void);

// 执行 JS 脚本，返回字符串结果
// 返回的字符串需要调用者用 free() 释放
// is_error: 0=成功, 1=异常
const char *quickjs_bridge_eval(QuickJSBridge *bridge, const char *script, int *is_error);

// 释放 QuickJS 运行时
void quickjs_bridge_dispose(QuickJSBridge *bridge);

// 释放 eval 返回的字符串
void quickjs_bridge_free_string(const char *str);

// ---------- 原生加密桥接 ----------
// Dart 层通过 FFI 注册同步回调，JS 调用 __nativeCrypto.aesDecrypt(data, key, iv) 时触发
// 回调返回的 const char* 由 Dart 端管理（环形缓冲区），C 层不释放

// AES 解密回调类型
// data: Base64 编码的密文
// key: UTF-8 字符串密钥
// iv: UTF-8 字符串 IV
// is_error: 0=成功, 1=失败
// 返回: 解密后的 UTF-8 明文（Dart 管理内存，C 层不释放），失败时返回 nullptr
typedef const char *(*aes_decrypt_callback)(const char *data, const char *key, const char *iv, int *is_error);

// 注册 AES 解密回调（全局，所有 runtime 共享）
void quickjs_bridge_set_aes_decrypt_callback(aes_decrypt_callback cb);

#ifdef __cplusplus
}
#endif

#endif /* QUICKJS_BRIDGE_H */
