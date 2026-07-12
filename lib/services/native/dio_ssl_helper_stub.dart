import 'package:dio/dio.dart';

/// Web 平台 SSL 配置 stub（浏览器自行处理证书，无需配置）
void configureDioSslBypass(Dio dio) {
  // no-op: Web 平台由浏览器处理 TLS
}
