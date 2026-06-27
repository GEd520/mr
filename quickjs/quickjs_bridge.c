#include "quickjs_bridge.h"
#include <stdlib.h>
#include <string.h>

struct QuickJSBridge {
    JSRuntime *runtime;
    JSContext *ctx;
};

// ---------- 原生加密回调（全局，所有 runtime 共享）----------
static aes_decrypt_callback g_aes_decrypt = NULL;

void quickjs_bridge_set_aes_decrypt_callback(aes_decrypt_callback cb) {
    g_aes_decrypt = cb;
}

// JS 函数: __nativeCrypto.aesDecrypt(data, key, iv)
// data: Base64 编码的密文
// key: UTF-8 字符串密钥
// iv: UTF-8 字符串 IV
// 返回: 解密后的 UTF-8 明文，失败抛 JS 异常
static JSValue js_native_aes_decrypt(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv) {
    if (!g_aes_decrypt) {
        return JS_ThrowTypeError(ctx, "native AES decrypt not registered");
    }
    if (argc < 3) {
        return JS_ThrowTypeError(ctx, "aesDecrypt requires 3 arguments: (data, key, iv)");
    }

    const char *data = JS_ToCString(ctx, argv[0]);
    const char *key = JS_ToCString(ctx, argv[1]);
    const char *iv = JS_ToCString(ctx, argv[2]);

    if (!data || !key || !iv) {
        if (data) JS_FreeCString(ctx, data);
        if (key) JS_FreeCString(ctx, key);
        if (iv) JS_FreeCString(ctx, iv);
        return JS_ThrowTypeError(ctx, "arguments must be strings");
    }

    int is_error = 0;
    const char *result = g_aes_decrypt(data, key, iv, &is_error);

    JS_FreeCString(ctx, data);
    JS_FreeCString(ctx, key);
    JS_FreeCString(ctx, iv);

    if (is_error || !result) {
        // 注意：result 是 Dart 分配的内存，即使 is_error 时也可能需要 Dart 自己释放
        // 这里不释放，由 Dart 的环形缓冲区管理
        return JS_ThrowTypeError(ctx, "%s", result ? result : "AES decrypt failed");
    }

    // JS_NewString 会复制字符串到 QuickJS 的内存，所以 result 可以立即被 Dart 释放
    JSValue ret = JS_NewString(ctx, result);
    return ret;
}

QuickJSBridge *quickjs_bridge_create(void) {
    QuickJSBridge *bridge = (QuickJSBridge *)malloc(sizeof(QuickJSBridge));
    if (!bridge) return NULL;

    bridge->runtime = JS_NewRuntime();
    if (!bridge->runtime) {
        free(bridge);
        return NULL;
    }

    // 设置内存限制（256MB）和栈大小（256KB）
    JS_SetMemoryLimit(bridge->runtime, 256 * 1024 * 1024);
    JS_SetMaxStackSize(bridge->runtime, 256 * 1024);

    bridge->ctx = JS_NewContext(bridge->runtime);
    if (!bridge->ctx) {
        JS_FreeRuntime(bridge->runtime);
        free(bridge);
        return NULL;
    }

    // 注入 quickjs-libc 标准库（setTimeout 等暂不需要）
    // js_std_add_helpers(bridge->ctx, 0, NULL);

    // 注册原生加密全局对象 __nativeCrypto
    // JS 代码可通过 __nativeCrypto.aesDecrypt(data, key, iv) 调用原生 AES 解密
    // 失败回退到纯 JS 的 CryptoJS 实现
    JSValue global_obj = JS_GetGlobalObject(bridge->ctx);
    JSValue crypto_obj = JS_NewObject(bridge->ctx);
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "aesDecrypt",
        JS_NewCFunction(bridge->ctx, js_native_aes_decrypt, "aesDecrypt", 3));
    JS_SetPropertyStr(bridge->ctx, global_obj, "__nativeCrypto", crypto_obj);
    JS_FreeValue(bridge->ctx, global_obj);

    return bridge;
}

const char *quickjs_bridge_eval(QuickJSBridge *bridge, const char *script, int *is_error) {
    if (!bridge || !bridge->ctx || !script) {
        if (is_error) *is_error = 1;
        return NULL;
    }

    JSValue val = JS_Eval(bridge->ctx, script, strlen(script), "<eval>", JS_EVAL_TYPE_GLOBAL);

    if (JS_IsException(val)) {
        JSValue exception = JS_GetException(bridge->ctx);
        const char *str = JS_ToCString(bridge->ctx, exception);
        JS_FreeValue(bridge->ctx, exception);
        JS_FreeValue(bridge->ctx, val);
        if (is_error) *is_error = 1;
        if (str) {
            char *result = strdup(str);
            JS_FreeCString(bridge->ctx, str);
            return result;
        }
        return strdup("Unknown error");
    }

    const char *str = JS_ToCString(bridge->ctx, val);
    JS_FreeValue(bridge->ctx, val);
    if (is_error) *is_error = 0;

    if (str) {
        char *result = strdup(str);
        JS_FreeCString(bridge->ctx, str);
        return result;
    }

    return strdup("");
}

void quickjs_bridge_free_string(const char *str) {
    if (str) {
        free((void *)str);
    }
}

void quickjs_bridge_dispose(QuickJSBridge *bridge) {
    if (!bridge) return;
    if (bridge->ctx) {
        JS_FreeContext(bridge->ctx);
    }
    if (bridge->runtime) {
        JS_FreeRuntime(bridge->runtime);
    }
    free(bridge);
}
