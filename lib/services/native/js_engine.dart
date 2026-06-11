import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import '../app_logger.dart';
import 'platform_channel.dart';
import 'shared_js_scope.dart';

// ===== 分流引擎架构 =====

/// JS 引擎类型枚举
enum JsEngineType {
  /// QuickJS 引擎（flutter_js），原生支持 ES6+
  quickjs,

  /// Rhino 引擎（Android 原生），支持 Java 互操作
  rhino,
}

/// 引擎分流解析结果
class _EngineResolveResult {
  final JsEngineType engine;
  final String code;

  const _EngineResolveResult(this.engine, this.code);
}

/// JS/TS 运行时引擎 - 分流双引擎架构
///
/// 架构设计：
/// - QuickJS 引擎：处理 ES6+ 语法，作为默认引擎
/// - Rhino 引擎：处理 Java 互操作（通过 NativeChannel）
/// - 分流策略：显式声明 > 关键词自动识别 > 默认 QuickJS
/// - 桥接层：两个引擎共享缓存和变量
class JsEngine {
  static JsEngine? _instance;
  static JsEngine get instance => _instance ??= JsEngine._();

  JsEngine._();

  bool _initialized = false;
  JavascriptRuntime? _jsRuntime;
  final Map<String, String> _installedPackages = {};
  final Map<String, String> _moduleCache = {};

  // ===== 脚本编译缓存（借鉴 legado 的 scriptCache）=====
  /// 缓存编译后的脚本结果，避免重复 evaluate 相同代码
  /// key: JS代码的MD5, value: evaluate结果
  final Map<String, dynamic> _scriptCache = {};
  static const int _maxScriptCacheSize = 16;

  // ===== 共享作用域变量（借鉴 legado 的 SharedJsScope）=====
  /// 书源级共享变量，跨规则共享
  final Map<String, Map<String, String>> _sharedScopeVars = {};

  /// 书源级 jsLib 缓存（借鉴 legado 的 SharedJsScope）
  /// key: bookSourceUrl, value: jsLib 代码
  final Map<String, String> _jsLibCache = {};

  /// 当前已加载到 globalThis 的 jsLib 所属的书源 URL
  /// 借鉴 legado 的 SharedJsScope：同一书源的 jsLib 只加载一次，切换书源时清除旧的
  String? _currentJsLibSourceUrl;

  /// 当前已加载的 jsLib 中定义的全局函数名列表
  /// 用于切换书源时清除旧函数，避免全局污染
  final List<String> _currentJsLibFunctions = [];

  // ===== 引擎桥接层：跨引擎共享缓存 =====

  /// 跨引擎共享缓存（QuickJS 和 Rhino 均可读写）
  final Map<String, String> _bridgeCache = {};

  /// 获取桥接缓存
  String bridgeGet(String key) => _bridgeCache[key] ?? '';

  /// 写入桥接缓存
  void bridgePut(String key, String value) {
    _bridgeCache[key] = value;
  }

  /// 删除桥接缓存
  void bridgeDelete(String key) {
    _bridgeCache.remove(key);
  }

  // ===== 初始化 =====

  /// 初始化 JS 引擎
  Future<bool> init() async {
    if (_initialized && _jsRuntime != null) {
      // 验证全局对象是否仍然存在（防止运行时被意外重置）
      final check = evaluate('typeof java !== "undefined" && typeof CryptoJS !== "undefined" && typeof _javaCache !== "undefined" && typeof _AES !== "undefined"');
      if (check == 'true') return true;
      // 全局对象丢失，需要重新注入
      debugPrint('JsEngine: 全局对象丢失，重新注入 polyfills');
      _injectJavaBridge();
      final recheck = evaluate('typeof java !== "undefined"');
      if (recheck == 'true') return true;
      // 重新注入也失败，重建运行时
      debugPrint('JsEngine: 重新注入失败，重建运行时');
      _jsRuntime?.dispose();
      _jsRuntime = null;
      _initialized = false;
    }

    if (_initialized) return true;
    try {
      _jsRuntime = getJavascriptRuntime();
      // 先标记运行时可用，再注入 polyfills
      // 注意：_initialized 在所有注入完成后才设为 true
      await _injectNodePolyfills();
      _injectJavaBridge();
      await _loadInstalledPackages();

      // 验证注入是否成功
      final verifyResult = evaluate('typeof java !== "undefined" && typeof CryptoJS !== "undefined" && typeof _javaCache !== "undefined" && typeof _AES !== "undefined"');
      if (verifyResult != 'true') {
        debugPrint('JsEngine: 注入验证失败！java=${evaluate('typeof java')}, CryptoJS=${evaluate('typeof CryptoJS')}, _javaCache=${evaluate('typeof _javaCache')}, _AES=${evaluate('typeof _AES')}');
        // 尝试重新注入
        _injectJavaBridge();
        final retryResult = evaluate('typeof java !== "undefined" && typeof _AES !== "undefined"');
        if (retryResult != 'true') {
          debugPrint('JsEngine: 重新注入仍然失败，初始化失败');
          return false;
        }
      }

      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('JsEngine init error: $e');
      return false;
    }
  }

  bool get isAvailable => _initialized && _jsRuntime != null;

  // ===== 分流策略 =====

  /// 解析规则代码，确定使用哪个引擎（公开，供 EngineDispatcher 调用）
  ///
  /// 优先级：
  /// 1. 显式前缀声明：@rhino: / @quickjs: / @java: / @ts: / @js:
  /// 2. 关键词自动识别（无显式声明时）
  /// 3. 书源级全局声明（sourceEngine 参数）
  /// 4. 默认 QuickJS
  _EngineResolveResult resolveEngine(String ruleCode, {JsEngineType? sourceEngine}) {
    // 1. 显式前缀声明
    if (ruleCode.startsWith('@rhino:') || ruleCode.startsWith('<rhino>')) {
      final code = ruleCode.startsWith('@rhino:')
          ? ruleCode.substring(7)
          : ruleCode.replaceAll(RegExp(r'^<rhino>|</rhino>$'), '');
      return _EngineResolveResult(JsEngineType.rhino, code);
    }

    if (ruleCode.startsWith('@quickjs:') || ruleCode.startsWith('<quickjs>')) {
      final code = ruleCode.startsWith('@quickjs:')
          ? ruleCode.substring(9)
          : ruleCode.replaceAll(RegExp(r'^<quickjs>|</quickjs>$'), '');
      return _EngineResolveResult(JsEngineType.quickjs, code);
    }

    if (ruleCode.startsWith('@java:') || ruleCode.startsWith('<java>')) {
      final code = ruleCode.startsWith('@java:')
          ? ruleCode.substring(6)
          : ruleCode.replaceAll(RegExp(r'^<java>|</java>$'), '');
      return _EngineResolveResult(JsEngineType.rhino, code);
    }

    if (ruleCode.startsWith('@ts:') || ruleCode.startsWith('<ts>')) {
      final code = ruleCode.startsWith('@ts:')
          ? ruleCode.substring(4)
          : ruleCode.replaceAll(RegExp(r'^<ts>|</ts>$'), '');
      // TS 编译后由 QuickJS 执行
      return _EngineResolveResult(JsEngineType.quickjs, code);
    }

    // 2. @js: 或 <js> 前缀 → 自动识别
    String code = ruleCode;
    if (ruleCode.startsWith('@js:')) {
      code = ruleCode.substring(4);
    } else if (ruleCode.startsWith('<js>')) {
      code = ruleCode.replaceAll(RegExp(r'^<js>|</js>$'), '');
    }

    // 自动识别引擎
    final autoDetected = _autoDetectEngine(code);

    // 3. 如果自动识别不出明确倾向，使用书源级声明
    if (autoDetected == null && sourceEngine != null) {
      return _EngineResolveResult(sourceEngine, code);
    }

    // 4. 默认 QuickJS
    return _EngineResolveResult(autoDetected ?? JsEngineType.quickjs, code);
  }

  /// 关键词自动识别引擎
  ///
  /// - 含 java. 前缀调用且无 ES6 特征 → Rhino
  /// - 含 ES6 特征（不管有无 java.*）→ QuickJS
  /// - 无法确定 → null（使用书源级声明或默认值）
  JsEngineType? _autoDetectEngine(String code) {
    final hasJavaCall = RegExp(r'\bjava\.').hasMatch(code);
    final hasES6 = RegExp(
      r'\bconst\b|\blet\b|=>|\basync\b|\bawait\b|\.\.\.|\bclass\b|\bimport\b|`[^`]*\$\{',
    ).hasMatch(code);

    if (hasES6) {
      // ES6 特征 → QuickJS（java.* 通过桥接调用）
      return JsEngineType.quickjs;
    }

    if (hasJavaCall && !hasES6) {
      // 纯 Java 互操作，无 ES6 → Rhino
      return JsEngineType.rhino;
    }

    // 无法确定，返回 null 让上层决定
    return null;
  }

  // ===== Node.js API 兼容层 =====

