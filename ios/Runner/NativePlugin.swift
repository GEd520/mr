import Flutter
import UIKit
import WebKit

/// iOS 原生桥接插件（精简版）
///
/// 架构原则：
/// • 网络请求由 Dart Dio 处理（PlatformBridge），不再经过 MethodChannel
/// • 加密/HTML 解析/编码转换由 C 层 FFI 直接处理
/// • 本插件仅保留平台强依赖 API：屏幕亮度、WebView、数据存储、Cookie、设备信息
///
/// 代码量从 934 行精简至 ~280 行，删除 16 个冗余方法。
class NativePlugin: NSObject, FlutterPlugin {

    // MARK: - 注册

    static let channelName = "com.mr.app/native"

    /// 保持正在运行的 WebView handler 引用，防止被提前释放
    private var activeHandlers: [WebViewJsHandler] = []

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = NativePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    /// 移除已完成的 handler
    fileprivate func removeHandler(_ handler: WebViewJsHandler) {
        activeHandlers.removeAll { $0 === handler }
    }

    // MARK: - MethodChannel 分发

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // 原生库检查（iOS 动态框架由系统自动加载，直接返回 true）
        case "checkNativeLib":
            result(true)
        // 屏幕亮度
        case "getScreenBrightness":
            getScreenBrightness(result: result)
        case "setScreenBrightness":
            setScreenBrightness(call: call, result: result)
        // 数据存储
        case "putData":
            putData(call: call, result: result)
        case "getData":
            getData(call: call, result: result)
        case "deleteData":
            deleteData(call: call, result: result)
        // 设备信息
        case "getDeviceInfo":
            getDeviceInfo(result: result)
        // Cookie
        case "getCookie":
            getCookie(call: call, result: result)
        // WebView JS 执行
        case "executeWebViewJs":
            executeWebViewJs(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 屏幕亮度

    private func getScreenBrightness(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            result(Double(UIScreen.main.brightness))
        }
    }

    private func setScreenBrightness(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let value = (args["value"] as? NSNumber)?.doubleValue else {
            result(FlutterError(code: "INVALID_VALUE", message: "value is required", details: nil))
            return
        }
        DispatchQueue.main.async {
            let clamped = max(0.0, min(1.0, value))
            UIScreen.main.brightness = CGFloat(clamped)
            result(true)
        }
    }

    // MARK: - 数据存储（UserDefaults）

    private func putData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String,
              let value = args["value"] as? String else {
            result(FlutterError(code: "ERROR", message: "key and value are required", details: nil))
            return
        }
        UserDefaults.standard.set(value, forKey: key)
        result(nil)
    }

    private func getData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
            result(FlutterError(code: "ERROR", message: "key is required", details: nil))
            return
        }
        let defaultValue = (args["defaultValue"] as? String) ?? ""
        let value = UserDefaults.standard.string(forKey: key) ?? defaultValue
        result(value)
    }

    private func deleteData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
            result(FlutterError(code: "ERROR", message: "key is required", details: nil))
            return
        }
        UserDefaults.standard.removeObject(forKey: key)
        result(nil)
    }

    // MARK: - 设备信息

    private func getDeviceInfo(result: @escaping FlutterResult) {
        let device = UIDevice.current
        let systemVersion = device.systemVersion
        let sdkInt = Int(systemVersion.split(separator: ".").first ?? "0") ?? 0
        result([
            "sdkInt": sdkInt,
            "release": systemVersion,
            "brand": "Apple",
            "model": device.model,
            "manufacturer": "Apple",
        ])
    }

    // MARK: - Cookie

    private func getCookie(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let url = args["url"] as? String,
              let cookieURL = URL(string: url) else {
            result(FlutterError(code: "ERROR", message: "url is required", details: nil))
            return
        }
        let key = args["key"] as? String

        guard let cookies = HTTPCookieStorage.shared.cookies(for: cookieURL) else {
            result("")
            return
        }

        if let key = key, !key.isEmpty {
            if let cookie = cookies.first(where: { $0.name == key }) {
                result(cookie.value)
            } else {
                result("")
            }
        } else {
            let cookieStr = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            result(cookieStr)
        }
    }

    // MARK: - WebView JS 执行（WKWebView）

    /// 在 WKWebView 中加载 URL 并执行 JS 代码
    /// 对应 Android 的 BackstageWebView.getStrResponse()
    private func executeWebViewJs(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "ERROR", message: "invalid arguments", details: nil))
            return
        }
        let url = (args["url"] as? String) ?? ""
        let jsCode = (args["jsCode"] as? String) ?? "document.documentElement.outerHTML"
        let sourceRegex = args["sourceRegex"] as? String
        let html = args["html"] as? String
        let delayTime = (args["delayTime"] as? Int) ?? 200

        if url.isEmpty && (html?.isEmpty ?? true) {
            result(FlutterError(code: "ERROR", message: "url or html is required", details: nil))
            return
        }

        DispatchQueue.main.async {
            self.runWebViewJs(
                url: url,
                jsCode: jsCode,
                sourceRegex: sourceRegex,
                html: html,
                delayTime: delayTime,
                result: result
            )
        }
    }

    private func runWebViewJs(
        url: String,
        jsCode: String,
        sourceRegex: String?,
        html: String?,
        delayTime: Int,
        result: @escaping FlutterResult
    ) {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

        // 资源嗅探正则
        let sniffRegex: NSRegularExpression? = {
            guard let sourceRegex = sourceRegex, !sourceRegex.isEmpty else { return nil }
            return try? NSRegularExpression(pattern: sourceRegex, options: [])
        }()

        let handler = WebViewJsHandler(
            webView: webView,
            jsCode: jsCode,
            sniffRegex: sniffRegex,
            delayTime: delayTime,
            completion: { jsResult in
                result(jsResult)
            }
        )
        handler.owner = self

        // 设置导航代理
        webView.navigationDelegate = handler

        // 设置资源拦截（用于嗅探）
        if sniffRegex != nil {
            webView.uiDelegate = handler
        }

        // 保持 handler 引用，防止 WKWebView 被提前释放
        activeHandlers.append(handler)

        if let html = html, !html.isEmpty {
            webView.loadHTMLString(html, baseURL: URL(string: url))
        } else if let targetURL = URL(string: url) {
            webView.load(URLRequest(url: targetURL))
        }

        // 30 秒超时
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak handler] in
            handler?.timeout()
        }
    }
}

