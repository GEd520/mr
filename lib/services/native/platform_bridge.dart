import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'platform_channel.dart';
import 'dio_ssl_helper_stub.dart'
    if (dart.library.io) 'dio_ssl_helper_io.dart' as ssl;

/// 统一平台桥接层
///
/// 架构原则：
/// • 网络请求统一走 Dio（成熟稳定，支持 HTTP/HTTPS/缓存/拦截器）
/// • 原生平台 API（亮度、WebView、数据存储等）委托 NativeChannel → MethodChannel
/// • 加密/HTML 解析/编码转换由 C 层 FFI 直接处理，不经过本层
///
/// 调用链：
///   Dart → PlatformBridge.httpGet → Dio → 网络
///   Dart → PlatformBridge.setBrightness → NativeChannel → MethodChannel → Kotlin/Swift
///   JS  → __nativeCrypto.aesDecrypt → C 函数（无中间层）
///
/// 替代原 NativeChannel 中的 HTTP 方法（httpGet/httpPost/httpHead/httpDownload），
/// 消除 OkHttp/URLSession 的 MethodChannel 序列化开销。
class PlatformBridge {
  static PlatformBridge? _instance;
  static PlatformBridge get instance => _instance ??= PlatformBridge._();

  PlatformBridge._();

  /// Dio 实例（懒加载，全应用共享）
  Dio? _dio;
  Dio get dio => _dio ??= _createDio();

