Future<String> fetch(String url, {
  String method = 'GET',
  Map<String, String>? headers,
  String? body,
}) async {
  throw UnsupportedError('WebProxy only works on web platform');
}