  Future<void> _injectNodePolyfills() async {
    const nodePolyfills = '''
      // ===== Node.js 核心模块模拟 =====

      var process = {
        env: {},
        argv: [],
        version: 'v18.17.0',
        versions: { node: '18.17.0', v8: '10.2.154.4' },
        platform: 'android',
        arch: 'arm64',
        pid: 1,
        cwd: function() { return '/'; },
        exit: function(code) {},
        nextTick: function(fn) { setTimeout(fn, 0); },
        on: function(event, handler) {},
        stdout: { write: function(data) {} },
        stderr: { write: function(data) {} },
      };

      var Buffer = {
        from: function(data, encoding) {
          if (typeof data === 'string') {
            return { toString: function() { return data; }, length: data.length };
          }
          return { length: data ? data.length : 0 };
        },
        isBuffer: function(obj) { return false; },
        concat: function(list) { return Buffer.from(list.join('')); },
      };

      // ===== URL/URLSearchParams 完整实现 =====
      function URL(url, base) {
        if (!(this instanceof URL)) return new URL(url, base);
        var input = url || '';
        // 处理 base URL
        if (base) {
          var baseParsed = new URL(base);
          if (input.startsWith('/') || input.startsWith('./') || input.startsWith('../')) {
            input = baseParsed.origin + input;
          } else if (!input.startsWith('http')) {
            input = baseParsed.origin + '/' + input;
          }
        }
        this.href = input;
        // 解析 protocol
        var protoMatch = input.match(/^(https?:)\\/\\//i);
        this.protocol = protoMatch ? protoMatch[1] : '';
        // 解析 host (hostname:port)
        var hostMatch = input.match(/^https?:\\/\\/([^/\\?#]+)/i);
        this.host = hostMatch ? hostMatch[1] : '';
        // 解析 hostname 和 port
        if (this.host) {
          var parts = this.host.split(':');
          this.hostname = parts[0];
          this.port = parts.length > 1 ? parts[1] : '';
        } else {
          this.hostname = '';
          this.port = '';
        }
        this.origin = this.protocol ? this.protocol + '//' + this.host : '';
        // 解析 pathname, search, hash
        var pathPart = hostMatch ? input.substring(hostMatch.index + hostMatch[0].length) : input;
        var hashIdx = pathPart.indexOf('#');
        var hashPart = '';
        if (hashIdx >= 0) {
          hashPart = pathPart.substring(hashIdx);
          pathPart = pathPart.substring(0, hashIdx);
        }
        var searchIdx = pathPart.indexOf('?');
        if (searchIdx >= 0) {
          this.search = pathPart.substring(searchIdx);
          this.pathname = pathPart.substring(0, searchIdx) || '/';
        } else {
          this.search = '';
          this.pathname = pathPart || '/';
        }
        this.hash = hashPart;
        this.toString = function() { return this.href; };
      }
      function URLSearchParams(init) {
        if (!(this instanceof URLSearchParams)) return new URLSearchParams(init);
        this._params = [];
        if (typeof init === 'string') {
          var str = init.startsWith('?') ? init.substring(1) : init;
          if (str) {
            var pairs = str.split('&');
            for (var i = 0; i < pairs.length; i++) {
              var eq = pairs[i].indexOf('=');
              if (eq >= 0) {
                this._params.push([decodeURIComponent(pairs[i].substring(0, eq)), decodeURIComponent(pairs[i].substring(eq + 1))]);
              } else if (pairs[i]) {
                this._params.push([decodeURIComponent(pairs[i]), '']);
              }
            }
          }
        }
        this.get = function(name) {
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] === name) return this._params[i][1];
          }
          return null;
        };
        this.getAll = function(name) {
          var results = [];
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] === name) results.push(this._params[i][1]);
          }
          return results;
        };
        this.set = function(name, value) {
          var found = false;
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] === name) {
              if (!found) { this._params[i][1] = value; found = true; }
              else { this._params.splice(i, 1); i--; }
            }
          }
          if (!found) this._params.push([name, value]);
        };
        this.has = function(name) {
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] === name) return true;
          }
          return false;
        };
        this.delete = function(name) {
          for (var i = 0; i < this._params.length; i++) {
            if (this._params[i][0] === name) { this._params.splice(i, 1); i--; }
          }
        };
        this.append = function(name, value) { this._params.push([name, value]); };
        this.toString = function() {
          return this._params.map(function(p) {
            return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
          }).join('&');
        };
        this.keys = function() { return this._params.map(function(p) { return p[0]; }); };
        this.values = function() { return this._params.map(function(p) { return p[1]; }); };
        this.entries = function() { return this._params.map(function(p) { return [p[0], p[1]]; }); };
        this.forEach = function(fn) { for (var i = 0; i < this._params.length; i++) fn(this._params[i][1], this._params[i][0]); };
      }

      function EventEmitter() {
        this._events = {};
      }
      EventEmitter.prototype.on = function(event, handler) {
        if (!this._events[event]) this._events[event] = [];
        this._events[event].push(handler);
        return this;
      };
      EventEmitter.prototype.emit = function(event) {
        var args = Array.from(arguments).slice(1);
        (this._events[event] || []).forEach(function(handler) { handler.apply(null, args); });
        return this;
      };
      EventEmitter.prototype.off = function(event, handler) {
        if (this._events[event]) {
          this._events[event] = this._events[event].filter(function(h) { return h !== handler; });
        }
        return this;
      };
      EventEmitter.prototype.once = function(event, handler) {
        var self = this;
        var wrapper = function() {
          handler.apply(null, arguments);
          self.off(event, wrapper);
        };
        return this.on(event, wrapper);
      };

      var _modules = {};
      var _moduleCache = {};
      function require(name) {
        if (_moduleCache[name]) return _moduleCache[name];
        if (_modules[name]) {
          var module = { exports: {} };
          _modules[name](module, module.exports, require);
          _moduleCache[name] = module.exports;
          return _moduleCache[name];
        }
        switch(name) {
          case 'http': return { get: function(url, cb) {}, request: function() {} };
          case 'https': return { get: function(url, cb) {}, request: function() {} };
          case 'fs': return { readFileSync: function(path) { return ''; }, writeFileSync: function(path, data) {} };
          case 'path': return { join: function() { return Array.from(arguments).join('/'); }, resolve: function() { return '/'; }, basename: function(p) { return p.split('/').pop(); }, dirname: function(p) { return p.split('/').slice(0, -1).join('/'); } };
          case 'crypto': return { createHash: function(algo) { return { update: function(d) { return this; }, digest: function(enc) { return ''; } }; }, randomBytes: function(n) { return []; } };
          case 'url': return { parse: function(u) { return new URL(u); }, format: function(u) { return u.href || u; } };
          case 'querystring': return { parse: function(q) { var r = {}; q.split('&').forEach(function(p) { var kv = p.split('='); r[kv[0]] = kv[1]; }); return r; }, stringify: function(o) { return Object.keys(o).map(function(k) { return k + '=' + o[k]; }).join('&'); } };
          case 'events': return { EventEmitter: EventEmitter };
          case 'stream': return { Readable: function() {}, Writable: function() {}, Transform: function() {} };
          case 'util': return { promisify: function(fn) { return fn; }, inherits: function() {}, inspect: function(obj) { return JSON.stringify(obj); } };
          case 'cheerio': return { load: function(html) { return function(sel) { return { text: function() { return ''; }, attr: function(a) { return ''; }, find: function(s) { return this; }, each: function(fn) {} }; }; } };
          default: throw new Error('Module not found: ' + name);
        }
      }

      // ===== fetch() 全局函数 =====
      // 借鉴 legado 的 JsExtensions.ajax：直接返回 HTML 字符串（同步模式）
      // legado 书源中 fetch(url) 期望直接得到 HTML，不是 Response 对象
      function fetch(input, init) {
        var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
        var method = (init && init.method) || 'GET';
        // 自动拼接 baseUrl
        var fullUrl = url;
        if (url && !url.startsWith('http') && typeof baseUrl !== 'undefined' && baseUrl) {
          fullUrl = baseUrl.replace(/\/+\$/, '') + '/' + url.replace(/^\/+/, '');
        }
        var cacheKey = method.toUpperCase() === 'POST' ? 'http_post:' + fullUrl : 'http_get:' + fullUrl;
        if (_javaCache[cacheKey] !== undefined) {
          return _javaCache[cacheKey];
        }
        // fallback: 尝试原始 url
        if (fullUrl !== url) {
          var origKey = method.toUpperCase() === 'POST' ? 'http_post:' + url : 'http_get:' + url;
          if (_javaCache[origKey] !== undefined) return _javaCache[origKey];
        }
        return '';
      }

      // ===== XMLHttpRequest 简易实现 =====
      // 同步模式：从缓存取结果；异步模式：回调触发但数据仍来自缓存
      function XMLHttpRequest() {
        this.readyState = 0;
        this.status = 0;
        this.statusText = '';
        this.responseText = '';
        this.responseXML = null;
        this.response = '';
        this.responseType = '';
        this.timeout = 0;
        this.withCredentials = false;
        this._method = 'GET';
        this._url = '';
        this._headers = {};
        this._async = true;
        this.onreadystatechange = null;
        this.onload = null;
        this.onerror = null;
        this.onabort = null;
        this.ontimeout = null;
        this.onprogress = null;
      }
      XMLHttpRequest.prototype.open = function(method, url, async) {
        this._method = method.toUpperCase();
        this._url = url;
        this._async = async !== false;
        this.readyState = 1;
      };
      XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        this._headers[name] = value;
      };
      XMLHttpRequest.prototype.send = function(body) {
        var self = this;
        var url = this._url;
        // 自动拼接 baseUrl
        if (url && !url.startsWith('http') && typeof baseUrl !== 'undefined' && baseUrl) {
          url = baseUrl.replace(/\/+\$/, '') + '/' + url.replace(/^\/+/, '');
        }
        var cacheKey = this._method === 'POST' ? 'http_post:' + url : 'http_get:' + url;
        var cachedText = _javaCache[cacheKey] || '';
        // fallback: 尝试原始 url
        if (!cachedText && url !== this._url) {
          var origKey = this._method === 'POST' ? 'http_post:' + this._url : 'http_get:' + this._url;
          cachedText = _javaCache[origKey] || '';
        }
        this.readyState = 2;
        if (this.onreadystatechange) this.onreadystatechange();
        this.readyState = 3;
        if (this.onreadystatechange) this.onreadystatechange();
        this.status = cachedText ? 200 : 0;
        this.statusText = cachedText ? 'OK' : 'No cache';
        this.responseText = cachedText;
        this.response = cachedText;
        this.readyState = 4;
        if (this.onreadystatechange) this.onreadystatechange();
        if (cachedText && this.onload) this.onload();
        else if (!cachedText && this.onerror) this.onerror();
      };
      XMLHttpRequest.prototype.abort = function() {
        this.readyState = 0;
        if (this.onabort) this.onabort();
      };
      XMLHttpRequest.prototype.getResponseHeader = function(name) { return null; };
      XMLHttpRequest.prototype.getAllResponseHeaders = function() { return ''; };

      // ===== setTimeout / setInterval =====
      // QuickJS 可能不支持，提供 polyfill
      if (typeof setTimeout === 'undefined') {
        var _timerId = 0;
        var _timers = {};
        globalThis.setTimeout = function(fn, delay) { var id = ++_timerId; fn(); return id; };
        globalThis.setInterval = function(fn, delay) { var id = ++_timerId; fn(); return id; };
        globalThis.clearTimeout = function(id) { delete _timers[id]; };
        globalThis.clearInterval = function(id) { delete _timers[id]; };
      }

      // ===== console 增强 =====
      // 借鉴 legado：所有 console 输出同步到调试页面
      // 注意：总是覆盖 console，因为 QuickJS 可能已有内置 console 但没有 _getLogs
      var _consoleLogs = [];
      globalThis.console = {
        log: function() { var msg = Array.from(arguments).join(' '); _consoleLogs.push({level:'log', msg:msg}); },
        warn: function() { var msg = Array.from(arguments).join(' '); _consoleLogs.push({level:'warn', msg:msg}); },
        error: function() { var msg = Array.from(arguments).join(' '); _consoleLogs.push({level:'error', msg:msg}); },
        info: function() { var msg = Array.from(arguments).join(' '); _consoleLogs.push({level:'info', msg:msg}); },
        debug: function() { var msg = Array.from(arguments).join(' '); _consoleLogs.push({level:'debug', msg:msg}); },
        dir: function(obj) { _consoleLogs.push({level:'log', msg: JSON.stringify(obj, null, 2)}); },
        table: function(data) { _consoleLogs.push({level:'log', msg: JSON.stringify(data, null, 2)}); },
        time: function(label) { _consoleLogs._timers = _consoleLogs._timers || {}; _consoleLogs._timers[label] = Date.now(); },
        timeEnd: function(label) { _consoleLogs._timers = _consoleLogs._timers || {}; if (_consoleLogs._timers[label]) { var ms = Date.now() - _consoleLogs._timers[label]; _consoleLogs.push({level:'info', msg: label + ': ' + ms + 'ms'}); delete _consoleLogs._timers[label]; } },
        count: function(label) { _consoleLogs._counts = _consoleLogs._counts || {}; _consoleLogs._counts[label] = (_consoleLogs._counts[label] || 0) + 1; _consoleLogs.push({level:'info', msg: label + ': ' + _consoleLogs._counts[label]}); },
        assert: function(condition) { if (!condition) { var msg = Array.from(arguments).slice(1).join(' ') || 'Assertion failed'; _consoleLogs.push({level:'error', msg: msg}); } },
        clear: function() { _consoleLogs.length = 0; },
        _getLogs: function() { return _consoleLogs; },
        _clearLogs: function() { _consoleLogs.length = 0; },
      };

      // ===== btoa/atob 全局函数 =====
      // Base64 编码/解码，QuickJS 原生可能不提供
      if (typeof btoa === 'undefined') {
        var _b64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        globalThis.btoa = function(str) {
          var output = '';
          for (var i = 0; i < str.length; i += 3) {
            var byte1 = str.charCodeAt(i);
            var byte2 = i + 1 < str.length ? str.charCodeAt(i + 1) : 0;
            var byte3 = i + 2 < str.length ? str.charCodeAt(i + 2) : 0;
            var enc1 = byte1 >> 2;
            var enc2 = ((byte1 & 3) << 4) | (byte2 >> 4);
            var enc3 = ((byte2 & 15) << 2) | (byte3 >> 6);
            var enc4 = byte3 & 63;
            if (i + 1 >= str.length) { enc3 = enc4 = 64; }
            else if (i + 2 >= str.length) { enc4 = 64; }
            output += _b64Chars.charAt(enc1) + _b64Chars.charAt(enc2) + _b64Chars.charAt(enc3) + _b64Chars.charAt(enc4);
          }
          return output;
        };
        globalThis.atob = function(str) {
          var output = '';
          for (var i = 0; i < str.length; i += 4) {
            var enc1 = _b64Chars.indexOf(str.charAt(i));
            var enc2 = _b64Chars.indexOf(str.charAt(i + 1));
            var enc3 = _b64Chars.indexOf(str.charAt(i + 2));
            var enc4 = _b64Chars.indexOf(str.charAt(i + 3));
            var chr1 = (enc1 << 2) | (enc2 >> 4);
            var chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
            var chr3 = ((enc3 & 3) << 6) | enc4;
            output += String.fromCharCode(chr1);
            if (enc3 !== 64) output += String.fromCharCode(chr2);
            if (enc4 !== 64) output += String.fromCharCode(chr3);
          }
          return output;
        };
      }
    ''';

    evaluate(nodePolyfills);
  }

  // ===== 纯 JS AES 引擎（QuickJS 同步可用，不依赖 Dart 桥接）=====