  /// 创建配置好的 Dio 实例
  ///
  /// 与 web_book.dart 的 HttpClient 保持一致的配置策略：
  /// - 接受所有状态码（书源网站可能返回 301/302/403/503 等）
  /// - 跟随重定向
  /// - Web 端 CORS 代理由 ProxyService 处理，Dio 无需特殊配置
  Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 5,
      responseType: ResponseType.plain,
      // 接受所有状态码，不抛异常（与原 NativeChannel 行为一致）
      validateStatus: (status) => status != null && status < 600,
    ));
    // 书源网站证书常有问题，允许不安全证书（Web 平台由浏览器处理）
    ssl.configureDioSslBypass(dio);
    return dio;
  }

  // ===== HTTP 请求（Dio）=====

  /// HTTP GET 请求
  ///
  /// 返回响应体字符串，失败返回 null
  Future<String?> httpGet(
    String url, {
    Map<String, String>? headers,
    int timeoutMs = 10000,
  }) async {
    try {
      final response = await dio.get<String>(
        url,
        options: Options(
          headers: headers,
          receiveTimeout: Duration(milliseconds: timeoutMs),
          sendTimeout: Duration(milliseconds: timeoutMs),
          responseType: ResponseType.plain,
        ),
      );
      return response.data;
    } on DioException catch (e) {
      debugPrint('PlatformBridge.httpGet 失败: $url → ${e.message}');
      return null;
    } catch (e) {
      debugPrint('PlatformBridge.httpGet 异常: $url → $e');
      return null;
    }
  }

  /// HTTP POST 请求
  ///
  /// 返回响应体字符串，失败返回 null
  Future<String?> httpPost(
    String url, {
    String? body,
    Map<String, String>? headers,
    int timeoutMs = 10000,
  }) async {
    try {
      final contentType = headers?['Content-Type'] ?? 'application/x-www-form-urlencoded';
      final response = await dio.post<String>(
        url,
        data: body,
        options: Options(
          headers: headers,
          contentType: contentType,
          receiveTimeout: Duration(milliseconds: timeoutMs),
          sendTimeout: Duration(milliseconds: timeoutMs),
          responseType: ResponseType.plain,
        ),
      );
      return response.data;
    } on DioException catch (e) {
      debugPrint('PlatformBridge.httpPost 失败: $url → ${e.message}');
      return null;
    } catch (e) {
      debugPrint('PlatformBridge.httpPost 异常: $url → $e');
      return null;
    }
  }

  /// HTTP HEAD 请求
  ///
  /// 返回响应头 Map，失败返回 null
  Future<Map<String, String>?> httpHead(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await dio.head(
        url,
        options: Options(
          headers: headers,
          followRedirects: true,
        ),
      );
      return response.headers.map.map(
        (key, value) => MapEntry(key, value.join(', ')),
      );
    } on DioException catch (e) {
      debugPrint('PlatformBridge.httpHead 失败: $url → ${e.message}');
      return null;
    } catch (e) {
      debugPrint('PlatformBridge.httpHead 异常: $url → $e');
      return null;
    }
  }

  /// 文件下载
  ///
  /// 下载到 [savePath]，成功返回文件路径，失败返回 null
  Future<String?> httpDownload(
    String url,
    String savePath, {
    Map<String, String>? headers,
  }) async {
    try {
      await dio.download(
        url,
        savePath,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      return savePath;
    } on DioException catch (e) {
      debugPrint('PlatformBridge.httpDownload 失败: $url → ${e.message}');
      return null;
    } catch (e) {
      debugPrint('PlatformBridge.httpDownload 异常: $url → $e');
      return null;
    }
  }

  /// 带缓存的 HTTP GET
  ///
  /// 使用 Dio 内置缓存机制，适合不常变化的资源
  Future<String?> httpGetWithCache(
    String url, {
    Map<String, String>? headers,
    int cacheMaxAge = 3600,
  }) async {
    try {
      final response = await dio.get<String>(
        url,
        options: Options(
          headers: headers,
          extra: {'cache': true},
          responseType: ResponseType.plain,
        ),
      );
      return response.data;
    } on DioException catch (e) {
      debugPrint('PlatformBridge.httpGetWithCache 失败: $url → ${e.message}');
      return null;
    } catch (e) {
      debugPrint('PlatformBridge.httpGetWithCache 异常: $url → $e');
      return null;
    }
  }

  // ===== 原生平台 API（委托 NativeChannel → MethodChannel）=====
  // 以下方法仅在 Dart 层无法实现时才使用 MethodChannel：
  // - 屏幕亮度：平台 UI API
  // - WebView JS 执行：平台 WebView 组件
  // - 数据存储：SharedPreferences/UserDefaults
  // - 设备信息：平台系统 API
  // - Cookie：平台 Cookie 存储

  /// 获取屏幕亮度
  Future<double> getScreenBrightness() =>
      NativeChannel.instance.getScreenBrightness();

  /// 设置屏幕亮度
  Future<bool> setScreenBrightness(double value) =>
      NativeChannel.instance.setScreenBrightness(value);

  /// 执行 WebView JS
  Future<String?> executeWebViewJs({
    required String url,
    required String jsCode,
    String? sourceRegex,
    String? html,
    int delayTime = 200,
  }) =>
      NativeChannel.instance.executeWebViewJs(
        url: url,
        jsCode: jsCode,
        sourceRegex: sourceRegex,
        html: html,
        delayTime: delayTime,
      );

  /// 获取设备信息
  Future<Map<String, dynamic>?> getDeviceInfo() =>
      NativeChannel.instance.getDeviceInfo();

  /// 数据存储：写入
  Future<bool> putData(String key, String value) =>
      NativeChannel.instance.putData(key, value);

  /// 数据存储：读取
  Future<String?> getData(String key, {String defaultValue = ''}) =>
      NativeChannel.instance.getData(key, defaultValue: defaultValue);

  /// 数据存储：删除
  Future<bool> deleteData(String key) =>
      NativeChannel.instance.deleteData(key);

  /// 获取 Cookie
  Future<String?> getCookie(String url, {String? key}) =>
      NativeChannel.instance.getCookie(url, key: key);

  /// Native lib 完整性检查
  Future<bool> checkNativeLib(String libName) =>
      NativeChannel.instance.checkNativeLib(libName);
}
