import 'package:flutter/foundation.dart';
import 'proxy_service_stub.dart'
    if (dart.library.io) 'proxy_service_native.dart' as impl;

class ProxyService {
  static final ProxyService _instance = ProxyService._internal();
  static ProxyService get instance => _instance;
  ProxyService._internal();

  bool _isRunning = false;
  int _port = 0;

  bool get isRunning => _isRunning;
  int get port => _port;

  /// 启动 CORS 代理服务
  /// [port] 指定端口，0 或不传则随机分配
  Future<void> start({int port = 0}) async {
    if (kIsWeb) {
      debugPrint('Web平台需要外部代理服务');
      debugPrint('请运行: node tools/cors-proxy.js');
      return;
    }

    if (_isRunning) return;

    final result = await impl.startProxy(port);
    _port = result;
    _isRunning = true;

    debugPrint('🚀 CORS Proxy 启动于 http://localhost:$_port (端口${port == 0 ? "随机分配" : "指定"})');
  }

  Future<void> stop() async {
    await impl.stopProxy();
    _isRunning = false;
    _port = 0;
    debugPrint('代理服务已停止');
  }
}