  void _injectAesEngine() {
    // 分步注入 AES 引擎，避免单次 evaluate 代码过大导致失败

    // Step 1: S-Box 和基础函数
    const aesStep1 = '''
      var _AES_SBOX = [0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16];
      var _AES_INV_SBOX = [0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d];
      var _AES_RCON = [0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36];
      function _aesXtime(a) { return (a & 0x80) ? ((a << 1) ^ 0x1b) : (a << 1); }
      function _aesMul(a, b) { var r = 0; for (var i = 0; i < 8; i++) { if (b & 1) r ^= a; a = _aesXtime(a); b >>= 1; } return r & 0xff; }
      function _aesSubBytes(s) { for (var i = 0; i < 16; i++) s[i] = _AES_SBOX[s[i]]; }
      function _aesInvSubBytes(s) { for (var i = 0; i < 16; i++) s[i] = _AES_INV_SBOX[s[i]]; }
      function _aesShiftRows(s) { var t=s[1];s[1]=s[5];s[5]=s[9];s[9]=s[13];s[13]=t;t=s[2];s[2]=s[10];s[10]=t;t=s[6];s[6]=s[14];s[14]=t;t=s[15];s[15]=s[11];s[11]=s[7];s[7]=s[3];s[3]=t; }
      function _aesInvShiftRows(s) { var t=s[13];s[13]=s[9];s[9]=s[5];s[5]=s[1];s[1]=t;t=s[2];s[2]=s[10];s[10]=t;t=s[6];s[6]=s[14];s[14]=t;t=s[3];s[3]=s[7];s[7]=s[11];s[11]=s[15];s[15]=t; }
      function _aesMixColumns(s) { for (var i=0;i<4;i++) { var a=s[i*4],b=s[i*4+1],c=s[i*4+2],d=s[i*4+3]; s[i*4]=_aesMul(2,a)^_aesMul(3,b)^c^d; s[i*4+1]=a^_aesMul(2,b)^_aesMul(3,c)^d; s[i*4+2]=a^b^_aesMul(2,c)^_aesMul(3,d); s[i*4+3]=_aesMul(3,a)^b^c^_aesMul(2,d); } }
      function _aesInvMixColumns(s) { for (var i=0;i<4;i++) { var a=s[i*4],b=s[i*4+1],c=s[i*4+2],d=s[i*4+3]; s[i*4]=_aesMul(0x0e,a)^_aesMul(0x0b,b)^_aesMul(0x0d,c)^_aesMul(0x09,d); s[i*4+1]=_aesMul(0x09,a)^_aesMul(0x0e,b)^_aesMul(0x0b,c)^_aesMul(0x0d,d); s[i*4+2]=_aesMul(0x0d,a)^_aesMul(0x09,b)^_aesMul(0x0e,c)^_aesMul(0x0b,d); s[i*4+3]=_aesMul(0x0b,a)^_aesMul(0x0d,b)^_aesMul(0x09,c)^_aesMul(0x0e,d); } }
      function _aesAddRoundKey(s, rk) { for (var i = 0; i < 16; i++) s[i] ^= rk[i]; }
    ''';

    // Step 2: Key expansion + encrypt/decrypt blocks
    const aesStep2 = '''
      function _aesKeyExpansion(key) {
        var nk = key.length / 4, nr = nk + 6;
        var w = new Array(4 * (nr + 1));
        for (var i = 0; i < nk; i++) { w[i*4]=key[i*4]; w[i*4+1]=key[i*4+1]; w[i*4+2]=key[i*4+2]; w[i*4+3]=key[i*4+3]; }
        for (var i = nk; i < 4*(nr+1); i++) {
          var t = [w[(i-1)*4], w[(i-1)*4+1], w[(i-1)*4+2], w[(i-1)*4+3]];
          if (i % nk === 0) { var tmp=t[0]; t[0]=_AES_SBOX[t[1]]^_AES_RCON[i/nk]; t[1]=_AES_SBOX[t[2]]; t[2]=_AES_SBOX[t[3]]; t[3]=_AES_SBOX[tmp]; }
          else if (nk > 6 && i % nk === 4) { t[0]=_AES_SBOX[t[0]]; t[1]=_AES_SBOX[t[1]]; t[2]=_AES_SBOX[t[2]]; t[3]=_AES_SBOX[t[3]]; }
          w[i*4]=w[(i-nk)*4]^t[0]; w[i*4+1]=w[(i-nk)*4+1]^t[1]; w[i*4+2]=w[(i-nk)*4+2]^t[2]; w[i*4+3]=w[(i-nk)*4+3]^t[3];
        }
        return w;
      }
      function _aesEncryptBlock(block, w, nr) {
        var s = block.slice(); _aesAddRoundKey(s, w.slice(0, 16));
        for (var r = 1; r < nr; r++) { _aesSubBytes(s); _aesShiftRows(s); _aesMixColumns(s); _aesAddRoundKey(s, w.slice(r*16, r*16+16)); }
        _aesSubBytes(s); _aesShiftRows(s); _aesAddRoundKey(s, w.slice(nr*16, nr*16+16));
        return s;
      }
      function _aesDecryptBlock(block, w, nr) {
        var s = block.slice(); _aesAddRoundKey(s, w.slice(nr*16, nr*16+16));
        for (var r = nr-1; r > 0; r--) { _aesInvShiftRows(s); _aesInvSubBytes(s); _aesAddRoundKey(s, w.slice(r*16, r*16+16)); _aesInvMixColumns(s); }
        _aesInvShiftRows(s); _aesInvSubBytes(s); _aesAddRoundKey(s, w.slice(0, 16));
        return s;
      }
      function _aesPkcs7Pad(data) { var pad = 16 - (data.length % 16); var r = data.slice(); for (var i = 0; i < pad; i++) r.push(pad); return r; }
      function _aesPkcs7Unpad(data) { if (data.length === 0) return data; var pad = data[data.length - 1]; if (pad < 1 || pad > 16) return data; for (var i = data.length - pad; i < data.length; i++) { if (data[i] !== pad) return data; } return data.slice(0, data.length - pad); }
    ''';

    // Step 3: UTF-8/Base64 conversion + _AES public API
    const aesStep3 = '''
      function _aesUtf8ToBytes(str) {
        var bytes = [];
        for (var i = 0; i < str.length; i++) {
          var c = str.charCodeAt(i);
          if (c < 0x80) bytes.push(c);
          else if (c < 0x800) { bytes.push(0xc0|(c>>6)); bytes.push(0x80|(c&0x3f)); }
          else if (c >= 0xd800 && c <= 0xdbff) { var hi=c,lo=str.charCodeAt(++i); var cp=((hi-0xd800)<<10)+(lo-0xdc00)+0x10000; bytes.push(0xf0|(cp>>18)); bytes.push(0x80|((cp>>12)&0x3f)); bytes.push(0x80|((cp>>6)&0x3f)); bytes.push(0x80|(cp&0x3f)); }
          else { bytes.push(0xe0|(c>>12)); bytes.push(0x80|((c>>6)&0x3f)); bytes.push(0x80|(c&0x3f)); }
        }
        return bytes;
      }
      function _aesBytesToUtf8(bytes) {
        var str = '';
        for (var i = 0; i < bytes.length; i++) {
          var c = bytes[i];
          if (c < 0x80) str += String.fromCharCode(c);
          else if (c >= 0xf0) { str += String.fromCharCode(((c&0x07)<<18)|((bytes[++i]&0x3f)<<12)|((bytes[++i]&0x3f)<<6)|(bytes[++i]&0x3f)); }
          else if (c >= 0xe0) { str += String.fromCharCode(((c&0x0f)<<12)|((bytes[++i]&0x3f)<<6)|(bytes[++i]&0x3f)); }
          else { str += String.fromCharCode(((c&0x1f)<<6)|(bytes[++i]&0x3f)); }
        }
        return str;
      }
      var _AES_B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      function _aesBytesToBase64(bytes) {
        var r = '';
        for (var i = 0; i < bytes.length; i += 3) {
          var b1=bytes[i], b2=i+1<bytes.length?bytes[i+1]:0, b3=i+2<bytes.length?bytes[i+2]:0;
          r += _AES_B64[b1>>2] + _AES_B64[((b1&3)<<4)|(b2>>4)] + (i+1<bytes.length?_AES_B64[((b2&15)<<2)|(b3>>6)]:'=') + (i+2<bytes.length?_AES_B64[b3&63]:'=');
        }
        return r;
      }
      function _aesBase64ToBytes(b64) {
        b64 = b64.replace(/[^A-Za-z0-9+/]/g, '');
        var bytes = [];
        for (var i = 0; i < b64.length; i += 4) {
          var b1=_AES_B64.indexOf(b64[i]), b2=_AES_B64.indexOf(b64[i+1]), b3=b64[i+2]==='='?0:_AES_B64.indexOf(b64[i+2]), b4=b64[i+3]==='='?0:_AES_B64.indexOf(b64[i+3]);
          bytes.push((b1<<2)|(b2>>4)); if (b64[i+2]!=='=') bytes.push(((b2&15)<<4)|(b3>>2)); if (b64[i+3]!=='=') bytes.push(((b3&3)<<6)|b4);
        }
        return bytes;
      }
      function _aesParseKey(val) {
        if (!val) return [];
        if (typeof val === 'object' && val.words && Array.isArray(val.words)) {
          var bytes = [];
          for (var i = 0; i < val.words.length; i++) { bytes.push((val.words[i]>>24)&0xff, (val.words[i]>>16)&0xff, (val.words[i]>>8)&0xff, val.words[i]&0xff); }
          return val.sigBytes !== undefined ? bytes.slice(0, val.sigBytes) : bytes;
        }
        if (typeof val === 'string') return _aesUtf8ToBytes(val);
        if (Array.isArray(val)) return val;
        if (typeof val === 'number') return [val];
        return [];
      }
    ''';

    // Step 4: _AES public API
    const aesStep4 = '''
      var _AES = {
        encrypt: function(data, key, iv, mode) {
          mode = mode || 'CBC';
          var kb = _aesParseKey(key), ivb = iv ? _aesParseKey(iv) : [];
          var db = (typeof data === 'string') ? _aesUtf8ToBytes(data) : data;
          var nr = kb.length/4 + 6, w = _aesKeyExpansion(kb), padded = _aesPkcs7Pad(db), encrypted = [];
          if (mode === 'ECB') { for (var i=0;i<padded.length;i+=16) { encrypted=encrypted.concat(_aesEncryptBlock(padded.slice(i,i+16),w,nr)); } }
          else { var prev=ivb.length>=16?ivb.slice(0,16):new Array(16).fill(0); for (var i=0;i<padded.length;i+=16) { var block=padded.slice(i,i+16); for (var j=0;j<16;j++) block[j]^=prev[j]; var enc=_aesEncryptBlock(block,w,nr); encrypted=encrypted.concat(enc); prev=enc; } }
          return _aesBytesToBase64(encrypted);
        },
        decrypt: function(data, key, iv, mode) {
          mode = mode || 'CBC';
          var kb = _aesParseKey(key), ivb = iv ? _aesParseKey(iv) : [];
          var db = (typeof data === 'string') ? _aesBase64ToBytes(data) : data;
          var nr = kb.length/4 + 6, w = _aesKeyExpansion(kb), decrypted = [];
          if (mode === 'ECB') { for (var i=0;i<db.length;i+=16) { decrypted=decrypted.concat(_aesDecryptBlock(db.slice(i,i+16),w,nr)); } }
          else { var prev=ivb.length>=16?ivb.slice(0,16):new Array(16).fill(0); for (var i=0;i<db.length;i+=16) { var block=db.slice(i,i+16); var dec=_aesDecryptBlock(block,w,nr); for (var j=0;j<16;j++) dec[j]^=prev[j]; decrypted=decrypted.concat(dec); prev=block; } }
          return _aesBytesToUtf8(_aesPkcs7Unpad(decrypted));
        },
        utf8Parse: function(str) {
          var bytes = _aesUtf8ToBytes(str), words = [];
          for (var i = 0; i < bytes.length; i += 4) { words.push(((bytes[i]||0)<<24)|((bytes[i+1]||0)<<16)|((bytes[i+2]||0)<<8)|(bytes[i+3]||0)); }
          return { words: words, sigBytes: bytes.length };
        },
        base64Parse: function(str) {
          var bytes = _aesBase64ToBytes(str), words = [];
          for (var i = 0; i < bytes.length; i += 4) { words.push(((bytes[i]||0)<<24)|((bytes[i+1]||0)<<16)|((bytes[i+2]||0)<<8)|(bytes[i+3]||0)); }
          return { words: words, sigBytes: bytes.length };
        },
      };
    ''';

    // 分步注入，每步独立 try-catch
    try {
      evaluate(aesStep1);
      evaluate(aesStep2);
      evaluate(aesStep3);
      evaluate(aesStep4);
      final aesCheck = evaluate('typeof _AES !== "undefined"');
      if (aesCheck == 'true') {
        debugPrint('JsEngine: _AES 引擎注入成功');
      } else {
        debugPrint('JsEngine: _AES 引擎注入后验证失败');
        _injectAesFallback();
      }
    } catch (e) {
      debugPrint('JsEngine: _AES 引擎注入失败: $e，使用 fallback');
      _injectAesFallback();
    }
  }

  /// AES 引擎注入失败时的简化 fallback
  void _injectAesFallback() {
    evaluate('var _AES = { encrypt: function(d,k,iv,m) { return ""; }, decrypt: function(d,k,iv,m) { return ""; }, utf8Parse: function(s) { return s; }, base64Parse: function(s) { return s; } };');
  }

  /// 注入纯 JS MD5 引擎
  void _injectMd5Engine() {
    const md5Code = '''
      var _MD5 = (function() {
        function safeAdd(x, y) { var l = (x & 0xFFFF) + (y & 0xFFFF), m = (x >> 16) + (y >> 16) + (l >> 16); return (m << 16) | (l & 0xFFFF); }
        function bitRotateLeft(n, c) { return (n << c) | (n >>> (32 - c)); }
        function md5cmn(q, a, b, x, s, t) { return safeAdd(bitRotateLeft(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b); }
        function md5ff(a, b, c, d, x, s, t) { return md5cmn((b & c) | ((~b) & d), a, b, x, s, t); }
        function md5gg(a, b, c, d, x, s, t) { return md5cmn((b & d) | (c & (~d)), a, b, x, s, t); }
        function md5hh(a, b, c, d, x, s, t) { return md5cmn(b ^ c ^ d, a, b, x, s, t); }
        function md5ii(a, b, c, d, x, s, t) { return md5cmn(c ^ (b | (~d)), a, b, x, s, t); }
        function binlMD5(x, len) {
          x[len >> 5] |= 0x80 << (len % 32);
          x[(((len + 64) >>> 9) << 4) + 14] = len;
          var a = 1732584193, b = -271733879, c = -1732584194, d = 271733878;
          for (var i = 0; i < x.length; i += 16) {
            var oa = a, ob = b, oc = c, od = d;
            a=md5ff(a,b,c,d,x[i],7,-680876936); d=md5ff(d,a,b,c,x[i+1],12,-389564586); c=md5ff(c,d,a,b,x[i+2],17,606105819); b=md5ff(b,c,d,a,x[i+3],22,-1044525330);
            a=md5ff(a,b,c,d,x[i+4],7,-176418897); d=md5ff(d,a,b,c,x[i+5],12,1200080426); c=md5ff(c,d,a,b,x[i+6],17,-1473231341); b=md5ff(b,c,d,a,x[i+7],22,-45705983);
            a=md5ff(a,b,c,d,x[i+8],7,1770035416); d=md5ff(d,a,b,c,x[i+9],12,-1958414417); c=md5ff(c,d,a,b,x[i+10],17,-42063); b=md5ff(b,c,d,a,x[i+11],22,-1990404162);
            a=md5ff(a,b,c,d,x[i+12],7,1804603682); d=md5ff(d,a,b,c,x[i+13],12,-40341101); c=md5ff(c,d,a,b,x[i+14],17,-1502002290); b=md5ff(b,c,d,a,x[i+15],22,1236535329);
            a=md5gg(a,b,c,d,x[i+1],5,-165796510); d=md5gg(d,a,b,c,x[i+6],9,-1069501632); c=md5gg(c,d,a,b,x[i+11],14,643717713); b=md5gg(b,c,d,a,x[i],20,-373897302);
            a=md5gg(a,b,c,d,x[i+5],5,-701558691); d=md5gg(d,a,b,c,x[i+10],9,38016083); c=md5gg(c,d,a,b,x[i+15],14,-660478335); b=md5gg(b,c,d,a,x[i+4],20,-405537848);
            a=md5gg(a,b,c,d,x[i+9],5,568446438); d=md5gg(d,a,b,c,x[i+14],9,-1019803690); c=md5gg(c,d,a,b,x[i+3],14,-187363961); b=md5gg(b,c,d,a,x[i+8],20,1163531501);
            a=md5gg(a,b,c,d,x[i+13],5,-1444681467); d=md5gg(d,a,b,c,x[i+2],9,-51403784); c=md5gg(c,d,a,b,x[i+7],14,1735328473); b=md5gg(b,c,d,a,x[i+12],20,-1926607734);
            a=md5hh(a,b,c,d,x[i+5],4,-378558); d=md5hh(d,a,b,c,x[i+8],11,-2022574463); c=md5hh(c,d,a,b,x[i+11],16,1839030562); b=md5hh(b,c,d,a,x[i+14],23,-35309556);
            a=md5hh(a,b,c,d,x[i+1],4,-1530992060); d=md5hh(d,a,b,c,x[i+4],11,1272893353); c=md5hh(c,d,a,b,x[i+7],16,-155497632); b=md5hh(b,c,d,a,x[i+10],23,-1094730640);
            a=md5hh(a,b,c,d,x[i+13],4,681279174); d=md5hh(d,a,b,c,x[i],11,-358537222); c=md5hh(c,d,a,b,x[i+3],16,-722521979); b=md5hh(b,c,d,a,x[i+6],23,76029189);
            a=md5hh(a,b,c,d,x[i+9],4,-640364487); d=md5hh(d,a,b,c,x[i+12],11,-421815835); c=md5hh(c,d,a,b,x[i+15],16,530742520); b=md5hh(b,c,d,a,x[i+2],23,-995338651);
            a=md5ii(a,b,c,d,x[i],6,-198630844); d=md5ii(d,a,b,c,x[i+7],10,1126891415); c=md5ii(c,d,a,b,x[i+14],15,-1416354905); b=md5ii(b,c,d,a,x[i+5],21,-57434055);
            a=md5ii(a,b,c,d,x[i+12],6,1700485571); d=md5ii(d,a,b,c,x[i+3],10,-1894986606); c=md5ii(c,d,a,b,x[i+10],15,-1051523); b=md5ii(b,c,d,a,x[i+1],21,-2054922799);
            a=md5ii(a,b,c,d,x[i+8],6,1873313359); d=md5ii(d,a,b,c,x[i+15],10,-30611744); c=md5ii(c,d,a,b,x[i+6],15,-1560198380); b=md5ii(b,c,d,a,x[i+13],21,1309151649);
            a=md5ii(a,b,c,d,x[i+4],6,-145523070); d=md5ii(d,a,b,c,x[i+11],10,-1120210379); c=md5ii(c,d,a,b,x[i+2],15,718787259); b=md5ii(b,c,d,a,x[i+9],21,-343485551);
            a=safeAdd(a,oa); b=safeAdd(b,ob); c=safeAdd(c,oc); d=safeAdd(d,od);
          }
          return [a, b, c, d];
        }
        function binl2rstr(input) {
          var output = '';
          for (var i = 0; i < input.length * 32; i += 8) output += String.fromCharCode((input[i >> 5] >>> (i % 32)) & 0xFF);
          return output;
        }
        function rstr2binl(input) {
          var output = [];
          for (var i = 0; i < input.length * 8; i += 32) output[i >> 5] = 0;
          for (var i = 0; i < input.length * 8; i += 8) output[i >> 5] |= (input.charCodeAt(i / 8) & 0xFF) << (i % 32);
          return output;
        }
        function rstrMD5(s) { return binl2rstr(binlMD5(rstr2binl(s), s.length * 8)); }
        function rstr2hex(input) {
          var hexTab = '0123456789abcdef', output = '';
          for (var i = 0; i < input.length; i++) {
            var x = input.charCodeAt(i);
            output += hexTab.charAt((x >>> 4) & 0x0F) + hexTab.charAt(x & 0x0F);
          }
          return output;
        }
        function str2rstrUTF8(input) {
          return unescape(encodeURIComponent(input));
        }
        return function(str) { return rstr2hex(rstrMD5(str2rstrUTF8(str))); };
      })();
    ''';
    try {
      evaluate(md5Code);
      final check = evaluate('typeof _MD5 !== "undefined"');
      if (check == 'true') {
        debugPrint('JsEngine: _MD5 引擎注入成功');
      } else {
        debugPrint('JsEngine: _MD5 引擎注入后验证失败');
      }
    } catch (e) {
      debugPrint('JsEngine: _MD5 引擎注入失败: $e');
    }
  }

  // ===== Java 桥接对象（QuickJS 侧）=====

