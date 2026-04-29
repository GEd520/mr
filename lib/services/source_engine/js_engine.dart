import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';

class JsEngine {
  static final JsEngine instance = JsEngine._internal();
  JsEngine._internal();

  JavascriptRuntime? _runtime;
  bool _initialized = false;
  final Map<String, dynamic> _globalVariables = {};

  Future<void> init() async {
    if (_initialized) return;
    
    _runtime = getJavascriptRuntime();
    _initialized = true;
  }

  void setGlobalVariable(String name, dynamic value) {
    _globalVariables[name] = value;
  }

  dynamic getGlobalVariable(String name) {
    return _globalVariables[name];
  }

  Future<dynamic> execute(String jsCode, {Map<String, dynamic>? variables}) async {
    if (!_initialized) {
      await init();
    }

    final runtime = _runtime!;
    
    final setupCode = StringBuffer();
    
    for (final entry in _globalVariables.entries) {
      setupCode.writeln('var ${entry.key} = ${_encodeValue(entry.value)};');
    }
    
    if (variables != null) {
      for (final entry in variables.entries) {
        setupCode.writeln('var ${entry.key} = ${_encodeValue(entry.value)};');
      }
    }

    final fullCode = '$setupCode\n$jsCode';
    
    try {
      final result = await runtime.evaluateAsync(fullCode);
      
      if (result.isError) {
        return null;
      }
      
      final stringResult = result.stringResult;
      
      if (stringResult.isEmpty || stringResult == 'undefined') {
        return null;
      }
      
      try {
        return json.decode(stringResult);
      } catch (_) {
        return stringResult;
      }
    } catch (e) {
      return null;
    }
  }

  Future<String?> executeString(String jsCode, {Map<String, dynamic>? variables}) async {
    final result = await execute(jsCode, variables: variables);
    return result?.toString();
  }

  Future<int?> executeInt(String jsCode, {Map<String, dynamic>? variables}) async {
    final result = await execute(jsCode, variables: variables);
    if (result is int) return result;
    if (result is double) return result.toInt();
    if (result is String) return int.tryParse(result);
    return null;
  }

  Future<double?> executeDouble(String jsCode, {Map<String, dynamic>? variables}) async {
    final result = await execute(jsCode, variables: variables);
    if (result is double) return result;
    if (result is int) return result.toDouble();
    if (result is String) return double.tryParse(result);
    return null;
  }

  Future<bool?> executeBool(String jsCode, {Map<String, dynamic>? variables}) async {
    final result = await execute(jsCode, variables: variables);
    if (result is bool) return result;
    if (result is String) {
      final lower = result.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return null;
  }

  Future<List<dynamic>?> executeList(String jsCode, {Map<String, dynamic>? variables}) async {
    final result = await execute(jsCode, variables: variables);
    if (result is List) return result;
    return null;
  }

  Future<Map<String, dynamic>?> executeMap(String jsCode, {Map<String, dynamic>? variables}) async {
    final result = await execute(jsCode, variables: variables);
    if (result is Map) return Map<String, dynamic>.from(result);
    return null;
  }

  String _encodeValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return json.encode(value);
    if (value is num || value is bool) return value.toString();
    if (value is List || value is Map) return json.encode(value);
    return json.encode(value.toString());
  }

  void dispose() {
    _runtime?.dispose();
    _runtime = null;
    _initialized = false;
    _globalVariables.clear();
  }

  Future<String?> processJsRule(String content, String jsCode, {String? baseUrl}) async {
    if (!_initialized) {
      await init();
    }

    final variables = <String, dynamic>{
      'result': content,
      'src': content,
      'html': content,
    };
    
    if (baseUrl != null) {
      variables['baseUrl'] = baseUrl;
    }

    return executeString(jsCode, variables: variables);
  }

  Future<String?> processJsWithBook(
    String jsCode, {
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    String? content,
    int? index,
  }) async {
    if (!_initialized) {
      await init();
    }

    final variables = <String, dynamic>{};
    
    if (book != null) variables['book'] = book;
    if (chapter != null) variables['chapter'] = chapter;
    if (content != null) variables['result'] = content;
    if (index != null) variables['index'] = index;

    return executeString(jsCode, variables: variables);
  }
}
