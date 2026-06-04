import 'package:flutter/foundation.dart';
import 'platform_channel.dart';
import '../app_logger.dart';

/// JsExtensions 桥接层
/// 借鉴 legado 的 JsExtensions 接口设计
/// 将 JS 中的 java.* 调用桥接到 Dart 侧的 NativeChannel
///
/// 双轨并行策略：
/// - 旧书源：继续使用 js_engine.dart 中的 stub java 对象
/// - 新书源：通过 JsExtensionsBridge 获得真实的桥接实现
class JsExtensionsBridge {
  JsExtensionsBridge._();
  static final JsExtensionsBridge instance = JsExtensionsBridge._();

  // ===== HTTP 请求 =====

  /// 异步 HTTP GET，返回响应体字符串
  /// 对应 legado 的 java.ajax(url)
  Future<String?> ajax(String url, {Map<String, String>? headers, int? timeoutMs}) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.httpGet(
        url,
        headers: headers,
        timeoutMs: timeoutMs ?? 10000,
      );
    } catch (e) {
      AppLogger.instance.logJsError('JsExtensions', 'ajax失败: $e');
      return null;
    }
  }

  /// 并发 HTTP 请求
  /// 对应 legado 的 java.ajaxAll(urlList)
  Future<List<String?>> ajaxAll(List<String> urls, {Map<String, String>? headers}) async {
    final results = <String?>[];
    // 并发执行
    final futures = urls.map((url) => ajax(url, headers: headers));
    results.addAll(await Future.wait(futures));
    return results;
  }

  /// HTTP GET 请求（Jsoup 方式，支持重定向拦截）
  /// 对应 legado 的 java.get(url, headers)
  Future<String?> get(String url, {Map<String, String>? headers, int? timeoutMs}) async {
    return ajax(url, headers: headers, timeoutMs: timeoutMs);
  }

  /// HTTP POST 请求
  /// 对应 legado 的 java.post(url, body, headers)
  Future<String?> post(String url, {String? body, Map<String, String>? headers, int? timeoutMs}) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.httpPost(
        url,
        body: body,
        headers: headers,
        timeoutMs: timeoutMs ?? 10000,
      );
    } catch (e) {
      AppLogger.instance.logJsError('JsExtensions', 'post失败: $e');
      return null;
    }
  }

  // ===== 加解密 =====

  /// AES 加密
  /// 对应 legado 的 java.aesEncode(data, key, iv)
  Future<String?> aesEncode(String data, String key, {String? iv}) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.aesEncrypt(data, key, iv: iv);
    } catch (e) {
      AppLogger.instance.logJsError('JsExtensions', 'aesEncode失败: $e');
      return null;
    }
  }

  /// AES 解密
  /// 对应 legado 的 java.aesDecode(data, key, iv)
  Future<String?> aesDecode(String data, String key, {String? iv}) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.aesDecrypt(data, key, iv: iv);
    } catch (e) {
      AppLogger.instance.logJsError('JsExtensions', 'aesDecode失败: $e');
      return null;
    }
  }

  /// MD5 哈希
  /// 对应 legado 的 java.md5Encode(str)
  Future<String?> md5Encode(String str) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.md5(str);
    } catch (e) {
      return null;
    }
  }

  /// Base64 编码
  Future<String?> base64Encode(String str) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.base64Encode(str);
    } catch (e) {
      return null;
    }
  }

  /// Base64 解码
  Future<String?> base64Decode(String str) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.base64Decode(str);
    } catch (e) {
      return null;
    }
  }

  // ===== Jsoup HTML 解析 =====

  /// CSS 选择器选择第一个元素
  Future<String?> jsoupSelectFirst(String html, String selector) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.jsoupSelect(html, selector);
    } catch (e) {
      return null;
    }
  }

  /// CSS 选择器选择所有元素
  Future<List<String>?> jsoupSelectAll(String html, String selector) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.jsoupSelectAll(html, selector);
    } catch (e) {
      return null;
    }
  }

  /// 获取元素属性
  Future<String?> jsoupGetAttr(String html, String selector, String attr) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.jsoupGetAttr(html, selector, attr);
    } catch (e) {
      return null;
    }
  }

  /// 清理 HTML
  Future<String?> jsoupClean(String html) async {
    try {
      if (kIsWeb) return null;
      return await NativeChannel.instance.jsoupClean(html);
    } catch (e) {
      return null;
    }
  }

  // ===== 数据持久化 =====

  /// 存储键值对
  Future<bool> putData(String key, String value) async {
    try {
      if (kIsWeb) return false;
      return await NativeChannel.instance.putData(key, value);
    } catch (e) {
      return false;
    }
  }

  /// 读取键值对
  Future<String?> getData(String key, {String defaultValue = ''}) async {
    try {
      if (kIsWeb) return defaultValue;
      return await NativeChannel.instance.getData(key, defaultValue: defaultValue);
    } catch (e) {
      return defaultValue;
    }
  }

  /// 删除键值对
  Future<bool> deleteData(String key) async {
    try {
      if (kIsWeb) return false;
      return await NativeChannel.instance.deleteData(key);
    } catch (e) {
      return false;
    }
  }

  // ===== 工具方法 =====

  /// 时间格式化
  String timeFormat(int timestamp, {String format = 'yyyy-MM-dd HH:mm:ss'}) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return date.toIso8601String();
  }

  /// 获取当前时间戳
  int getTime() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// URI 编码
  String encodeURI(String str) {
    return Uri.encodeFull(str);
  }

  /// Hex 编码
  String hexEncode(String str) {
    return str.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hex 解码
  String hexDecode(String hex) {
    final result = StringBuffer();
    for (var i = 0; i < hex.length; i += 2) {
      final code = int.parse(hex.substring(i, i + 2), radix: 16);
      result.writeCharCode(code);
    }
    return result.toString();
  }

  // ===== 安全沙箱 =====

  /// 检查 URL 是否安全（防止 SSRF 攻击）
  bool isUrlSafe(String url) {
    final blocked = ['127.0.0.1', 'localhost', '0.0.0.0', '::1', '169.254.'];
    for (final pattern in blocked) {
      if (url.contains(pattern)) return false;
    }
    return true;
  }

  /// 检查文件路径是否安全（防止路径遍历攻击）
  bool isPathSafe(String path) {
    return !path.contains('..') && !path.startsWith('/');
  }
}