  void _injectJavaBridge() {
    // 拆分注入：先注入基础变量，再注入 AES 引擎，再注入 java 对象，最后注入 CryptoJS
    // 每步独立 try-catch，避免一步失败导致全部丢失

    // 1. 注入 _javaCache 基础变量
    try {
      evaluate('if (typeof _javaCache === "undefined") var _javaCache = {};');
    } catch (e) {
      debugPrint('JsEngine: _javaCache 注入失败: $e');
      try { evaluate('var _javaCache = {};'); } catch (_) {}
    }

    // 2. 注入纯 JS AES 引擎（不依赖 Dart 桥接，QuickJS 同步可用）
    _injectAesEngine();

    // 2.5 注入纯 JS MD5 引擎
    _injectMd5Engine();
    // 注意：不能使用 const，因为字符串中包含 $ 符号（JS 正则替换引用 $&）
    final helperCode = '''
      // ===== Legado Java 桥接对象（QuickJS 侧）=====
      // 借鉴 legado 的 JsExtensions 接口，通过 Dart 侧 NativeChannel 桥接
      // 核心策略：同步模式从 _javaCache 取缓存值，异步模式由 Dart 端预缓存
      // _javaCache 已在前面注入，这里不再重复声明

      // ===== 内置 HTML 解析器（精简版：优先从 Dart 预缓存取结果，仅做最小正则兜底）=====
      // Dart 端通过 _nativeJsoupParse + _preCacheBridgeCalls 已将解析结果写入 _javaCache
      // JS 侧只需查缓存，未命中时用简单正则兜底
      var _JsoupLite = {
        _hashStr: function(s) {
          var h = 0;
          for (var i = 0; i < s.length; i++) {
            h = ((h << 5) - h + s.charCodeAt(i)) | 0;
          }
          return h;
        },
        _cacheKey: function(prefix, selector, html) {
          return prefix + ':' + selector + ':' + _JsoupLite._hashStr(html || '');
        },
        selectFirst: function(html, selector) {
          var key = _JsoupLite._cacheKey('jsoup_sf', selector, html);
          if (_javaCache[key] !== undefined) return _javaCache[key];
          return _JsoupLite._fallback(html, selector, true);
        },
        selectAll: function(html, selector) {
          var key = _JsoupLite._cacheKey('jsoup_sa', selector, html);
          if (_javaCache[key] !== undefined) return _javaCache[key];
          return _JsoupLite._fallback(html, selector, false);
        },
        getAttr: function(html, selector, attr) {
          var key = _JsoupLite._cacheKey('jsoup_ga', selector + ':' + attr, html);
          if (_javaCache[key] !== undefined) return _javaCache[key];
          var el = _JsoupLite.selectFirst(html, selector);
          if (!el) return '';
          var m = (typeof el === 'string' ? el : '').match(new RegExp(attr + '=["\\']([^"\\']*)["\\']', 'i'));
          return m ? m[1] : '';
        },
        _fallback: function(html, selector, firstOnly) {
          if (!html || !selector) return firstOnly ? '' : [];
          var sel = selector.trim();
          // Simple .class
          if (sel.startsWith('.') && sel.indexOf(' ', 1) < 0 && sel.indexOf('>') < 0) {
            var cls = sel.substring(1);
            var re = new RegExp('<([a-zA-Z][a-zA-Z0-9]*)[^>]*class="[^"]*\\\\b' + cls.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\\$&') + '\\\\b[^"]*"[^>]*>([\\\\s\\\\S]*?)</\\\\1>', 'gi');
            if (firstOnly) { var m = re.exec(html); return m ? m[0] : ''; }
            var results = []; var m2; while ((m2 = re.exec(html)) !== null) results.push(m2[0]); return results;
          }
          // Simple tag
          if (/^[a-zA-Z][a-zA-Z0-9]*\$/.test(sel)) {
            var tagRe = new RegExp('<' + sel + '[^>]*>([\\\\s\\\\S]*?)</' + sel + '>', 'gi');
            if (firstOnly) { var m = tagRe.exec(html); return m ? m[0] : ''; }
            var results2 = []; var m3; while ((m3 = tagRe.exec(html)) !== null) results2.push(m3[0]); return results2;
          }
          // Simple #id
          if (sel.startsWith('#')) {
            var id = sel.substring(1);
            var idRe = new RegExp('<([a-zA-Z][a-zA-Z0-9]*)[^>]*id="' + id.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\\$&') + '"[^>]*>([\\\\s\\\\S]*?)</\\\\1>', 'i');
            var m4 = idRe.exec(html);
            if (firstOnly) return m4 ? m4[0] : '';
            return m4 ? [m4[0]] : [];
          }
          return firstOnly ? '' : [];
        }
      };

      var java = {
        // ===== HTTP 请求方法（核心，借鉴 legado JsExtensions.ajax）=====
        get: function(url, headers) {
          // 自动拼接 baseUrl：如果 url 是相对路径，拼接 baseUrl
          var fullUrl = url;
          if (url && !url.startsWith('http') && typeof baseUrl !== 'undefined' && baseUrl) {
            fullUrl = baseUrl.replace(/\/+\$/, '') + '/' + url.replace(/^\/+/, '');
          }
          var cacheKey = 'http_get:' + fullUrl;
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          // fallback: 尝试原始 url
          if (fullUrl !== url) {
            var origKey = 'http_get:' + url;
            if (_javaCache[origKey] !== undefined) return _javaCache[origKey];
          }
          return '';
        },
        post: function(url, body, headers) {
          var fullUrl = url;
          if (url && !url.startsWith('http') && typeof baseUrl !== 'undefined' && baseUrl) {
            fullUrl = baseUrl.replace(/\/+\$/, '') + '/' + url.replace(/^\/+/, '');
          }
          var cacheKey = 'http_post:' + fullUrl;
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          if (fullUrl !== url) {
            var origKey = 'http_post:' + url;
            if (_javaCache[origKey] !== undefined) return _javaCache[origKey];
          }
          return '';
        },
        ajax: function(url, headers) {
          return java.get(url, headers);
        },
        ajaxAll: function(urls) {
          if (!urls || !urls.length) return [];
          var results = [];
          for (var i = 0; i < urls.length; i++) {
            results.push(java.ajax(urls[i]));
          }
          return results;
        },

        // ===== 变量存取（借鉴 legado 的 CacheManager）=====
        put: function(key, value) {
          _javaCache[key] = typeof value === 'object' ? JSON.stringify(value) : String(value);
        },
        getStr: function(key, defaultValue) {
          return _javaCache[key] || (defaultValue || '');
        },
        getString: function(str, ruleStr) {
          // 借鉴 legado：单参数模式 java.getString(ruleStr)
          // 此时 str 是规则字符串，内容来自 result 变量
          // 双参数模式 java.getString(content, ruleStr)
          // 此时 str 是内容，ruleStr 是规则
          var content, rule;
          if (ruleStr === undefined || ruleStr === null) {
            // 单参数模式：str 是规则，内容来自 result
            rule = str;
            content = (typeof result !== 'undefined') ? result : '';
          } else {
            // 双参数模式
            content = str;
            rule = ruleStr;
          }

          if (!rule) return content || '';

          // @@ 前缀：去掉 @@ 后作为默认 CSS 规则
          if (rule.indexOf('@@') === 0) {
            rule = rule.substring(2);
          }

          // 借鉴 legado 的 JsExtensions.getString：支持 CSS/正则/JSON 规则
          if (rule.startsWith('@css:') || rule.startsWith('@CSS:')) {
            var cssSel = rule.substring(5);
            // 尝试从缓存获取 text
            var textKey = 'jsoup_text:' + cssSel + ':' + _JsoupLite._hashStr(content || '');
            if (_javaCache[textKey] !== undefined) return _javaCache[textKey];
            // 尝试从缓存获取 href
            var hrefKey = 'jsoup_href:' + cssSel + ':' + _JsoupLite._hashStr(content || '');
            if (_javaCache[hrefKey] !== undefined) return _javaCache[hrefKey];
            return _JsoupLite.selectFirst(content, cssSel);
          }
          if (rule.startsWith('@json:') || rule.startsWith('@JSON:')) {
            try {
              var data = (typeof content === 'string') ? JSON.parse(content) : content;
              var path = rule.substring(6).trim().replace(/^\$\./, '');
              var parts = path.split('.');
              var r = data;
              for (var i = 0; i < parts.length; i++) {
                if (r == null) return '';
                r = r[parts[i]];
              }
              return r != null ? String(r) : '';
            } catch(e) { return ''; }
          }
          // 正则规则
          if (rule.startsWith('@regex:') || rule.startsWith('@Regex:')) {
            try {
              var pattern = rule.substring(7);
              var m = String(content).match(new RegExp(pattern));
              return m ? (m[1] || m[0]) : '';
            } catch(e) { return ''; }
          }
          // 默认：CSS 选择器规则（legado 的 Default 模式）
          // 支持 #id、.class、tag、tag@attr、tag@sub@attr 等格式
          try {
            // 尝试从缓存获取 text
            var textKey2 = 'jsoup_text:' + rule + ':' + _JsoupLite._hashStr(content || '');
            if (_javaCache[textKey2] !== undefined) return _javaCache[textKey2];
            // 尝试从缓存获取 href
            var hrefKey2 = 'jsoup_href:' + rule + ':' + _JsoupLite._hashStr(content || '');
            if (_javaCache[hrefKey2] !== undefined) return _javaCache[hrefKey2];
            return _JsoupLite.selectFirst(content, rule);
          } catch(e) {}

          return String(content);
        },
        getStrResponse: function(url, ruleStr) {
          var html = java.ajax(url);
          if (ruleStr) return java.getString(html, ruleStr);
          return html;
        },
        getJson: function(str) {
          try { return JSON.parse(str); } catch(e) { return {}; }
        },
        putJson: function(key, value) {
          _javaCache[key] = JSON.stringify(value);
        },

        // ===== 加密/解密（优先使用纯 JS _AES 引擎，fallback 到缓存）=====
        aesEncode: function(data, key, iv) {
          var cacheKey = 'aes_enc:' + data + ':' + key + ':' + (iv || '');
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          try {
            var mode = iv ? 'CBC' : 'ECB';
            var result = _AES.encrypt(data, key, iv, mode);
            _javaCache[cacheKey] = result;
            return result;
          } catch(e) { return ''; }
        },
        aesDecode: function(data, key, iv) {
          var cacheKey = 'aes_dec:' + data + ':' + key + ':' + (iv || '');
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          try {
            var mode = iv ? 'CBC' : 'ECB';
            var result = _AES.decrypt(data, key, iv, mode);
            _javaCache[cacheKey] = result;
            return result;
          } catch(e) { return ''; }
        },
        md5Encode: function(str) {
          // 优先使用纯 JS _MD5 引擎，fallback 到缓存
          if (typeof _MD5 !== 'undefined') return _MD5(str);
          var cacheKey = 'md5:' + str;
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          return '';
        },
        sha1Encode: function(str) {
          var cacheKey = 'sha1:' + str;
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          return '';
        },
        sha256Encode: function(str) {
          var cacheKey = 'sha256:' + str;
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          return '';
        },
        hmacSHA256: function(data, key) {
          var cacheKey = 'hmac_sha256:' + data + ':' + key;
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          return '';
        },
        base64Encode: function(str) {
          try {
            if (typeof btoa === 'function') return btoa(unescape(encodeURIComponent(str)));
          } catch(e) {}
          return '';
        },
        base64Decode: function(str) {
          try {
            if (typeof atob === 'function') return decodeURIComponent(escape(atob(str)));
          } catch(e) {}
          return '';
        },

        // ===== HTML 解析（使用内置 _JsoupLite，不再递归自调用）=====
        jsoup: {
          parse: function(html) {
            return {
              html: html,
              select: function(sel) { return _JsoupLite.selectAll(html, sel); },
              selectFirst: function(sel) { return _JsoupLite.selectFirst(html, sel); },
              text: function() {
                // 简易去标签提取文本
                return (html || '').replace(/<[^>]+>/g, '').trim();
              },
            };
          },
          select: function(html, selector) { return _JsoupLite.selectAll(html, selector); },
          selectFirst: function(html, selector) { return _JsoupLite.selectFirst(html, selector); },
          getAttr: function(html, selector, attr) { return _JsoupLite.getAttr(html, selector, attr); },
          clean: function(html) {
            if (!html) return '';
            return html.replace(/<script[^>]*>[\\\\s\\\\S]*?<\\\\/script>/gi, '')
                       .replace(/<style[^>]*>[\\\\s\\\\S]*?<\\\\/style>/gi, '')
                       .replace(/<[^>]+>/g, '')
                       .replace(/&nbsp;/g, ' ')
                       .replace(/&amp;/g, '&')
                       .replace(/&lt;/g, '<')
                       .replace(/&gt;/g, '>')
                       .replace(/&quot;/g, '"')
                       .trim();
          },
        },

        // ===== 正则操作（QuickJS 原生支持）=====
        regex: {
          match: function(str, pattern) {
            try { var m = str.match(new RegExp(pattern)); return m ? m[0] : ''; } catch(e) { return ''; }
          },
          matchAll: function(str, pattern) {
            try { var results = []; var r = new RegExp(pattern, 'g'); var m; while(m = r.exec(str)) { results.push(m[0]); } return results; } catch(e) { return []; }
          },
          replace: function(str, pattern, replacement) {
            try { return str.replace(new RegExp(pattern, 'g'), replacement); } catch(e) { return str; }
          },
          test: function(str, pattern) {
            try { return new RegExp(pattern).test(str); } catch(e) { return false; }
          },
        },

        // ===== 时间/编码工具 =====
        timeFormat: function(timestamp, format) {
          var d = new Date(timestamp);
          if (!format) return d.toLocaleString();
          // 支持 yyyy-MM-dd HH:mm:ss 格式
          return format
            .replace(/yyyy/g, d.getFullYear())
            .replace(/MM/g, (d.getMonth() + 1).toString().padStart(2, '0'))
            .replace(/dd/g, d.getDate().toString().padStart(2, '0'))
            .replace(/HH/g, d.getHours().toString().padStart(2, '0'))
            .replace(/mm/g, d.getMinutes().toString().padStart(2, '0'))
            .replace(/ss/g, d.getSeconds().toString().padStart(2, '0'));
        },
        getTime: function() {
          return Date.now();
        },
        encodeURI: function(str) {
          return encodeURIComponent(str);
        },
        hexEncodeToString: function(str) {
          var hex = '';
          for (var i = 0; i < str.length; i++) {
            hex += str.charCodeAt(i).toString(16).padStart(2, '0');
          }
          return hex;
        },
        hexDecodeToString: function(hex) {
          var str = '';
          for (var i = 0; i < hex.length; i += 2) {
            str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
          }
          return str;
        },

        // ===== WebView（桥接到 NativeChannel，同步模式从缓存取）=====
        webview: {
          eval: function(url, js) {
            var cacheKey = 'webview:' + url + ':' + (js || '').length;
            if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
            return '';
          },
        },

        // legado 兼容：java.webView(htmlOrJs, baseUrl, extra)
        // 在 legado 中，java.webView 用于执行包含 JS 的 HTML 并获取渲染结果
        // QuickJS 同步模式下无法真正渲染 WebView，尝试从缓存获取
        webView: function(htmlOrJs, baseUrl, extra) {
          var cacheKey = 'webview:' + (baseUrl || '') + ':' + (htmlOrJs || '').length;
          if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey];
          // fallback: 如果 htmlOrJs 包含 <script>，尝试直接执行其中的 JS
          try {
            if (typeof htmlOrJs === 'string' && htmlOrJs.indexOf('<script') >= 0) {
              var scripts = htmlOrJs.match(/<script[^>]*>([\\s\\S]*?)<\\/script>/gi);
              if (scripts && scripts.length > 0) {
                var lastResult = '';
                for (var i = 0; i < scripts.length; i++) {
                  var code = scripts[i].replace(/<script[^>]*>/i, '').replace(/<\\/script>/i, '');
                  if (code.trim()) lastResult = String(eval(code));
                }
                return lastResult;
              }
            }
          } catch(e) {}
          return '';
        },

        // ===== 缓存管理 =====
        cache: {
          get: function(key) { return _javaCache[key] || ''; },
          put: function(key, value) { _javaCache[key] = value; },
          delete: function(key) { delete _javaCache[key]; },
        },

        // ===== 日志 =====
        log: function(msg) {
          console.log('[JavaBridge] ' + msg);
        },

        // ===== 元素操作（借鉴 legado JsExtensions）=====
        getElements: function(html, rule) {
          // 借鉴 legado：单参数模式 html 是规则，内容来自 result
          var content, r;
          if (rule === undefined || rule === null) {
            r = html;
            content = (typeof result !== 'undefined') ? result : '';
          } else {
            content = html;
            r = rule;
          }
          if (!r) return [];
          if (r.indexOf('@@') === 0) r = r.substring(2);
          return _JsoupLite.selectAll(content, r);
        },
        getElement: function(html, rule) {
          // 借鉴 legado：单参数模式 html 是规则，内容来自 result
          var content, r;
          if (rule === undefined || rule === null) {
            r = html;
            content = (typeof result !== 'undefined') ? result : '';
          } else {
            content = html;
            r = rule;
          }
          if (!r) return '';
          if (r.indexOf('@@') === 0) r = r.substring(2);
          return _JsoupLite.selectFirst(content, r);
        },
      };

      // ===== 兼容 Legado 的 CryptoJS（桥接到 NativeChannel）=====
      var CryptoJS = {
        AES: {
          encrypt: function(data, key, cfg) {
            var keyStr = typeof key === 'string' ? key : (key.toString ? key.toString() : '');
            var iv = cfg && cfg.iv ? (typeof cfg.iv === 'string' ? cfg.iv : (cfg.iv.toString ? cfg.iv.toString() : '')) : '';
            var mode = cfg && cfg.mode ? 'ECB' : 'CBC';
            var result = java.aesEncode(data, keyStr, iv);
            return { toString: function() { return result; }, ciphertext: { toString: function(enc) { return result; } } };
          },
          decrypt: function(data, key, cfg) {
            var keyStr = typeof key === 'string' ? key : (key.toString ? key.toString() : '');
            var iv = cfg && cfg.iv ? (typeof cfg.iv === 'string' ? cfg.iv : (cfg.iv.toString ? cfg.iv.toString() : '')) : '';
            var result = java.aesDecode(data, keyStr, iv);
            return { toString: function(enc) { return result; } };
          },
        },
        MD5: function(str) { return { toString: function() { return java.md5Encode(str); } }; },
        SHA1: function(str) { return { toString: function() { return java.sha1Encode(str); } }; },
        SHA256: function(str) { return { toString: function() { return java.sha256Encode(str); } }; },
        HmacSHA256: function(data, key) { return { toString: function() { return java.hmacSHA256(data, key); } }; },
        enc: {
          Utf8: { parse: function(s) { return s; }, stringify: function(w) { return w; } },
          Base64: { parse: function(s) { return java.base64Decode(s) || ''; }, stringify: function(w) { return java.base64Encode(w) || ''; } },
          Hex: { parse: function(s) { return java.hexDecodeToString(s); }, stringify: function(w) { return java.hexEncodeToString(w); } },
          Latin1: { parse: function(s) { return s; }, stringify: function(w) { return w; } },
        },
        mode: { ECB: {}, CBC: {} },
        pad: { Pkcs7: {}, ZeroPadding: {}, NoPadding: {}, Iso97971: {} },
        lib: {
          WordArray: {
            create: function(words, sigBytes) {
              return { words: words || [], sigBytes: sigBytes || 0, toString: function() { return (words || []).join(''); } };
            }
          }
        },
        algo: {},
      };
    ''';

    // 3. 注入 HTML 解析辅助函数 + java 对象
    try {
      evaluate(helperCode);
    } catch (e) {
      debugPrint('JsEngine: java 对象注入失败: $e');
    }

    // 4. 验证 java 对象是否注入成功
    final javaCheck = evaluate('typeof java !== "undefined"');
    if (javaCheck != 'true') {
      debugPrint('JsEngine: java 对象注入失败，尝试简化版注入');
      // 简化版：只注入核心方法
      evaluate('''
        var java = {
          get: function(url) { var cacheKey = 'http_get:' + url; if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey]; return ''; },
          post: function(url, body) { var cacheKey = 'http_post:' + url; if (_javaCache[cacheKey] !== undefined) return _javaCache[cacheKey]; return ''; },
          ajax: function(url) { return java.get(url); },
          put: function(key, value) { _javaCache[key] = typeof value === 'object' ? JSON.stringify(value) : String(value); },
          getStr: function(key, def) { return _javaCache[key] || (def || ''); },
          log: function(msg) { console.log('[JavaBridge] ' + msg); },
          aesEncode: function(data, key, iv) { try { return _AES.encrypt(data, key, iv, iv ? 'CBC' : 'ECB'); } catch(e) { return ''; } },
          aesDecode: function(data, key, iv) { try { return _AES.decrypt(data, key, iv, iv ? 'CBC' : 'ECB'); } catch(e) { return ''; } },
          md5Encode: function(str) { var k = 'md5:' + str; if (_javaCache[k] !== undefined) return _javaCache[k]; return ''; },
          base64Encode: function(str) { try { return btoa(unescape(encodeURIComponent(str))); } catch(e) { return ''; } },
          base64Decode: function(str) { try { return decodeURIComponent(escape(atob(str))); } catch(e) { return ''; } },
        };
      ''');
    }

    // 4. 注入 CryptoJS（使用纯 JS _AES 引擎，支持 WordArray 格式）
    final cryptoCode = '''
      var CryptoJS = {
        AES: {
          encrypt: function(data, key, cfg) {
            var iv = cfg && cfg.iv ? cfg.iv : null;
            var mode = (cfg && cfg.mode === CryptoJS.mode.ECB) ? 'ECB' : 'CBC';
            var result = _AES.encrypt(data, key, iv, mode);
            return { toString: function() { return result; }, ciphertext: { toString: function(enc) { return result; } } };
          },
          decrypt: function(data, key, cfg) {
            var iv = cfg && cfg.iv ? cfg.iv : null;
            var mode = (cfg && cfg.mode === CryptoJS.mode.ECB) ? 'ECB' : 'CBC';
            var result = _AES.decrypt(data, key, iv, mode);
            return { toString: function(enc) { return result; } };
          },
        },
        MD5: function(str) { return { toString: function() { return java.md5Encode(str); } }; },
        SHA1: function(str) { return { toString: function() { return java.sha1Encode ? java.sha1Encode(str) : ''; } }; },
        SHA256: function(str) { return { toString: function() { return java.sha256Encode ? java.sha256Encode(str) : ''; } }; },
        HmacSHA256: function(data, key) { return { toString: function() { return java.hmacSHA256 ? java.hmacSHA256(data, key) : ''; } }; },
        enc: {
          Utf8: {
            parse: function(s) { return _AES.utf8Parse(s); },
            stringify: function(w) {
              if (typeof w === 'string') return w;
              if (w && w.words) {
                var bytes = [];
                for (var i = 0; i < w.sigBytes; i++) {
                  var wi = Math.floor(i/4);
                  bytes.push((w.words[wi] >> (24 - (i%4)*8)) & 0xff);
                }
                var s = '';
                for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
                return decodeURIComponent(escape(s));
              }
              return String(w);
            }
          },
          Base64: {
            parse: function(s) { return _AES.base64Parse(s); },
            stringify: function(w) {
              if (typeof w === 'string') return java.base64Encode(w) || '';
              if (w && w.words) {
                var bytes = [];
                for (var i = 0; i < w.sigBytes; i++) {
                  var wi = Math.floor(i/4);
                  bytes.push((w.words[wi] >> (24 - (i%4)*8)) & 0xff);
                }
                return java.base64Encode(String.fromCharCode.apply(null, bytes)) || '';
              }
              return java.base64Encode(String(w)) || '';
            }
          },
          Hex: {
            parse: function(s) {
              var bytes = [];
              for (var i = 0; i < s.length; i += 2) bytes.push(parseInt(s.substr(i, 2), 16));
              var words = [];
              for (var i = 0; i < bytes.length; i += 4) {
                words.push(((bytes[i]||0)<<24)|((bytes[i+1]||0)<<16)|((bytes[i+2]||0)<<8)|(bytes[i+3]||0));
              }
              return { words: words, sigBytes: bytes.length };
            },
            stringify: function(w) {
              if (typeof w === 'string') return w;
              if (w && w.words) {
                var hex = '';
                for (var i = 0; i < w.sigBytes; i++) {
                  var wi = Math.floor(i/4);
                  hex += ('0' + ((w.words[wi] >> (24 - (i%4)*8)) & 0xff).toString(16)).slice(-2);
                }
                return hex;
              }
              return String(w);
            }
          },
          Latin1: { parse: function(s) { return s; }, stringify: function(w) { return typeof w === 'string' ? w : String(w); } },
        },
        mode: { ECB: {}, CBC: {} },
        pad: { Pkcs7: {}, ZeroPadding: {}, NoPadding: {}, Iso97971: {} },
        lib: {
          WordArray: {
            create: function(words, sigBytes) {
              return { words: words || [], sigBytes: sigBytes !== undefined ? sigBytes : (words ? words.length * 4 : 0), toString: function() { return (words || []).join(''); } };
            }
          }
        },
        algo: {},
      };
    ''';
    try {
      evaluate(cryptoCode);
    } catch (e) {
      debugPrint('JsEngine: CryptoJS 注入失败: $e');
    }

    // 5. 最终验证
    final finalCheck = evaluate('typeof java !== "undefined" && typeof CryptoJS !== "undefined" && typeof _javaCache !== "undefined" && typeof _AES !== "undefined"');
    if (finalCheck == 'true') {
      debugPrint('JsEngine: Java 桥接注入成功 (java, CryptoJS, _javaCache, _AES)');
    } else {
      debugPrint('JsEngine: Java 桥接注入部分失败！java=${evaluate('typeof java')}, CryptoJS=${evaluate('typeof CryptoJS')}, _javaCache=${evaluate('typeof _javaCache')}, _AES=${evaluate('typeof _AES')}');
    }
  }

