#include "quickjs_bridge.h"
#include <stdlib.h>
#include <string.h>

struct QuickJSBridge {
    JSRuntime *runtime;
    JSContext *ctx;
};

// ---------- 原生加密回调（全局，所有 runtime 共享）----------
static crypto_callback g_crypto_cb = NULL;
static crypto_callback_binary g_crypto_cb_binary = NULL;

void quickjs_bridge_set_crypto_callback(crypto_callback cb) {
    g_crypto_cb = cb;
}

void quickjs_bridge_set_crypto_callback_binary(crypto_callback_binary cb) {
    g_crypto_cb_binary = cb;
}

// ---------- 字符串路径 ----------
// 通用加密调度：调用 Dart 回调，返回 JSValue
// 失败抛 JS 异常，成功返回字符串
static JSValue js_call_crypto(JSContext *ctx, int op, int argc, JSValueConst *argv,
                              int min_args, const char *fn_name) {
    if (!g_crypto_cb) {
        return JS_ThrowTypeError(ctx, "%s: native crypto not registered", fn_name);
    }
    if (argc < min_args) {
        return JS_ThrowTypeError(ctx, "%s requires %d arguments, got %d", fn_name, min_args, argc);
    }

    const char *a = argc > 0 ? JS_ToCString(ctx, argv[0]) : NULL;
    const char *b = argc > 1 ? JS_ToCString(ctx, argv[1]) : NULL;
    const char *c = argc > 2 ? JS_ToCString(ctx, argv[2]) : NULL;

    if (min_args > 0 && (!a)) {
        if (a) JS_FreeCString(ctx, a);
        if (b) JS_FreeCString(ctx, b);
        if (c) JS_FreeCString(ctx, c);
        return JS_ThrowTypeError(ctx, "%s: argument 1 must be a string", fn_name);
    }
    if (min_args > 1 && (!b)) {
        if (a) JS_FreeCString(ctx, a);
        if (b) JS_FreeCString(ctx, b);
        if (c) JS_FreeCString(ctx, c);
        return JS_ThrowTypeError(ctx, "%s: argument 2 must be a string", fn_name);
    }
    if (min_args > 2 && (!c)) {
        if (a) JS_FreeCString(ctx, a);
        if (b) JS_FreeCString(ctx, b);
        if (c) JS_FreeCString(ctx, c);
        return JS_ThrowTypeError(ctx, "%s: argument 3 must be a string", fn_name);
    }

    int is_error = 0;
    const char *result = g_crypto_cb(op, a ? a : "", b ? b : "", c ? c : "", &is_error);

    if (a) JS_FreeCString(ctx, a);
    if (b) JS_FreeCString(ctx, b);
    if (c) JS_FreeCString(ctx, c);

    if (is_error || !result) {
        return JS_ThrowTypeError(ctx, "%s: %s", fn_name, result ? result : "failed");
    }

    // JS_NewString 会复制字符串到 QuickJS 的内存
    JSValue ret = JS_NewString(ctx, result);
    return ret;
}

// ---------- ArrayBuffer 零拷贝路径 ----------
// 用于大数据：JS 传 Uint8Array/ArrayBuffer，C 侧直接取指针
// 返回 Uint8Array（JS_NewArrayBufferCopy 会复制，但只复制一次）
static JSValue js_call_crypto_binary(JSContext *ctx, int op, int argc, JSValueConst *argv,
                                     int min_args, const char *fn_name) {
    if (!g_crypto_cb_binary) {
        return JS_ThrowTypeError(ctx, "%s: native crypto binary not registered", fn_name);
    }
    if (argc < min_args) {
        return JS_ThrowTypeError(ctx, "%s requires %d arguments, got %d", fn_name, min_args, argc);
    }

    size_t len0 = 0, len1 = 0, len2 = 0;
    const uint8_t *data0 = NULL, *data1 = NULL, *data2 = NULL;

    // JS_GetArrayBuffer 直接返回内部指针，零拷贝
    if (argc > 0) {
        data0 = JS_GetArrayBuffer(ctx, &len0, argv[0]);
        if (!data0 && min_args > 0) {
            return JS_ThrowTypeError(ctx, "%s: argument 1 must be an ArrayBuffer/Uint8Array", fn_name);
        }
    }
    if (argc > 1) {
        data1 = JS_GetArrayBuffer(ctx, &len1, argv[1]);
        if (!data1 && min_args > 1) {
            return JS_ThrowTypeError(ctx, "%s: argument 2 must be an ArrayBuffer/Uint8Array", fn_name);
        }
    }
    if (argc > 2) {
        data2 = JS_GetArrayBuffer(ctx, &len2, argv[2]);
        if (!data2 && min_args > 2) {
            return JS_ThrowTypeError(ctx, "%s: argument 3 must be an ArrayBuffer/Uint8Array", fn_name);
        }
    }

    size_t out_len = 0;
    int is_error = 0;
    const uint8_t *result = g_crypto_cb_binary(op,
        data0, len0, data1, len1, data2, len2,
        &out_len, &is_error);

    if (is_error || !result) {
        return JS_ThrowTypeError(ctx, "%s: %s", fn_name, "binary failed");
    }

    // JS_NewArrayBufferCopy 会复制数据到 QuickJS 管理的内存
    // 这是唯一一次拷贝（从 Dart 环形缓冲区到 JS）
    JSValue ret = JS_NewArrayBufferCopy(ctx, result, out_len);
    return ret;
}

