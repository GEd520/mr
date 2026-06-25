import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// QuickJS 评估结果
/// 兼容 flutter_js 的 JsEvalResult 接口
class JsEvalResult {
  final String stringResult;
  final bool isError;

  JsEvalResult(this.stringResult, this.isError);
}

// ---------- C 函数签名 ----------
typedef _BridgeCreateC = Pointer<Void> Function();
typedef _BridgeEvalC = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Int32>);
typedef _BridgeFreeStringC = Void Function(Pointer<Utf8>);
typedef _BridgeDisposeC = Void Function(Pointer<Void>);

// ---------- Dart 函数签名 ----------
typedef _BridgeCreateDart = Pointer<Void> Function();
typedef _BridgeEvalDart = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Int32>);
typedef _BridgeFreeStringDart = void Function(Pointer<Utf8>);
typedef _BridgeDisposeDart = void Function(Pointer<Void>);

/// 加载 QuickJS 动态库
///
/// 全端加载策略：
/// - iOS/macOS: podspec 配置 static_framework，符号链接到主程序 → DynamicLibrary.process()
/// - Android: NDK 编译为 libquickjs_c_bridge.so → DynamicLibrary.open()
/// - Windows: CMake 编译为 quickjs_c_bridge.dll → DynamicLibrary.open()
/// - Linux: CMake 编译为 libquickjs_c_bridge.so → DynamicLibrary.open()
DynamicLibrary _loadQuickJsLib() {
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open('libquickjs_c_bridge.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('quickjs_c_bridge.dll');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libquickjs_c_bridge.so');
  }
  throw UnsupportedError('QuickJS 不支持当前平台: ${Platform.operatingSystem}');
}

final DynamicLibrary _qjsLib = _loadQuickJsLib();

// ---------- FFI 绑定 ----------
// C 桥接层定义在 ios/QuickJS/quickjs_bridge.h
// 创建运行时：QuickJSBridge *quickjs_bridge_create(void)
final _BridgeCreateDart _bridgeCreate = _qjsLib
    .lookup<NativeFunction<_BridgeCreateC>>('quickjs_bridge_create')
    .asFunction<_BridgeCreateDart>();

// 执行脚本：const char *quickjs_bridge_eval(bridge, script, &is_error)
// 返回的字符串需调用 quickjs_bridge_free_string 释放
final _BridgeEvalDart _bridgeEval = _qjsLib
    .lookup<NativeFunction<_BridgeEvalC>>('quickjs_bridge_eval')
    .asFunction<_BridgeEvalDart>();

// 释放 eval 返回的字符串
final _BridgeFreeStringDart _bridgeFreeString = _qjsLib
    .lookup<NativeFunction<_BridgeFreeStringC>>('quickjs_bridge_free_string')
    .asFunction<_BridgeFreeStringDart>();

// 释放运行时：void quickjs_bridge_dispose(bridge)
final _BridgeDisposeDart _bridgeDispose = _qjsLib
    .lookup<NativeFunction<_BridgeDisposeC>>('quickjs_bridge_dispose')
    .asFunction<_BridgeDisposeDart>();

/// QuickJS 运行时
///
/// 从 C 源码编译的 QuickJS，通过 dart:ffi 直接调用 C API。
/// 替代 flutter_js 的 JavascriptRuntime。
///
/// 关键：evaluate() 保持同步调用（FFI 调用是同步的），
/// 这样 js_engine.dart 中 13 处同步方法无需改为 async。
class JavascriptRuntime {
  Pointer<Void>? _bridge;
  bool _disposed = false;

  JavascriptRuntime() {
    _bridge = _bridgeCreate();
    if (_bridge == null || _bridge!.address == 0) {
      throw StateError('QuickJS 运行时创建失败');
    }
  }

  /// 执行 JS 脚本（同步）
  ///
  /// 通过 FFI 直接调用 C 函数 quickjs_bridge_eval，同步返回结果。
  /// 这与 flutter_js 的 QuickJsRuntime2.evaluate() 行为一致。
  JsEvalResult evaluate(String script) {
    if (_disposed || _bridge == null) {
      return JsEvalResult('', true);
    }
    final scriptPtr = script.toNativeUtf8();
    final isErrorPtr = malloc<Int32>();
    try {
      isErrorPtr.value = 0;
      final resultPtr = _bridgeEval(_bridge!, scriptPtr, isErrorPtr);
      final isError = isErrorPtr.value != 0;
      if (resultPtr == nullptr) {
        return JsEvalResult('', isError);
      }
      final result = resultPtr.toDartString();
      _bridgeFreeString(resultPtr);
      return JsEvalResult(result, isError);
    } catch (e) {
      return JsEvalResult(e.toString(), true);
    } finally {
      malloc.free(scriptPtr);
      malloc.free(isErrorPtr);
    }
  }

  /// 异步执行 JS 脚本
  ///
  /// QuickJS 本身是同步执行的，这里包装为 Future 保持接口兼容。
  /// 对应 js_engine.dart 中的 evaluateAsync 调用。
  Future<JsEvalResult> evaluateAsync(String script) async {
    return evaluate(script);
  }

  /// 释放资源
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_bridge != null) {
      _bridgeDispose(_bridge!);
      _bridge = null;
    }
  }
}

/// 创建 QuickJS 运行时
/// 兼容 flutter_js 的 getJavascriptRuntime 接口
JavascriptRuntime getJavascriptRuntime() {
  return JavascriptRuntime();
}