  // ===== TypeScript 编译支持 =====

  Future<String> compileTypeScript(String tsCode) async {
    String js = tsCode;

    js = js.replaceAllMapped(
      RegExp(r'(\w+)\s*:\s*[\w\[\]<>\|&\s]+([,\)])'),
      (m) => '${m[1]}${m[2]}',
    );
    js = js.replaceAllMapped(
      RegExp(r'\)\s*:\s*[\w\[\]<>\|&\s]+\s*([=>{])'),
      (m) => ') ${m[1]}',
    );
    js = js.replaceAllMapped(
      RegExp(r'(const|let|var)\s+(\w+)\s*:\s*[\w\[\]<>\|&\s]+=\s*'),
      (m) => '${m[1]} ${m[2]} = ',
    );
    js = js.replaceAll(RegExp(r'interface\s+\w+\s*\{[^}]*\}', multiLine: true), '');
    js = js.replaceAll(RegExp(r'type\s+\w+\s*=\s*[^;]+;'), '');
    js = js.replaceAllMapped(RegExp(r'\s+as\s+[\w\[\]<>\|&]+'), (m) => '');
    js = js.replaceAllMapped(
      RegExp(r'(\w+)<[^>]+>\('),
      (m) => '${m[1]}(',
    );
    js = js.replaceAllMapped(
      RegExp(r'enum\s+(\w+)\s*\{([^}]+)\}'),
      (m) {
        final name = m[1];
        final body = m[2];
        final entries = body!.split(',').asMap().entries.map((e) {
          final trimmed = e.value.trim();
          if (trimmed.contains('=')) {
            return trimmed;
          }
          return '$trimmed = ${e.key}';
        }).join(', ');
        return 'var $name = { $entries };';
      },
    );
    js = js.replaceAllMapped(
      RegExp(r'(\w+)\?\.(?:(\w+)\()?'),
      (m) => m[2] != null ? '(${m[1]} && ${m[1]}.${m[2]}(' : '(${m[1]} && ${m[1]}.',
    );
    js = js.replaceAllMapped(
      RegExp(r'(\w+)\s*\?\?\s*'),
      (m) => '(${m[1]} != null ? ${m[1]} : ',
    );
    js = js.replaceAll(RegExp(r'\b(public|private|protected|readonly)\s+'), '');
    js = js.replaceAll(RegExp(r'\babstract\s+'), '');
    js = js.replaceAllMapped(RegExp(r'\s+implements\s+[\w,\s]+'), (m) => '');

    return js;
  }

  // ===== 自定义库管理 =====

