import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 崩溃日志条目
class CrashLogEntry {
  final DateTime time;
  final String type; // 'flutter' | 'zone' | 'isolate' | 'manual'
  final String error;
  final String? stackTrace;

  const CrashLogEntry({
    required this.time,
    required this.type,
    required this.error,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'type': type,
        'error': error,
        'stackTrace': stackTrace,
      };

  factory CrashLogEntry.fromJson(Map<String, dynamic> json) => CrashLogEntry(
        time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
        type: json['type'] as String? ?? 'unknown',
        error: json['error'] as String? ?? '',
        stackTrace: json['stackTrace'] as String?,
      );

  /// 完整格式化文本
  String toFullString() {
    final sb = StringBuffer();
    sb.writeln('========== 崩溃日志 ==========');
    sb.writeln('时间: ${time.toString().substring(0, 19)}');
    sb.writeln('类型: $type');
    sb.writeln('错误: $error');
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      sb.writeln('堆栈:');
      sb.writeln(stackTrace);
    }
    sb.writeln('==============================');
    return sb.toString();
  }
}

/// 崩溃日志服务（单例）
///
/// 功能：
/// 1. 捕获 Flutter 框架错误、Zone 错误、Isolate 错误
/// 2. 持久化到本地文件（Hive 不可用时降级文件系统）
/// 3. 自动复制到粘贴板
/// 4. 启动时检测上次崩溃并提示用户
class CrashLogService {
  CrashLogService._();
  static final CrashLogService instance = CrashLogService._();

  /// 最大保留崩溃日志条数
  static const int _maxEntries = 20;

  /// 崩溃日志文件名
  static const String _crashFileName = 'crash_logs.json';

  /// 内存中的崩溃日志列表
  final List<CrashLogEntry> _entries = [];

  /// 是否已初始化
  bool _initialized = false;

  /// 是否有新的崩溃日志待显示
  bool _hasNewCrash = false;

  /// 并发保护：防止多个错误同时触发 logCrash 导致并发文件写入
  bool _isLogging = false;

  /// 获取所有崩溃日志（只读副本）
  List<CrashLogEntry> get entries => List.unmodifiable(_entries);

  /// 是否有新的崩溃日志
  bool get hasNewCrash => _hasNewCrash;

  /// 标记崩溃日志已查看
  void markCrashViewed() => _hasNewCrash = false;

  /// 初始化：加载历史崩溃日志 + 注册错误捕获
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _loadCrashLogs();

    // 注册 Flutter 框架错误捕获
    FlutterError.onError = _onFlutterError;

    // 注册 Isolate 错误捕获（异步错误）
    Isolate.current.addErrorListener(RawReceivePort((dynamic pair) {
      final list = pair as List<dynamic>;
      final error = list.first.toString();
      final stack = list.last.toString();
      logCrash(error: error, stackTrace: stack, type: 'isolate');
    }).sendPort);

    // 注册 Zone 错误捕获（未捕获的异步错误）
    PlatformDispatcher.instance.onError = (error, stack) {
      logCrash(
        error: error.toString(),
        stackTrace: stack.toString(),
        type: 'zone',
      );
      return true;
    };
  }

  /// Flutter 框架错误回调
  void _onFlutterError(FlutterErrorDetails details) {
    logCrash(
      error: details.exceptionAsString(),
      stackTrace: details.stack?.toString(),
      type: 'flutter',
    );
    // 同时输出到控制台
    FlutterError.dumpErrorToConsole(details);
  }

  /// 记录一条崩溃日志
  ///
  /// 自动：
  /// 1. 加入内存列表（保留最近 _maxEntries 条）
  /// 2. 持久化到本地文件
  /// 3. 自动复制到粘贴板
  Future<void> logCrash({
    required String error,
    String? stackTrace,
    String type = 'manual',
  }) async {
    // 并发保护：防止多个错误同时触发导致文件写入冲突
    if (_isLogging) {
      if (kDebugMode) debugPrint('🔴 崩溃日志正在写入中，跳过并发记录: $error');
      return;
    }
    _isLogging = true;

    try {
      final entry = CrashLogEntry(
        time: DateTime.now(),
        type: type,
        error: error.length > 10000 ? '${error.substring(0, 10000)}...(已截断)' : error,
        stackTrace: stackTrace != null && stackTrace.length > 20000
            ? '${stackTrace.substring(0, 20000)}...(已截断)'
            : stackTrace,
      );

      _entries.add(entry);
      _hasNewCrash = true;

      // 限制条数
      if (_entries.length > _maxEntries) {
        _entries.removeRange(0, _entries.length - _maxEntries);
      }

      // 持久化
      await _saveCrashLogs();

      // 自动复制到粘贴板
      try {
        await Clipboard.setData(ClipboardData(text: entry.toFullString()));
      } catch (e) {
        if (kDebugMode) debugPrint('复制崩溃日志到粘贴板失败: $e');
      }

      if (kDebugMode) {
        debugPrint('🔴 崩溃已记录并复制到粘贴板:\n${entry.toFullString()}');
      }
    } finally {
      _isLogging = false;
    }
  }

  /// 手动记录错误（供外部调用）
  Future<void> recordError(Object error, StackTrace? stackTrace,
      {String type = 'manual'}) async {
    await logCrash(
      error: error.toString(),
      stackTrace: stackTrace?.toString(),
      type: type,
    );
  }

  /// 清空所有崩溃日志
  Future<void> clear() async {
    _entries.clear();
    _hasNewCrash = false;
    await _saveCrashLogs();
  }

  /// 导出所有崩溃日志为文本
  String exportLogs() {
    if (_entries.isEmpty) return '暂无崩溃日志';
    final sb = StringBuffer();
    sb.writeln('========== 崩溃日志导出 ==========');
    sb.writeln('导出时间: ${DateTime.now().toString().substring(0, 19)}');
    sb.writeln('日志条数: ${_entries.length}');
    sb.writeln('');
    for (final entry in _entries) {
      sb.writeln(entry.toFullString());
      sb.writeln('');
    }
    return sb.toString();
  }

  /// 加载历史崩溃日志
  Future<void> _loadCrashLogs() async {
    try {
      final file = await _getCrashFile();
      if (!file.existsSync()) return;

      final content = await file.readAsString();
      if (content.isEmpty) return;

      final json = jsonDecode(content);
      if (json is List) {
        for (final item in json) {
          if (item is Map<String, dynamic>) {
            _entries.add(CrashLogEntry.fromJson(item));
          }
        }
        if (_entries.isNotEmpty) {
          _hasNewCrash = true;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('加载崩溃日志失败: $e');
    }
  }

  /// 保存崩溃日志到文件
  Future<void> _saveCrashLogs() async {
    try {
      final file = await _getCrashFile();
      final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      if (kDebugMode) debugPrint('保存崩溃日志失败: $e');
    }
  }

  /// 获取崩溃日志文件
  Future<File> _getCrashFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$_crashFileName');
  }
}
