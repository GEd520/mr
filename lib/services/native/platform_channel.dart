import 'package:flutter/services.dart';

/// 原生平台通道（MethodChannel）
///
/// 仅保留 Dart 层无法实现、必须依赖平台原生 API 的方法：
/// - 屏幕亮度（平台 UI API）
/// - WebView JS 执行（平台 WebView 组件）
/// - Cookie（平台 Cookie 存储）
/// - 设备信息（平台系统 API）
/// - 数据存储（SharedPreferences / UserDefaults）
/// - Native lib 完整性检查
///
/// HTTP 请求已迁移至 [PlatformBridge]（Dio），不再经过 MethodChannel。
/// 加密/HTML 解析/编码转换由 C 层 FFI 直接处理。
class NativeChannel {
  static NativeChannel? _instance;
  static NativeChannel get instance => _instance ??= NativeChannel._();

  NativeChannel._();

  static const MethodChannel _channel = MethodChannel(
    'com.mr.app/native',
  );

  // ===== 屏幕亮度（平台 UI API，C FFI 无法替代）=====

  Future<double> getScreenBrightness() async {
    try {
      return await _channel.invokeMethod<double>('getScreenBrightness') ?? -1;
    } on PlatformException catch (_) {
      return -1;
    } on MissingPluginException catch (_) {
      return -1;
    }
  }

  Future<bool> setScreenBrightness(double value) async {
    try {
      return await _channel.invokeMethod<bool>('setScreenBrightness', {
            'value': value.clamp(-1.0, 1.0),
          }) ??
          false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  // ===== Cookie（平台 Cookie 存储）=====

  Future<String?> getCookie(String url, {String? key}) async {
    try {
      final result = await _channel.invokeMethod<String>('getCookie', {
        'url': url,
        'key': key,
      });
      return result;
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  // ===== 设备信息 =====

  Future<Map<String, dynamic>?> getDeviceInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getDeviceInfo');
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  // ===== WebView JS =====

  Future<String?> executeWebViewJs({
    required String url,
    required String jsCode,
    String? sourceRegex,
    String? html,
    int delayTime = 200,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('executeWebViewJs', {
        'url': url,
        'jsCode': jsCode,
        'sourceRegex': sourceRegex,
        'html': html,
        'delayTime': delayTime,
      });
      return result;
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  // ===== 数据持久化 =====

  Future<bool> putData(String key, String value) async {
    try {
      await _channel.invokeMethod<void>('putData', {
        'key': key,
        'value': value,
      });
      return true;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  Future<String?> getData(String key, {String defaultValue = ''}) async {
    try {
      final result = await _channel.invokeMethod<String>('getData', {
        'key': key,
        'defaultValue': defaultValue,
      });
      return result;
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  Future<bool> deleteData(String key) async {
    try {
      await _channel.invokeMethod<void>('deleteData', {'key': key});
      return true;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  // ===== Native lib 完整性检查（安全，不执行 FFI，避免 SIGSEGV）=====

  /// 检查 native .so 文件完整性
  /// 通过 MethodChannel 走到 Java 层做文件系统检查 + loadLibrary 验证，
  /// 不直接执行 FFI 调用，避免 SIGSEGV。
  /// 覆盖安装后首次启动时 .so 可能未完全就绪，此方法可安全检测。
  Future<bool> checkNativeLib(String libName) async {
    try {
      final result = await _channel.invokeMethod<bool>('checkNativeLib', {
        'libName': libName,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}