// ---------- JS 函数注册 ----------
// 字符串路径（小数据，< 1KB）
static JSValue js_crypto_aes_decrypt(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv) {
    return js_call_crypto(ctx, 0, argc, argv, 3, "aesDecrypt");
}
static JSValue js_crypto_aes_encrypt(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv) {
    return js_call_crypto(ctx, 1, argc, argv, 3, "aesEncrypt");
}
static JSValue js_crypto_md5(JSContext *ctx, JSValueConst this_val,
                             int argc, JSValueConst *argv) {
    return js_call_crypto(ctx, 2, argc, argv, 1, "md5");
}
static JSValue js_crypto_sha256(JSContext *ctx, JSValueConst this_val,
                                int argc, JSValueConst *argv) {
    return js_call_crypto(ctx, 3, argc, argv, 1, "sha256");
}
static JSValue js_crypto_hmac_sha256(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv) {
    return js_call_crypto(ctx, 4, argc, argv, 2, "hmacSHA256");
}
static JSValue js_crypto_sha1(JSContext *ctx, JSValueConst this_val,
                              int argc, JSValueConst *argv) {
    return js_call_crypto(ctx, 5, argc, argv, 1, "sha1");
}

// ArrayBuffer 路径（大数据，>= 1KB）
static JSValue js_crypto_aes_decrypt_bin(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv) {
    return js_call_crypto_binary(ctx, 0, argc, argv, 3, "aesDecryptBin");
}
static JSValue js_crypto_aes_encrypt_bin(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv) {
    return js_call_crypto_binary(ctx, 1, argc, argv, 3, "aesEncryptBin");
}
static JSValue js_crypto_md5_bin(JSContext *ctx, JSValueConst this_val,
                             int argc, JSValueConst *argv) {
    return js_call_crypto_binary(ctx, 2, argc, argv, 1, "md5Bin");
}
static JSValue js_crypto_sha256_bin(JSContext *ctx, JSValueConst this_val,
                                int argc, JSValueConst *argv) {
    return js_call_crypto_binary(ctx, 3, argc, argv, 1, "sha256Bin");
}
static JSValue js_crypto_hmac_sha256_bin(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv) {
    return js_call_crypto_binary(ctx, 4, argc, argv, 2, "hmacSHA256Bin");
}
static JSValue js_crypto_sha1_bin(JSContext *ctx, JSValueConst this_val,
                              int argc, JSValueConst *argv) {
    return js_call_crypto_binary(ctx, 5, argc, argv, 1, "sha1Bin");
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

    // 注册原生加密全局对象 __nativeCrypto
    // 字符串路径：aesDecrypt/aesEncrypt/md5/sha256/hmacSHA256/sha1
    // ArrayBuffer 路径：aesDecryptBin/aesEncryptBin/md5Bin/sha256Bin/hmacSHA256Bin/sha1Bin
    JSValue global_obj = JS_GetGlobalObject(bridge->ctx);
    JSValue crypto_obj = JS_NewObject(bridge->ctx);

    // 字符串路径
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "aesDecrypt",
        JS_NewCFunction(bridge->ctx, js_crypto_aes_decrypt, "aesDecrypt", 3));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "aesEncrypt",
        JS_NewCFunction(bridge->ctx, js_crypto_aes_encrypt, "aesEncrypt", 3));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "md5",
        JS_NewCFunction(bridge->ctx, js_crypto_md5, "md5", 1));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "sha256",
        JS_NewCFunction(bridge->ctx, js_crypto_sha256, "sha256", 1));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "hmacSHA256",
        JS_NewCFunction(bridge->ctx, js_crypto_hmac_sha256, "hmacSHA256", 2));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "sha1",
        JS_NewCFunction(bridge->ctx, js_crypto_sha1, "sha1", 1));

    // ArrayBuffer 路径（零拷贝，大数据）
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "aesDecryptBin",
        JS_NewCFunction(bridge->ctx, js_crypto_aes_decrypt_bin, "aesDecryptBin", 3));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "aesEncryptBin",
        JS_NewCFunction(bridge->ctx, js_crypto_aes_encrypt_bin, "aesEncryptBin", 3));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "md5Bin",
        JS_NewCFunction(bridge->ctx, js_crypto_md5_bin, "md5Bin", 1));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "sha256Bin",
        JS_NewCFunction(bridge->ctx, js_crypto_sha256_bin, "sha256Bin", 1));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "hmacSHA256Bin",
        JS_NewCFunction(bridge->ctx, js_crypto_hmac_sha256_bin, "hmacSHA256Bin", 2));
    JS_SetPropertyStr(bridge->ctx, crypto_obj, "sha1Bin",
        JS_NewCFunction(bridge->ctx, js_crypto_sha1_bin, "sha1Bin", 1));

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