/// WebView JS 执行的导航代理处理
private class WebViewJsHandler: NSObject, WKNavigationDelegate, WKUIDelegate {
    /// 强引用 WKWebView，确保页面加载和 JS 执行期间不被释放
    private var webView: WKWebView?
    private let jsCode: String
    private let sniffRegex: NSRegularExpression?
    private let delayTime: Int
    private let completion: (String?) -> Void
    private var isCompleted = false
    /// 弱引用 NativePlugin，完成后通知其移除自己
    weak var owner: NativePlugin?

    init(webView: WKWebView,
         jsCode: String,
         sniffRegex: NSRegularExpression?,
         delayTime: Int,
         completion: @escaping (String?) -> Void) {
        self.webView = webView
        self.jsCode = jsCode
        self.sniffRegex = sniffRegex
        self.delayTime = delayTime
        self.completion = completion
        super.init()
    }

    /// 资源嗅探：检查请求 URL 是否匹配正则
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let sniffRegex = sniffRegex {
            let reqURL = navigationAction.request.url?.absoluteString ?? ""
            let range = NSRange(location: 0, length: reqURL.utf16.count)
            if sniffRegex.firstMatch(in: reqURL, options: [], range: range) != nil {
                complete(reqURL)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    /// 页面加载完成：执行 JS
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(delayTime) / 1000.0) { [weak self] in
            guard let self = self, !self.isCompleted else { return }
            webView.evaluateJavaScript(self.jsCode) { [weak self] evalResult, _ in
                guard let self = self, !self.isCompleted else { return }
                self.complete(self.cleanJsResult(evalResult))
            }
        }
    }

    /// 页面加载失败
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        complete(nil)
    }

    /// 超时处理
    func timeout() {
        complete(nil)
    }

    /// 统一完成入口：确保只调用一次，并清理资源
    private func complete(_ result: String?) {
        guard !isCompleted else { return }
        isCompleted = true
        completion(result)
        // 清理 WKWebView 引用，避免内存泄漏
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        // 通知 NativePlugin 移除自己
        owner?.removeHandler(self)
    }

    /// 清理 JS 执行结果（与 Android 的清理逻辑保持一致）
    private func cleanJsResult(_ result: Any?) -> String? {
        guard let result = result else { return nil }
        var str: String
        if let s = result as? String {
            str = s
        } else {
            str = "\(result)"
        }
        if str == "null" || str.isEmpty {
            return nil
        }
        // 去掉首尾引号
        if str.hasPrefix("\"") { str.removeFirst() }
        if str.hasSuffix("\"") { str.removeLast() }
        // 反转义
        str = str.replacingOccurrences(of: "\\u003C", with: "<")
        str = str.replacingOccurrences(of: "\\u003E", with: ">")
        str = str.replacingOccurrences(of: "\\/", with: "/")
        str = str.replacingOccurrences(of: "\\n", with: "\n")
        str = str.replacingOccurrences(of: "\\t", with: "\t")
        str = str.replacingOccurrences(of: "\\\"", with: "\"")
        return str
    }
}
