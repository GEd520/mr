import 'dart:async';
import 'dart:html';

Future<String> fetch(String url, {
  String method = 'GET',
  Map<String, String>? headers,
  String? body,
}) async {
  final completer = Completer<String>();
  
  final request = HttpRequest();
  
  request.open(method, url);
  
  headers?.forEach((key, value) {
    request.setRequestHeader(key, value);
  });
  
  request.onLoad.listen((_) {
    final status = request.status ?? 0;
    if (status >= 200 && status < 300) {
      completer.complete(request.responseText ?? '');
    } else {
      completer.completeError('HTTP $status: ${request.statusText}');
    }
  });
  
  request.onError.listen((e) {
    completer.completeError('Network error');
  });
  
  try {
    if (body != null) {
      request.send(body);
    } else {
      request.send();
    }
  } catch (e) {
    completer.completeError('Request failed: $e');
  }
  
  return completer.future;
}
