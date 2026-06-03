import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

HttpServer? _server;

/// 启动 CORS 代理服务，返回实际端口
Future<int> startProxy(int port) async {
  _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  final actualPort = _server!.port;

  _server!.listen(_handleRequest);
  return actualPort;
}

/// 停止代理服务
Future<void> stopProxy() async {
  await _server?.close();
  _server = null;
}

/// 处理代理请求
void _handleRequest(HttpRequest request) {
  final response = request.response;

  // ===== 始终注入跨域头 =====
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PATCH, HEAD');
  response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Target-Url, Accept, X-Requested-With, Cache-Control');
  response.headers.set('Access-Control-Max-Age', '86400');
  response.headers.set('Access-Control-Allow-Credentials', 'true');

  // 预检请求直接返回
  if (request.method == 'OPTIONS') {
    response.statusCode = 204;
    response.close();
    return;
  }

  // 从 URL 路径获取目标 URL
  String targetUrl = request.uri.path.substring(1);
  final headerTargetUrl = request.headers.value('x-target-url');
  if (headerTargetUrl != null && headerTargetUrl != 'undefined') {
    targetUrl = headerTargetUrl;
  }

  if (targetUrl.isEmpty || targetUrl == 'favicon.ico') {
    response.statusCode = 400;
    response.write('Missing target URL');
    response.close();
    return;
  }

  debugPrint('[Proxy] ${request.method} $targetUrl');
  _forwardRequest(request, targetUrl);
}

/// 转发请求到目标 URL
Future<void> _forwardRequest(HttpRequest request, String targetUrl) async {
  final response = request.response;
  try {
    final uri = Uri.parse(targetUrl);
    final client = HttpClient();
    final proxyReq = await client.openUrl(request.method, uri);

    // 复制请求头
    request.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower != 'host' && lower != 'x-target-url' && lower != 'origin' && lower != 'referer') {
        proxyReq.headers.set(name, values);
      }
    });
    proxyReq.headers.set('Host', uri.host);

    // 复制请求体
    final body = await request.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
    if (body.isNotEmpty) {
      proxyReq.add(body);
    }

    final proxyRes = await proxyReq.close();

    // 复制响应头，但不覆盖 CORS 头
    proxyRes.headers.forEach((name, values) {
      if (!name.toLowerCase().startsWith('access-control-')) {
        response.headers.set(name, values);
      }
    });

    // 再次确保跨域头（防止源站覆盖）
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PATCH, HEAD');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Target-Url, Accept, X-Requested-With, Cache-Control');

    response.statusCode = proxyRes.statusCode;
    await proxyRes.pipe(response);
    client.close();
  } catch (e) {
    debugPrint('[Proxy] 转发失败: $e');
    response.statusCode = 502;
    response.write('Proxy error: $e');
    response.close();
  }
}
