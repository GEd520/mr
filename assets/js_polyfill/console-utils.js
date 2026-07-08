/**
 * console-utils.js — Console 日志提取与恢复工具
 *
 * 从 js_engine.dart 中剥离的内联 JS 代码。
 * 提供：
 *   - __flushConsoleLogs()：提取并清空 console 日志，返回 JSON 字符串
 *   - __reinjectConsole()：当 console 被用户代码覆盖时重新注入
 */

// ===== 提取 console 日志（提取后清空）=====
// 返回值：
//   - JSON 字符串（日志数组）
//   - "NEED_REINJECT"：console 被覆盖，需要重新注入
//   - "[]" 或 "undefined"：无日志
function __flushConsoleLogs() {
  var logs = [];
  if (typeof __consoleLogs !== 'undefined' && __consoleLogs.length > 0) {
    logs = __consoleLogs.slice();
    __consoleLogs.length = 0;
  } else if (typeof console !== 'undefined' && typeof console._getLogs === 'function') {
    logs = console._getLogs();
    if (console._clearLogs) console._clearLogs();
  } else if (typeof console === 'undefined' || typeof console._getLogs !== 'function') {
    return 'NEED_REINJECT';
  }
  return JSON.stringify(logs);
}

// ===== 重新注入 console（被用户代码覆盖后恢复）=====
// 关键：直接复用全局 __consoleLogs（由 java-bridge.js 顶层 var __consoleLogs = [] 声明），
// 不创建局部变量。原因：
//   1. __flushConsoleLogs 优先检查全局 __consoleLogs，若 reinject 用局部变量遮蔽，
//      则 reinject 后新 console.log 写入局部数组，但 flush 仍读全局旧数组，
//      导致 reinject 后的日志要等 reinject 前的旧日志被 flush 清空后才能被取出（多一次延迟）。
//   2. 若 reinject 前全局 __consoleLogs 还有未提取日志，复用全局可保留这些日志不丢失。
function __reinjectConsole() {
  if (typeof __consoleLogs === 'undefined') globalThis.__consoleLogs = [];
  else __consoleLogs.length = 0;  // 清空旧日志（被覆盖前的 console.log 输出已无法恢复，避免与新日志混合）
  globalThis.console = {
    log: function() { var msg = Array.from(arguments).join(' '); __consoleLogs.push({level: 'log', msg: msg}); },
    warn: function() { var msg = Array.from(arguments).join(' '); __consoleLogs.push({level: 'warn', msg: msg}); },
    error: function() { var msg = Array.from(arguments).join(' '); __consoleLogs.push({level: 'error', msg: msg}); },
    info: function() { var msg = Array.from(arguments).join(' '); __consoleLogs.push({level: 'info', msg: msg}); },
    debug: function() { var msg = Array.from(arguments).join(' '); __consoleLogs.push({level: 'debug', msg: msg}); },
    // 补齐 _getLogs / _clearLogs，与初始 console（java-bridge.js）对齐，
    // 否则 __flushConsoleLogs 检测到 console._getLogs 非 function 会返回 NEED_REINJECT 陷入循环。
    _getLogs: function() { return __consoleLogs.slice(); },
    _clearLogs: function() { __consoleLogs.length = 0; },
  };
}