  Future<bool> installPackage(String name, String code, {String? version}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final pkgDir = Directory('${dir.path}/js_packages/$name');
      if (!await pkgDir.exists()) {
        await pkgDir.create(recursive: true);
      }

      final file = File('${pkgDir.path}/index.js');
      await file.writeAsString(code);

      final info = {
        'name': name,
        'version': version ?? '1.0.0',
        'installedAt': DateTime.now().toIso8601String(),
      };
      final infoFile = File('${pkgDir.path}/package.json');
      await infoFile.writeAsString(jsonEncode(info));

      _installedPackages[name] = code;
      _registerPackage(name, code);

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> installPackageFromUrl(String name, String url) async {
    try {
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> uninstallPackage(String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final pkgDir = Directory('${dir.path}/js_packages/$name');
      if (await pkgDir.exists()) {
        await pkgDir.delete(recursive: true);
      }
      _installedPackages.remove(name);
      _moduleCache.remove(name);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getInstalledPackages() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final pkgDir = Directory('${dir.path}/js_packages');
      if (!await pkgDir.exists()) return [];

      final packages = <Map<String, dynamic>>[];
      await for (final entity in pkgDir.list()) {
        if (entity is Directory) {
          final infoFile = File('${entity.path}/package.json');
          if (await infoFile.exists()) {
            final info = jsonDecode(await infoFile.readAsString());
            packages.add(info as Map<String, dynamic>);
          }
        }
      }
      return packages;
    } catch (e) {
      return [];
    }
  }

  Future<void> _loadInstalledPackages() async {
    final packages = await getInstalledPackages();
    for (final pkg in packages) {
      final name = pkg['name'] as String?;
      if (name == null) continue;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/js_packages/$name/index.js');
      if (await file.exists()) {
        final code = await file.readAsString();
        _installedPackages[name] = code;
        _registerPackage(name, code);
      }
    }
  }

  void _registerPackage(String name, String code) {
    final wrappedCode = '''
      _modules['$name'] = function(module, exports, require) {
        $code
      };
    ''';
    evaluate(wrappedCode);
  }

  // ===== QuickJS 引擎执行 =====

  dynamic evaluate(String script) {
    if (_jsRuntime == null) return null;
    try {
      final result = _jsRuntime!.evaluate(script);
      if (result.isError) {
        debugPrint('JsEngine evaluate error: ${result.stringResult}');
        return null;
      }
      return result.stringResult;
    } catch (e) {
      debugPrint('JsEngine evaluate exception: $e');
      return null;
    }
  }

  Future<dynamic> evaluateAsync(String script) async {
    if (!_initialized || _jsRuntime == null) return null;
    try {
      final result = await _jsRuntime!.evaluateAsync(script);
      if (result.isError) {
        debugPrint('JsEngine evaluateAsync error: ${result.stringResult}');
        return null;
      }
      return result.stringResult;
    } catch (e) {
      debugPrint('JsEngine evaluateAsync exception: $e');
      return null;
    }
  }

  Future<dynamic> evaluateTypeScript(String tsCode) async {
    final jsCode = await compileTypeScript(tsCode);
    return evaluate(jsCode);
  }

  /// 同步执行 JS 代码（用于 AnalyzeRule 规则解析）
  /// 默认走 QuickJS，如果代码含 java. 且无 ES6 特征，自动走 Rhino
  dynamic executeSync(String jsCode, dynamic content, {String? baseUrl, JsEngineType? sourceEngine, Map<String, dynamic>? variables}) {
    // 先提取 JS 代码（去掉 <js></js> 标签或 @js: 前缀）
    final extracted = _extractJsCode(jsCode) ?? jsCode;
    final resolved = resolveEngine(extracted, sourceEngine: sourceEngine);

    if (resolved.engine == JsEngineType.rhino) {
      // Rhino 不支持同步调用（MethodChannel 是异步的），降级到 QuickJS
      debugPrint('JsEngine: Rhino 不支持同步执行，降级到 QuickJS: ${jsCode.substring(0, jsCode.length > 50 ? 50 : jsCode.length)}...');
    }

    return _executeQuickJSSync(resolved.code, content, baseUrl: baseUrl, variables: variables);
  }

  /// QuickJS 同步执行
  dynamic _executeQuickJSSync(String jsCode, dynamic content, {String? baseUrl, Map<String, dynamic>? variables}) {
    if (!_initialized || _jsRuntime == null) {
      debugPrint('JsEngine not initialized, cannot executeSync');
      return null;
    }
    try {
      // content 序列化：List/Map 直接 jsonEncode，String 也 jsonEncode（加引号转义），其他 toString
      String contentStr;
      if (content is List || content is Map) {
        contentStr = jsonEncode(content);
      } else if (content is String) {
        contentStr = jsonEncode(content);
      } else {
        contentStr = jsonEncode(content?.toString() ?? '');
      }

      // 自动补 return：如果 JS 代码不以 return 结尾，自动包裹使其返回最后一个表达式的值
      final wrappedCode = _wrapJsCode(jsCode);

      // 构建变量注入代码（排除核心变量，避免覆盖 result/baseUrl/content）
      final coreVars = {'result', 'baseUrl', 'content', 'src'};
      final varInjections = <String>[];
      if (variables != null) {
        for (final entry in variables.entries) {
          if (!coreVars.contains(entry.key)) {
            varInjections.add('var ${entry.key} = ${jsonEncode(entry.value)};');
          }
        }
      }
      final varCode = varInjections.join('\n');

      // 构建共享作用域变量注入（借鉴 legado 的 scope 链）
      final sharedVars = <String, String>{};
      final sourceUrl = variables?['source']?['bookSourceUrl'] as String?;
      if (sourceUrl != null && _sharedScopeVars.containsKey(sourceUrl)) {
        sharedVars.addAll(_sharedScopeVars[sourceUrl]!);
      }
      final sharedVarsCode = sharedVars.entries.map((e) =>
        'var ${e.key} = ${jsonEncode(e.value)};'
      ).join('\n');

      // jsLib 已通过 loadJsLib() 加载到全局作用域
      // 借鉴 legado：evalJS 时 bindings.prototype = sharedScope
      // QuickJS 等价：jsLib 函数在 globalThis 上，IIFE 内部自动可访问

      final wrappedScript = '''
        (function() {
          var result = $contentStr;
          var baseUrl = ${jsonEncode(baseUrl ?? '')};
          var content = result;
          var src = result;
          $sharedVarsCode
          $varCode
          var __returnValue = (function() { $wrappedCode })();
          if (typeof __returnValue === 'object' && __returnValue !== null) {
            return JSON.stringify(__returnValue);
          }
          return __returnValue;
        })();
      ''';
      final evalResult = _jsRuntime!.evaluate(wrappedScript);
      _flushConsoleLogs();
      if (evalResult.isError) {
        debugPrint('JsEngine executeSync error: ${evalResult.stringResult}');
        AppLogger.instance.logJsError('QuickJS', evalResult.stringResult);
        return null;
      }
      return _parseJsResult(evalResult.stringResult);
    } catch (e) {
      debugPrint('JsEngine executeSync exception: $e');
      AppLogger.instance.logJsError('QuickJS', e.toString());
      return null;
    }
  }

  /// 包裹 JS 代码，确保最后一个表达式的值被返回
  /// 如果代码已经包含 return 语句，直接使用
  /// 如果没有 return，在代码末尾添加 return 语句
  String _wrapJsCode(String code) {
    final trimmed = code.trim();

    // 已经有 return 语句 → 直接使用
    if (trimmed.contains(RegExp(r'\breturn\b'))) {
      return trimmed;
    }

    // 单行简单表达式（如变量名、函数调用、字符串等）
    // 将整个代码作为返回值
    final lines = trimmed.split('\n');
    final lastLine = lines.last.trim();

    // 如果最后一行是语句（以 ; 结尾或是块语句），需要用 eval 包裹
    // 否则直接 return
    if (lastLine.isEmpty) {
      return trimmed;
    }

    // 多行代码：最后一行作为返回值
    if (lines.length > 1) {
      final allButLast = lines.sublist(0, lines.length - 1).join('\n');
      return '$allButLast\nreturn $lastLine';
    }

    // 单行代码：直接 return
    return 'return $trimmed';
  }

  /// 从规则字符串中提取 JS 代码
  /// 支持：<js>code</js>、@js:code、@rhino:code、@quickjs:code
  String? _extractJsCode(String rule) {
    // <js>code</js> 格式
    final jsTagPattern = RegExp(r'<js>([\s\S]*?)</js>', caseSensitive: false);
    final jsTagMatch = jsTagPattern.firstMatch(rule);
    if (jsTagMatch != null) {
      return jsTagMatch.group(1)?.trim();
    }

    // @js:code、@rhino:code、@quickjs:code、@java:code、@ts:code 格式
    final prefixPattern = RegExp(r'^@(?:js|rhino|quickjs|java|ts):', caseSensitive: false);
    if (prefixPattern.hasMatch(rule)) {
      return rule.replaceFirst(prefixPattern, '').trim();
    }

    // {{expression}} 格式
    final templatePattern = RegExp(r'\{\{([\s\S]*?)\}\}');
    final templateMatch = templatePattern.firstMatch(rule);
    if (templateMatch != null) {
      return 'return ${templateMatch.group(1)?.trim()}';
    }

    return null;
  }

  // ===== 书源规则执行（分流核心）=====

  /// 处理 JS 书源规则（异步）
  Future<String?> processJsRule(String content, String jsCode, {String? baseUrl, JsEngineType? sourceEngine, Map<String, dynamic>? env}) async {
    if (!_initialized || _jsRuntime == null) {
      await init();
      if (!_initialized || _jsRuntime == null) return null;
    }

    // 先提取 JS 代码（去掉 <js></js> 标签或 @js: 前缀）
    final extracted = _extractJsCode(jsCode) ?? jsCode;
    final resolved = resolveEngine(extracted, sourceEngine: sourceEngine);

    AppLogger.instance.logJsExecute(
      resolved.engine == JsEngineType.rhino ? 'Rhino' : 'QuickJS',
      resolved.code,
    );

    // 合并 env：传入的 env 优先，补充 baseUrl
    final mergedEnv = <String, dynamic>{
      'baseUrl': baseUrl ?? '',
    };
    if (env != null) {
      mergedEnv.addAll(env);
      if (!mergedEnv.containsKey('baseUrl')) mergedEnv['baseUrl'] = baseUrl ?? '';
    }

    if (resolved.engine == JsEngineType.rhino) {
      return _executeRhinoRule(resolved.code, result: content, env: mergedEnv);
    }

    // 借鉴 legado 的 preCache 机制：在执行 JS 前，预缓存 java.ajax/get/post 的结果
    try {
      await _preCacheBridgeCalls(resolved.code, env: mergedEnv);
    } catch (e) {
      AppLogger.instance.warn(LogCategory.js, '预缓存桥接调用失败，继续执行JS', detail: e.toString());
    }

    return _executeQuickJSRule(resolved.code, result: content, env: mergedEnv, variables: _extractVariables(mergedEnv));
  }

  /// 处理带书籍上下文的 JS 规则
  Future<String?> processJsWithBook(
    String jsCode, {
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    Map<String, dynamic>? source,
    String? content,
    int? index,
    JsEngineType? sourceEngine,
  }) async {
    if (!_initialized || _jsRuntime == null) {
      await init();
      if (!_initialized || _jsRuntime == null) return null;
    }

    // 先提取 JS 代码
    final extracted = _extractJsCode(jsCode) ?? jsCode;
    final resolved = resolveEngine(extracted, sourceEngine: sourceEngine);

    final env = <String, dynamic>{
      'book': book ?? {},
      'chapter': chapter ?? {},
      'source': source ?? {},
      'cookie': <String, String>{},
      'baseUrl': book?['bookUrl'] ?? '',
    };

    if (resolved.engine == JsEngineType.rhino) {
      return _executeRhinoRule(resolved.code, result: content, env: env);
    }

    try {
      final wrappedCode = _wrapJsCode(resolved.code);

      // 构建共享作用域变量注入
      final sharedVars = <String, String>{};
      final sourceUrl = source?['bookSourceUrl'] as String?;
      if (sourceUrl != null && _sharedScopeVars.containsKey(sourceUrl)) {
        sharedVars.addAll(_sharedScopeVars[sourceUrl]!);
      }
      final sharedVarsCode = sharedVars.entries.map((e) =>
        'var ${e.key} = ${jsonEncode(e.value)};'
      ).join('\n');

      final wrappedScript = '''
        (function() {
          var result = ${jsonEncode(content ?? '')};
          var baseUrl = ${jsonEncode(book?['bookUrl'] ?? '')};
          var content = result;
          var book = ${jsonEncode(book ?? {})};
          var chapter = ${jsonEncode(chapter ?? {})};
          var source = ${jsonEncode(source ?? {})};
          var cookie = ${jsonEncode(<String, String>{})};
          var index = ${jsonEncode(index ?? 0)};
          $sharedVarsCode
          var __returnValue = (function() { $wrappedCode })();
          if (typeof __returnValue === 'object' && __returnValue !== null) {
            return JSON.stringify(__returnValue);
          }
          return __returnValue;
        })();
      ''';
      final evalResult = _jsRuntime!.evaluate(wrappedScript);
      _flushConsoleLogs();
      if (evalResult.isError) {
        debugPrint('JsEngine processJsWithBook error: ${evalResult.stringResult}');
        AppLogger.instance.logJsError('QuickJS', evalResult.stringResult);
        return null;
      }
      return evalResult.stringResult;
    } catch (e) {
      debugPrint('JsEngine processJsWithBook exception: $e');
      AppLogger.instance.logJsError('QuickJS', e.toString());
      return null;
    }
  }

  /// 执行书源规则（统一入口，支持分流）
  ///
  /// 规则前缀路由：
  /// - @rhino: / <rhino> → Rhino 引擎
  /// - @quickjs: / <quickjs> → QuickJS 引擎
  /// - @java: / <java> → Rhino 引擎（Java 互操作）
  /// - @ts: / <ts> → TS 编译后 QuickJS 执行
  /// - @js: / <js> → 自动识别引擎
  /// - 无前缀 → 自动识别引擎
  Future<String?> evaluateBookRule(String ruleCode, {
    String? result,
    Map<String, dynamic>? env,
    JsEngineType? sourceEngine,
  }) async {
    final resolved = resolveEngine(ruleCode, sourceEngine: sourceEngine);
    var code = resolved.code;

    // TS 需要先编译
    if (ruleCode.startsWith('@ts:') || ruleCode.startsWith('<ts>')) {
      code = await compileTypeScript(code);
    }

    if (resolved.engine == JsEngineType.rhino) {
      return _executeRhinoRule(code, result: result, env: env);
    }

    return _executeQuickJSRule(code, result: result, env: env);
  }

  // ===== QuickJS 规则执行 =====

  /// 从 env 中提取非核心变量，用于注入到 JS 作用域
  static const _coreEnvVars = {'result', 'baseUrl', 'content', 'src', 'book', 'chapter', 'source', 'cookie', 'title'};

  Map<String, dynamic>? _extractVariables(Map<String, dynamic>? env) {
    if (env == null) return null;
    final vars = <String, dynamic>{};
    for (final entry in env.entries) {
      if (!_coreEnvVars.contains(entry.key)) {
        vars[entry.key] = entry.value;
      }
    }
    return vars.isEmpty ? null : vars;
  }

  Future<String?> _executeQuickJSRule(String jsCode, {
    String? result,
    Map<String, dynamic>? env,
    Map<String, dynamic>? variables,
  }) async {
    if (!_initialized || _jsRuntime == null) {
      await init();
      if (!_initialized || _jsRuntime == null) return null;
    }
    try {
      // 断点1：记录原始JS代码
      AppLogger.instance.debug(LogCategory.js, '[QuickJS] 开始执行',
        detail: jsCode.length > 300 ? '${jsCode.substring(0, 300)}...' : jsCode);

      // 自动补 return
      final wrappedCode = _wrapJsCode(jsCode);

      // 断点2：记录包装后的代码
      AppLogger.instance.debug(LogCategory.js, '[QuickJS] 代码包装完成',
        detail: wrappedCode.length > 200 ? '${wrappedCode.substring(0, 200)}...' : wrappedCode);

      // 构建共享作用域变量注入（借鉴 legado 的 scope 链）
      final sharedVars = <String, String>{};
      final sourceUrl = env?['source']?['bookSourceUrl'] as String?;
      if (sourceUrl != null && _sharedScopeVars.containsKey(sourceUrl)) {
        sharedVars.addAll(_sharedScopeVars[sourceUrl]!);
      }

      // 构建共享变量注入代码
      final sharedVarsCode = sharedVars.entries.map((e) =>
        'var ${e.key} = ${jsonEncode(e.value)};'
      ).join('\n');

      // 构建额外变量注入代码（排除核心变量，避免覆盖）
      final coreVars = {'result', 'baseUrl', 'content', 'src', 'book', 'chapter', 'source', 'cookie', 'title'};
      final varInjections = <String>[];
      if (variables != null) {
        for (final entry in variables.entries) {
          if (!coreVars.contains(entry.key)) {
            varInjections.add('var ${entry.key} = ${jsonEncode(entry.value)};');
          }
        }
      }
      final varCode = varInjections.join('\n');

      // jsLib 已通过 loadJsLib() 加载到全局作用域
      // 借鉴 legado：evalJS 时 bindings.prototype = sharedScope
      // QuickJS 等价：jsLib 函数在 globalThis 上，IIFE 内部自动可访问

      final wrappedScript = '''
        (function() {
          var result = ${jsonEncode(result ?? '')};
          var baseUrl = ${jsonEncode(env?['baseUrl'] ?? '')};
          var book = ${jsonEncode(env?['book'] ?? {})};
          var chapter = ${jsonEncode(env?['chapter'] ?? {})};
          var source = (function() {
            var _data = ${jsonEncode(env?['source'] ?? {})};
            var _vars = ${jsonEncode(env?['sourceVars'] ?? {})};
            // 借鉴 legado：source.getVariable() 无参返回 variable 字段的原始字符串值
            // source.getVariable(key) 有参返回指定 key 的值
            // source.setVariable(value) 设置整个 variable 字符串
            var obj = Object.assign({}, _data);
            obj.getVariable = function(key) {
              if (key === undefined) {
                // 无参：返回 variable 字段的原始值（legado 从 CacheManager 读取）
                return _data['variable'] || '';
              }
              return _vars[key] || _data[key] || '';
            };
            obj.setVariable = function(keyOrValue, value) {
              if (value === undefined) {
                // 单参数：设置整个 variable 字符串（legado 风格）
                _data['variable'] = String(keyOrValue);
              } else {
                // 双参数：设置指定 key
                _vars[keyOrValue] = String(value);
              }
              return keyOrValue;
            };
            obj.putVariable = function(value) {
              _data['variable'] = String(value);
              return value;
            };
            return obj;
          })();
          var cookie = ${jsonEncode(env?['cookie'] ?? {})};
          var title = ${jsonEncode(env?['chapter']?['title'] ?? '')};
          var src = result;

          // 注入共享作用域变量（借鉴 legado SharedJsScope）
          $sharedVarsCode

          // 注入额外变量（如 key, page 等）
          $varCode

          var __returnValue = (function() { $wrappedCode })();
          if (typeof __returnValue === 'object' && __returnValue !== null) {
            return JSON.stringify(__returnValue);
          }
          return __returnValue;
        })();
      ''';

      final evalResult = _jsRuntime!.evaluate(wrappedScript);

      // 提取 console 缓存的日志，同步到 AppLogger（借鉴 legado 的调试输出机制）
      _flushConsoleLogs();

      // 断点3：记录执行结果
      AppLogger.instance.debug(LogCategory.js, '[QuickJS] 执行完成',
        detail: 'isError=${evalResult.isError}, result=${evalResult.stringResult.length > 200 ? "${evalResult.stringResult.substring(0, 200)}..." : evalResult.stringResult}');

      if (evalResult.isError) {
        debugPrint('JsEngine QuickJS error: ${evalResult.stringResult}');
        AppLogger.instance.logJsError('QuickJS', evalResult.stringResult);
        // QuickJS 失败 → 降级到 Rust 引擎
        return fallbackToRustEngine(jsCode, result: result, env: env);
      }
      final strResult = evalResult.stringResult;
      // undefined → 返回空字符串而不是 null（书源规则可能不需要返回值）
      if (strResult == 'undefined') return '';
      // null → 返回 Dart null，避免 "null" 字符串被当作有效结果
      if (strResult == 'null') return null;
      return strResult;
    } catch (e) {
      debugPrint('JsEngine QuickJS exception: $e');
      AppLogger.instance.logJsError('QuickJS', e.toString());
      // 即使异常也尝试提取 console 日志
      _flushConsoleLogs();
      // QuickJS 异常 → 降级到 Rust 引擎
      return fallbackToRustEngine(jsCode, result: result, env: env);
    }
  }

  /// 提取 QuickJS 中 console 缓存的日志，同步到 AppLogger
  /// 借鉴 legado 的调试输出机制：JS 中的 console.log/warn/error 输出到调试页面
  void _flushConsoleLogs() {
    if (!_initialized || _jsRuntime == null) return;
    try {
      // 先检查 console 是否存在且有 _getLogs 方法
      final checkResult = evaluate('typeof console !== "undefined" ? (typeof console._getLogs === "function" ? "has_getLogs" : "no_getLogs") : "no_console"');
      if (checkResult == 'no_console') {
        debugPrint('JsEngine: console 不存在，重新注入');
        // 重新注入 console
        evaluate('var _consoleLogs = []; globalThis.console = { log: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"log", msg:msg}); }, warn: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"warn", msg:msg}); }, error: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"error", msg:msg}); }, info: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"info", msg:msg}); }, debug: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"debug", msg:msg}); }, _getLogs: function() { return _consoleLogs; }, _clearLogs: function() { _consoleLogs.length = 0; } };');
        return; // 下次执行时再提取
      }
      if (checkResult == 'no_getLogs') {
        debugPrint('JsEngine: console 存在但没有 _getLogs，重新注入');
        evaluate('var _consoleLogs = []; globalThis.console = { log: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"log", msg:msg}); }, warn: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"warn", msg:msg}); }, error: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"error", msg:msg}); }, info: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"info", msg:msg}); }, debug: function() { var msg = Array.from(arguments).join(" "); _consoleLogs.push({level:"debug", msg:msg}); }, _getLogs: function() { return _consoleLogs; }, _clearLogs: function() { _consoleLogs.length = 0; } };');
        return;
      }

      final logsResult = evaluate('JSON.stringify(console._getLogs())');
      if (logsResult == null || logsResult == '[]' || logsResult == 'undefined') return;

      final logsJson = logsResult;
      if (!logsJson.startsWith('[')) return;

      final logs = jsonDecode(logsJson) as List;
      for (final log in logs) {
        if (log is! Map) continue;
        final level = log['level'] as String? ?? 'log';
        final msg = log['msg']?.toString() ?? '';
        if (msg.isEmpty) continue;

        switch (level) {
          case 'error':
            AppLogger.instance.error(LogCategory.js, msg);
            break;
          case 'warn':
            AppLogger.instance.warn(LogCategory.js, msg);
            break;
          case 'info':
            AppLogger.instance.info(LogCategory.js, msg);
            break;
          case 'debug':
            AppLogger.instance.debug(LogCategory.js, msg);
            break;
          default:
            AppLogger.instance.info(LogCategory.js, msg);
        }
      }

      // 清除已提取的日志
      evaluate('console._clearLogs()');
    } catch (e) {
      // 日志提取失败不影响主流程
      debugPrint('JsEngine: console日志提取失败: $e');
    }
  }

  // ===== Rust 引擎降级（通过 native-proxy API）=====

  /// QuickJS 执行失败时，降级到 Rust boa 引擎
  /// 通过 HTTP 调用 native-proxy 的 /api/js/* 接口
  Future<String?> fallbackToRustEngine(String jsCode, {
    String? result,
    Map<String, dynamic>? env,
  }) async {
    if (kIsWeb) return null;

    final apiPort = _rustApiPort;
    if (apiPort == 0) {
      debugPrint('JsEngine: Rust API 不可用，降级失败');
      return null;
    }

    try {
      debugPrint('JsEngine: QuickJS 失败，降级到 Rust 引擎 (port: $apiPort)');
      final client = HttpClient();
      final code = Uri.encodeComponent(jsCode);
      final resultStr = Uri.encodeComponent(result ?? '');
      final baseUrl = Uri.encodeComponent(env?['baseUrl'] ?? '');
      final bookJson = env?['book'] != null ? Uri.encodeComponent(jsonEncode(env!['book'])) : '';
      final chapterJson = env?['chapter'] != null ? Uri.encodeComponent(jsonEncode(env!['chapter'])) : '';

      final url = 'http://localhost:$apiPort/api/js/evaluateWithContext'
          '?code=$code'
          '&result=$resultStr'
          '&baseUrl=$baseUrl'
          '&content=$resultStr'
          '${bookJson.isNotEmpty ? '&book=$bookJson' : ''}'
          '${chapterJson.isNotEmpty ? '&chapter=$chapterJson' : ''}';

      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (body.isEmpty) return null;

      final json = jsonDecode(body) as Map<String, dynamic>;
      final apiResult = json['result'] as Map<String, dynamic>?;

      if (apiResult == null || apiResult['success'] != true) {
        debugPrint('JsEngine: Rust 引擎也失败了: ${apiResult?['result']}');
        return null;
      }

      return apiResult['result']?.toString();
    } catch (e) {
      debugPrint('JsEngine: Rust API 调用失败: $e');
      return null;
    }
  }

  /// Rust API 端口（由 cors-proxy.js 启动时通过 stderr 输出）
  int _rustApiPort = 0;

  /// 设置 Rust API 端口（供外部调用）
  void setRustApiPort(int port) {
    _rustApiPort = port;
  }

  // ===== Rhino 规则执行（通过 NativeChannel）=====

  Future<String?> _executeRhinoRule(String code, {
    String? result,
    Map<String, dynamic>? env,
  }) async {
    if (kIsWeb) return null;
    try {
      // 同步桥接缓存到 Rhino 环境
      final bindings = <String, dynamic>{
        'result': result ?? '',
        'baseUrl': env?['baseUrl'] ?? '',
        ...?env,
        '_bridgeCache': Map<String, String>.from(_bridgeCache),
      };

      // 判断走 evaluateJavaRule 还是 executeScript
      // 含 Legado 规则前缀 → evaluateJavaRule（支持 @css:/@text:/@attr: 等）
      // 纯 JS 代码 → executeScript（通用 Rhino 执行）
      final isLegadoRule = code.startsWith('@css:') ||
          code.startsWith('@text:') ||
          code.startsWith('@attr:') ||
          code.startsWith('java:');

      if (isLegadoRule) {
        return await NativeChannel.instance.evaluateJavaRule(
          code,
          result: result,
          env: bindings,
        );
      }

      return await NativeChannel.instance.executeScript(
        code,
        bindings: bindings,
      );
    } catch (e) {
      debugPrint('JsEngine Rhino error: $e');
      return null;
    }
  }

  // ===== 工具方法 =====

  Future<String?> regexReplace(String text, String pattern, String replacement) async {
    if (!_initialized || _jsRuntime == null) return null;
    try {
      final script = '''
        (function() {
          var text = ${jsonEncode(text)};
          var pattern = $pattern;
          var replacement = ${jsonEncode(replacement)};
          return text.replace(new RegExp(pattern, 'g'), replacement);
        })();
      ''';
      final evalResult = _jsRuntime!.evaluate(script);
      if (evalResult.isError) return null;
      return evalResult.stringResult;
    } catch (e) {
      return null;
    }
  }

  Future<String?> cssSelect(String html, String selector) async {
    if (!_initialized || _jsRuntime == null) return null;
    try {
      final script = '''
        (function() {
          return java.jsoup.selectFirst(${jsonEncode(html)}, ${jsonEncode(selector)});
        })();
      ''';
      final evalResult = _jsRuntime!.evaluate(script);
      if (evalResult.isError) return null;
      return evalResult.stringResult;
    } catch (e) {
      return null;
    }
  }

  Future<String?> xpathSelect(String html, String xpath) async {
    return null;
  }

  Future<dynamic> jsonPath(String jsonStr, String path) async {
    if (!_initialized || _jsRuntime == null) return null;
    try {
      final script = '''
        (function() {
          var data = JSON.parse(${jsonEncode(jsonStr)});
          var path = ${jsonEncode(path)};
          var parts = path.replace(/^\\\$\\\./, '').split('.');
          var result = data;
          for (var i = 0; i < parts.length; i++) {
            if (result == null) return null;
            result = result[parts[i]];
          }
          return JSON.stringify(result);
        })();
      ''';
      final evalResult = _jsRuntime!.evaluate(script);
      if (evalResult.isError) return null;
      return evalResult.stringResult;
    } catch (e) {
      return null;
    }
  }

  dynamic _parseJsResult(String result) {
    // undefined → 返回空字符串（而不是 null，避免书源规则误判）
    if (result == 'undefined') return '';
    if (result == 'null') return null;
    if (result == 'true') return true;
    if (result == 'false') return false;
    final numVal = num.tryParse(result);
    if (numVal != null) return numVal;
    try {
      return jsonDecode(result);
    } catch (_) {}
    return result;
  }

  // ===== 共享作用域管理（借鉴 legado SharedJsScope）=====

  /// 加载书源的 jsLib 并创建共享作用域
  /// 借鉴 legado 的 BaseSource.getShareScope() + SharedJsScope.getScope()
  /// 加载书源 jsLib（借鉴 legado 的 SharedJsScope + getShareScope 机制）
  ///
  /// legado 的做法：
  /// 1. SharedJsScope.getScope(jsLib) 把 jsLib eval 到一个独立的 scope 对象中
  /// 2. evalJS 时 bindings.prototype = sharedScope，通过原型链访问 jsLib 函数
  /// 3. 同一书源的 jsLib 只加载一次（LRU 缓存），切换书源时用新的 scope
  ///
  /// QuickJS 的等价实现：
  /// 1. 把 jsLib eval 到 globalThis 上（等价于 legado 的 eval(jsLib, scope)）
  /// 2. 同一书源只加载一次，切换书源时先清除旧的全局函数
  /// 3. 用 _currentJsLibSourceUrl 追踪当前加载了哪个书源的 jsLib
  void loadJsLib(String sourceUrl, String jsLib) {
    if (jsLib.trim().isEmpty) return;

    // 缓存 jsLib 代码
    _jsLibCache[sourceUrl] = jsLib;

    // 如果当前已加载的就是同一个书源，不需要重新加载
    if (_currentJsLibSourceUrl == sourceUrl) return;

    // 切换书源：先清除旧的 jsLib 全局函数
    _clearCurrentJsLib();

    // 提取 jsLib 中定义的函数名（用于后续清除）
    _extractFunctionNames(jsLib);

    // 把 jsLib eval 到全局作用域（等价于 legado 的 RhinoScriptEngine.eval(jsLib, scope)）
    try {
      _jsRuntime?.evaluate(jsLib);
      _currentJsLibSourceUrl = sourceUrl;
      debugPrint('📚 已加载书源JS库到全局作用域: $sourceUrl (${_currentJsLibFunctions.length}个函数)');
    } catch (e) {
      debugPrint('❌ 加载书源JS库失败: $e');
    }
  }

  /// 清除当前已加载的 jsLib 全局函数
  /// 借鉴 legado 的 scope 切换机制：切换书源时清除旧的 scope
  void _clearCurrentJsLib() {
    if (_currentJsLibFunctions.isEmpty || _jsRuntime == null) return;
    try {
      final deleteCode = _currentJsLibFunctions.map((fn) => 'try{delete globalThis.$fn}catch(e){}').join(';');
      _jsRuntime!.evaluate(deleteCode);
      debugPrint('📚 已清除旧书源JS库: $_currentJsLibSourceUrl (${_currentJsLibFunctions.length}个函数)');
    } catch (e) {
      debugPrint('❌ 清除旧书源JS库失败: $e');
    }
    _currentJsLibFunctions.clear();
    _currentJsLibSourceUrl = null;
  }

  /// 提取 JS 代码中定义的函数名
  /// 匹配 function xxx() 和 var/const/let/this.xxx = function/()=> 模式
  void _extractFunctionNames(String jsLib) {
    _currentJsLibFunctions.clear();
    // 匹配 function xxx( 模式
    final funcPattern = RegExp(r'function\s+(\w+)\s*\(');
    for (final m in funcPattern.allMatches(jsLib)) {
      _currentJsLibFunctions.add(m.group(1)!);
    }
    // 匹配 var/const/let xxx = function / xxx = ()=> / xxx = (...) => 模式
    final varPattern = RegExp(r'(?:var|const|let)\s+(\w+)\s*=\s*(?:function|\(|[^(]*=>)');
    for (final m in varPattern.allMatches(jsLib)) {
      _currentJsLibFunctions.add(m.group(1)!);
    }
    // 匹配 this.xxx = function / this.xxx = ()=> 模式
    final thisPattern = RegExp(r'this\.(\w+)\s*=\s*(?:function|\(|[^(]*=>)');
    for (final m in thisPattern.allMatches(jsLib)) {
      _currentJsLibFunctions.add(m.group(1)!);
    }
  }

  /// 获取书源的 jsLib 代码
  String? getJsLib(String sourceUrl) => _jsLibCache[sourceUrl];

  /// 清除书源的 jsLib 缓存
  void clearJsLib(String sourceUrl) {
    _jsLibCache.remove(sourceUrl);
  }

  Future<void> loadSharedScope(String sourceUrl, String? jsLib) async {
    if (jsLib == null || jsLib.trim().isEmpty) return;
    if (_sharedScopeVars.containsKey(sourceUrl)) return;

    final scopeVars = await SharedJsScope.instance.createScope(
      jsLib,
      (code) => evaluate(code),
    );
    _sharedScopeVars[sourceUrl] = scopeVars;
  }

  /// 获取书源的共享作用域变量
  Map<String, String>? getSharedScope(String sourceUrl) {
    return _sharedScopeVars[sourceUrl];
  }

  /// 清除书源的共享作用域
  void clearSharedScope(String sourceUrl) {
    _sharedScopeVars.remove(sourceUrl);
  }

  /// 预缓存桥接结果（用于同步模式的 java.ajax 等）
  /// 借鉴 legado 的 CacheManager 机制
  Future<void> preCacheBridgeResult(String method, String url, String result) async {
    final script = '_javaCache["${method}:${url}"] = ${jsonEncode(result)};';
    evaluate(script);
  }

  /// 批量预缓存 HTTP 结果（在 processJsRule 前调用）
  /// 解决 QuickJS 同步模式下 java.ajax() 无法异步请求的问题
  Future<void> preCacheHttpResults(Map<String, String> urlResults) async {
    final entries = urlResults.entries.map((e) =>
      '_javaCache["http_get:${e.key}"] = ${jsonEncode(e.value)};'
    ).join('\n');
    if (entries.isNotEmpty) {
      evaluate(entries);
    }
  }

  /// 批量预缓存加密结果
  Future<void> preCacheCryptoResults(Map<String, String> cryptoResults) async {
    final entries = cryptoResults.entries.map((e) =>
      '_javaCache["${e.key}"] = ${jsonEncode(e.value)};'
    ).join('\n');
    if (entries.isNotEmpty) {
      evaluate(entries);
    }
  }

  /// 预缓存桥接调用（核心方法）
  /// 在执行 JS 代码前，扫描代码中的 java.ajax/get/post/aesEncode/md5Encode 等调用
  /// 通过 NativeChannel 预获取结果，写入 _javaCache
  /// 借鉴 legado 的 preCacheHttpResults 机制，但自动扫描而非手动传入
  Future<void> _preCacheBridgeCalls(String jsCode, {Map<String, dynamic>? env}) async {
    if (_jsRuntime == null) return;

    final baseUrl = env?['baseUrl'] as String? ?? '';
    final httpUrls = <String>{};

    // 1. 扫描字面量 URL: java.ajax("url"), java.get("url"), java.post("url"), fetch("url")
    final literalPattern = RegExp(
      r"""(?:java\.(?:ajax|get|post)|fetch)\s*\(\s*["']([^"']+)["']""",
      multiLine: true,
    );
    for (final match in literalPattern.allMatches(jsCode)) {
      final url = match.group(1);
      if (url != null && url.isNotEmpty) {
        // 处理模板变量 {{key}}, {{page}} 等
        var resolvedUrl = url;
        if (env != null) {
          resolvedUrl = _resolveTemplateVars(url, env);
        }
        final absoluteUrl = _resolveUrl(resolvedUrl, baseUrl);
        if (absoluteUrl.isNotEmpty && absoluteUrl.startsWith('http')) {
          httpUrls.add(absoluteUrl);
        }
      }
    }

    // 2. 扫描变量拼接 URL: java.ajax(url), java.get(baseUrl + "/api"), fetch(variable)
    // 先在 QuickJS 中求值变量，获取完整 URL
    final varPattern = RegExp(
      r"""(?:java\.(?:ajax|get|post)|fetch)\s*\(\s*([^"')\s][^)]*?)\s*\)""",
      multiLine: true,
    );
    for (final match in varPattern.allMatches(jsCode)) {
      final expr = match.group(1)?.trim();
      if (expr == null || expr.isEmpty) continue;
      // 跳过字面量字符串（已被上面匹配）
      if (expr.startsWith('"') || expr.startsWith("'")) continue;
      // 尝试在 QuickJS 中求值表达式
      try {
        // 注入 env 变量后求值
        final varCode = <String>[];
        if (env != null) {
          for (final entry in env.entries) {
            if (entry.value is String) {
              varCode.add('var ${entry.key} = ${jsonEncode(entry.value)};');
            } else if (entry.value is num || entry.value is bool) {
              varCode.add('var ${entry.key} = ${entry.value};');
            }
          }
        }
        final evalScript = '${varCode.join('\n')} (function() { try { var __url = String($expr); return __url; } catch(e) { return ""; } })()';
        final urlResult = evaluate(evalScript);
        if (urlResult != null && urlResult.isNotEmpty && urlResult.startsWith('http')) {
          httpUrls.add(urlResult);
        }
      } catch (_) {
        // 求值失败，跳过
      }
    }

    // 3. 扫描 URL 模板变量: fetch(`https://xxx/${key}`), java.ajax(`${baseUrl}/api`)
    final templatePattern = RegExp(r'`([^`]*\$\{[^}]+\}[^`]*)`');
    for (final match in templatePattern.allMatches(jsCode)) {
      var template = match.group(1);
      if (template == null) continue;
      // 替换 ${var} 为 env 中的值
      if (env != null) {
        template = template.replaceAllMapped(
          RegExp(r'\$\{([^}]+)\}'),
          (m) {
            final varName = m.group(1)?.trim() ?? '';
            final val = env[varName];
            if (val != null) return val.toString();
            // 尝试点号路径: source.bookSourceUrl
            final parts = varName.split('.');
            dynamic current = env;
            for (final part in parts) {
              if (current is Map) {
                current = current[part];
              } else {
                current = null;
                break;
              }
            }
            return current?.toString() ?? '';
          },
        );
      }
      final absoluteUrl = _resolveUrl(template, baseUrl);
      if (absoluteUrl.isNotEmpty && absoluteUrl.startsWith('http')) {
        httpUrls.add(absoluteUrl);
      }
    }

    // 4. 并发预缓存 HTTP 结果
    if (httpUrls.isNotEmpty) {
      AppLogger.instance.debug(LogCategory.js, '预缓存 ${httpUrls.length} 个HTTP请求');
      // 从 env 中获取自定义 headers（书源配置的 header 字段）
      final customHeaders = env?['headers'] as Map<String, String>?;
      final futures = httpUrls.map((url) async {
        try {
          final result = await NativeChannel.instance.httpGet(url, headers: customHeaders);
          if (result != null) {
            return MapEntry('http_get:$url', result);
          }
        } catch (e) {
          AppLogger.instance.warn(LogCategory.js, '预缓存HTTP失败: $url', detail: e.toString());
        }
        return null;
      });

      final results = await Future.wait(futures);
      final cacheEntries = <String, String>{};
      for (final entry in results) {
        if (entry != null) {
          cacheEntries[entry.key] = entry.value;
        }
      }
      if (cacheEntries.isNotEmpty) {
        await preCacheHttpResults(cacheEntries);
      }
    }

    // 5. 扫描 java.aesEncode/aesDecode 调用（已有纯 JS _AES 引擎，不再需要预缓存）
    // 6. 扫描 java.md5Encode 调用（暂无纯 JS MD5 实现，仍需预缓存）
    final md5Pattern = RegExp(
      r"""java\.md5Encode\s*\(\s*["']([^"']+)["']""",
      multiLine: true,
    );
    final cryptoResults = <String, String>{};
    for (final match in md5Pattern.allMatches(jsCode)) {
      final str = match.group(1);
      if (str != null) {
        final cacheKey = 'md5:$str';
        if (!_isCached(cacheKey)) {
          final result = await NativeChannel.instance.md5(str);
          if (result != null) cryptoResults[cacheKey] = result;
        }
      }
    }

    if (cryptoResults.isNotEmpty) {
      await preCacheCryptoResults(cryptoResults);
    }

    // 7. 预缓存 HTML 解析结果（使用 Dart 原生 html 包）
    final htmlParsePattern = RegExp(
      r'''(?:_JsoupLite\.(selectFirst|selectAll)|java\.(getString|getElement|getElements))\s*\(\s*([^,)]+)(?:\s*,\s*([^)]+))?\s*\)''',
      multiLine: true,
    );

    // 收集已缓存的 HTTP 内容
    final knownHtml = <String, String>{};
    // 从 HTTP 缓存中获取内容
    for (final url in httpUrls) {
      final httpCacheKey = 'http_get:$url';
      final cached = evaluate('_javaCache[${jsonEncode(httpCacheKey)}]');
      if (cached != null && cached.isNotEmpty && cached != 'undefined' && cached.length > 50) {
        knownHtml[httpCacheKey] = cached;
      }
    }

    for (final match in htmlParsePattern.allMatches(jsCode)) {
      final method = match.group(1) ?? match.group(2);
      final firstArg = match.group(3)?.trim() ?? '';
      final secondArg = match.group(4)?.trim();

      String? htmlContent;
      String? selector;

      // 解析 HTML 内容来源
      if (firstArg == 'result' || firstArg == 'content' || firstArg == 'src') {
        // 内容来自 result 变量 - 从 HTTP 缓存获取
        for (final entry in knownHtml.entries) {
          htmlContent = entry.value;
          break;
        }
      } else if (firstArg.startsWith('"') || firstArg.startsWith("'")) {
        // 字面量字符串内容
        try {
          htmlContent = jsonDecode(firstArg) as String;
        } catch (_) {}
      } else {
        // 变量名 - 尝试从 QuickJS 求值
        try {
          final evalResult = evaluate('(function(){ try { var __v = $firstArg; return (typeof __v === "string" && __v.length > 50) ? __v : ""; } catch(e) { return ""; } })()');
          if (evalResult != null && evalResult.isNotEmpty && evalResult.length > 50) {
            htmlContent = evalResult;
          }
        } catch (_) {}
      }

      // 解析选择器
      if (secondArg != null) {
        if (secondArg.startsWith('"') || secondArg.startsWith("'")) {
          try {
            selector = jsonDecode(secondArg);
          } catch (_) {
            selector = secondArg;
          }
        } else {
          selector = secondArg;
        }
        // 清理选择器前缀
        if (selector?.startsWith('@@') == true) selector = selector!.substring(2);
        if (selector?.startsWith('@css:') == true) selector = selector!.substring(5);
      } else if (method == 'getString' || method == 'getElement' || method == 'getElements') {
        // 单参数模式：firstArg 是选择器，内容来自 result
        var sel = firstArg;
        if (sel.startsWith('"') || sel.startsWith("'")) {
          try {
            sel = jsonDecode(sel);
          } catch (_) {}
        }
        if (sel.startsWith('@@')) sel = sel.substring(2);
        if (sel.startsWith('@css:')) sel = sel.substring(5);
        selector = sel;
        // 单参数模式需要从 HTTP 缓存获取内容
        if (htmlContent == null) {
          for (final entry in knownHtml.entries) {
            htmlContent = entry.value;
            break;
          }
        }
      }

      if (htmlContent == null || htmlContent.isEmpty || selector == null || selector.isEmpty) continue;

      // 使用 Dart 原生 html 包解析
      final parsed = _nativeJsoupParse(htmlContent, selector);

      // 计算与 JS 侧 _hashStr 等价的 hash
      final htmlHash = _computeJsHash(htmlContent);

      // 缓存结果到 JS 侧 _javaCache
      final sfKey = 'jsoup_sf:$selector:$htmlHash';
      final saKey = 'jsoup_sa:$selector:$htmlHash';

      if (!_isCached(sfKey)) {
        evaluate('_javaCache[${jsonEncode(sfKey)}] = ${jsonEncode(parsed['first'])};');
      }
      if (!_isCached(saKey)) {
        evaluate('_javaCache[${jsonEncode(saKey)}] = ${jsonEncode(parsed['all'])};');
      }
      // 缓存 text/href/src 供 java.getString 快速访问
      final textKey = 'jsoup_text:$selector:$htmlHash';
      final hrefKey = 'jsoup_href:$selector:$htmlHash';
      if (parsed['text'] != null && !_isCached(textKey)) {
        evaluate('_javaCache[${jsonEncode(textKey)}] = ${jsonEncode(parsed['text'])};');
      }
      if (parsed['href'] != null && (parsed['href'] as String).isNotEmpty && !_isCached(hrefKey)) {
        evaluate('_javaCache[${jsonEncode(hrefKey)}] = ${jsonEncode(parsed['href'])};');
      }
    }
  }

  /// 替换模板变量 {{key}}, {{page}} 等
  String _resolveTemplateVars(String url, Map<String, dynamic> env) {
    return url.replaceAllMapped(
      RegExp(r'\{\{(\w+)\}\}'),
      (match) {
        final varName = match.group(1) ?? '';
        final val = env[varName];
        if (val != null) return val.toString();
        // 尝试点号路径
        final parts = varName.split('.');
        dynamic current = env;
        for (final part in parts) {
          if (current is Map) {
            current = current[part];
          } else {
            current = null;
            break;
          }
        }
        return current?.toString() ?? match.group(0)!;
      },
    );
  }

  /// 使用 Dart 原生 html 包解析 HTML（替代 JS 侧正则版 _JsoupLite）
  Map<String, dynamic> _nativeJsoupParse(String html, String selector) {
    try {
      final doc = html_parser.parse(html);
      final elements = doc.querySelectorAll(selector);
      if (elements.isEmpty) {
        return {'first': '', 'all': <String>[], 'attr': ''};
      }
      final firstEl = elements.first;
      final firstHtml = firstEl.outerHtml;
      final allHtml = elements.map((e) => e.outerHtml).toList();
      final firstText = firstEl.text.trim();
      final firstHref = firstEl.attributes['href'] ?? '';
      final firstSrc = firstEl.attributes['src'] ?? '';
      return {
        'first': firstHtml,
        'all': allHtml,
        'text': firstText,
        'href': firstHref,
        'src': firstSrc,
        'count': elements.length,
      };
    } catch (e) {
      return {'first': '', 'all': <String>[], 'attr': ''};
    }
  }

  /// 计算 JS 侧 _hashStr 等价的 hash 值
  int _computeJsHash(String s) {
    int h = 0;
    for (int i = 0; i < s.length; i++) {
      h = ((h << 5) - h + s.codeUnitAt(i)) & 0xFFFFFFFF;
      if (h > 0x7FFFFFFF) h = h - 0x100000000;
    }
    return h;
  }

  /// 检查缓存键是否已存在
  bool _isCached(String key) {
    // 通过 JS 检查缓存
    final result = evaluate('_javaCache["$key"] !== undefined');
    return result == 'true';
  }

  /// 解析相对URL
  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (baseUrl.isEmpty) return url;
    try {
      return Uri.parse(baseUrl).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  // ===== 脚本编译缓存（借鉴 legado 的 scriptCache）=====

  /// 带缓存的脚本执行
  /// 相同代码只编译一次，后续直接返回缓存结果
  /// 注意：由于 QuickJS 不支持 CompiledScript，这里缓存的是代码解析结果
  dynamic evaluateWithCache(String script) {
    final cacheKey = _md5Hash(script);

    if (_scriptCache.containsKey(cacheKey)) {
      return _scriptCache[cacheKey];
    }

    // 限制缓存大小
    if (_scriptCache.length >= _maxScriptCacheSize) {
      _scriptCache.remove(_scriptCache.keys.first);
    }

    final result = evaluate(script);
    if (result != null) {
      _scriptCache[cacheKey] = result;
    }
    return result;
  }

  /// 清除脚本缓存
  void clearScriptCache() {
    _scriptCache.clear();
  }

  /// MD5 哈希（用于缓存 key）
  String _md5Hash(String input) {
    // 简单哈希，避免引入 crypto 依赖
    var hash = 0;
    for (var i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash + input.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// 释放资源
  void dispose() {
    _jsRuntime?.dispose();
    _jsRuntime = null;
    _initialized = false;
    _installedPackages.clear();
    _moduleCache.clear();
    _bridgeCache.clear();
    _scriptCache.clear();
    _sharedScopeVars.clear();
  }
}
