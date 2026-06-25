/// Web 平台 QuickJS stub
///
/// Web 平台不支持 dart:ffi，无法加载 QuickJS C 库。
/// 此 stub 提供 API 兼容，evaluate 返回错误结果而非抛异常，
/// 避免 Web 平台初始化时崩溃。JS 功能在 Web 上不可用。
class JsEvalResult {
  final String stringResult;
  final bool isError;

  JsEvalResult(this.stringResult, this.isError);
}

class JavascriptRuntime {
  JsEvalResult evaluate(String script) {
    return JsEvalResult('Web 平台不支持 QuickJS', true);
  }

  Future<JsEvalResult> evaluateAsync(String script) async {
    return JsEvalResult('Web 平台不支持 QuickJS', true);
  }

  void dispose() {}
}

JavascriptRuntime getJavascriptRuntime() {
  return JavascriptRuntime();
}
