import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 非 Web 平台：允许不安全 SSL 证书
///
/// 书源网站证书常有问题（自签名/过期/链不完整/TLS 版本旧），
/// 不绕过会导致 HandshakeException，图片和内容都无法加载。
void configureDioSslBypass(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = () {
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      return client;
    };
  }
}
