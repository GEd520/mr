// C 原生加密对比测试
// 验证 quickjs/crypto/ 下的 C 实现输出与 Dart pointycastle 完全一致
//
// 测试策略：
// 1. 在 JS 中调用 __nativeCrypto.md5Native 等 C 原生函数
// 2. 在 Dart 中用 pointycastle/crypto 包计算相同输入
// 3. 比较两者输出是否字节级一致
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:convert';
import 'package:mr/services/native/js_engine.dart';

void main() {
  group('C 原生加密对比测试', () {
    late JsEngine jsEngine;

    setUpAll(() async {
      jsEngine = JsEngine.instance;
      await jsEngine.init();
    });

    test('MD5: C 原生 vs Dart crypto 包', () {
      const testCases = [
        '',
        'hello',
        'Hello, World!',
        '你好，世界！',
      ];

      for (final input in testCases) {
        final dartResult = crypto.md5.convert(utf8.encode(input)).toString();
        final jsResult = jsEngine.evaluate(
          '(function(){ var u8 = _strToU8(${_jsString(input)}); '
          'var r8 = __nativeCrypto.md5Native(u8); '
          'return _u8ToHex(r8); })()'
        ) as String;
        expect(jsResult, dartResult, reason: 'MD5("$input") 不一致');
      }
    });

    test('SHA1: C 原生 vs Dart crypto 包', () {
      const testCases = [
        '',
        'hello',
        'Hello, World!',
        '你好，世界！',
      ];

      for (final input in testCases) {
        final dartResult = crypto.sha1.convert(utf8.encode(input)).toString();
        final jsResult = jsEngine.evaluate(
          '(function(){ var u8 = _strToU8(${_jsString(input)}); '
          'var r8 = __nativeCrypto.sha1Native(u8); '
          'return _u8ToHex(r8); })()'
        ) as String;
        expect(jsResult, dartResult, reason: 'SHA1("$input") 不一致');
      }
    });

    test('SHA256: C 原生 vs Dart crypto 包', () {
      const testCases = [
        '',
        'hello',
        'Hello, World!',
        '你好，世界！',
      ];

      for (final input in testCases) {
        final dartResult = crypto.sha256.convert(utf8.encode(input)).toString();
        final jsResult = jsEngine.evaluate(
          '(function(){ var u8 = _strToU8(${_jsString(input)}); '
          'var r8 = __nativeCrypto.sha256Native(u8); '
          'return _u8ToHex(r8); })()'
        ) as String;
        expect(jsResult, dartResult, reason: 'SHA256("$input") 不一致');
      }
    });

    test('HMAC-SHA256: C 原生 vs Dart crypto 包', () {
      const testCases = [
        ('data', 'key'),
        ('Hello, World!', 'secret'),
        ('你好', '密钥'),
      ];

      for (final (data, key) in testCases) {
        final dartResult = crypto.Hmac(crypto.sha256, utf8.encode(key))
            .convert(utf8.encode(data))
            .toString();
        final jsResult = jsEngine.evaluate(
          '(function(){ '
          'var d = _strToU8(${_jsString(data)}); '
          'var k = _strToU8(${_jsString(key)}); '
          'var r8 = __nativeCrypto.hmacSHA256Native(d, k); '
          'return _u8ToHex(r8); })()'
        ) as String;
        expect(jsResult, dartResult, reason: 'HMAC-SHA256("$data", "$key") 不一致');
      }
    });

    test('AES-CBC-PKCS7 加解密: C 原生自洽', () {
      // 测试 AES 加密后解密能还原原文
      const testCases = [
        ('Hello, World!', '1234567890123456', '1234567890123456'),  // AES-128
        ('你好，世界！', '1234567890123456', '1234567890123456'),
      ];

      for (final (plaintext, key, iv) in testCases) {
        // 加密
        final cipherB64 = jsEngine.evaluate(
          '(function(){ '
          'var p = _strToU8(${_jsString(plaintext)}); '
          'var k = _strToU8(${_jsString(key)}); '
          'var iv = _strToU8(${_jsString(iv)}); '
          'var c = __nativeCrypto.aesEncryptNative(p, k, iv); '
          'return _u8ToB64(c); })()'
        ) as String;

        expect(cipherB64.isNotEmpty, true, reason: 'AES 加密失败');

        // 解密
        final decrypted = jsEngine.evaluate(
          '(function(){ '
          'var c = _b64ToU8(${_jsString(cipherB64)}); '
          'var k = _strToU8(${_jsString(key)}); '
          'var iv = _strToU8(${_jsString(iv)}); '
          'var p = __nativeCrypto.aesDecryptNative(c, k, iv); '
          'return _u8ToStr(p); })()'
        ) as String;

        expect(decrypted, plaintext, reason: 'AES 加解密不自洽');
      }
    });

    // ===== 外部测试向量：用 Node.js crypto 加密的数据验证 C 层解密 =====
    // Node.js 脚本：
    //   const crypto = require('crypto');
    //   const key = Buffer.from('NlgrYjYuRT5ic1hifSs9Tg==', 'base64');  // favcomic 的 key
    //   const iv = Buffer.from('36a9730ad6040653692cb06a2c879e2b', 'hex'); // favcomic 的 iv
    //   const cipher = crypto.createCipheriv('aes-128-cbc', key, iv);
    //   const ciphertext = Buffer.concat([cipher.update('Hello, World!'), cipher.final()]);
    //
    // 如果此测试失败 → C 层 AES 实现有 bug
    // 如果此测试通过 → 问题在 JS 侧参数传递（favcomic.js 的 result.slice 等）
    test('AES-CBC 外部测试向量: Node.js 加密 → C 原生解密', () {
      // Node.js 生成的测试向量
      const keyHex = '36582b62362e453e627358627d2b3d4e';      // NlgrYjYuRT5ic1hifSs9Tg== 解码
      const ivHex = '36a9730ad6040653692cb06a2c879e2b';      // favcomic 首张图片前 16 字节
      const ctHex = '9a57ecd85a5af5a63be360b0f6446096';       // Node.js 加密 "Hello, World!" 的密文
      const expectedPtHex = '48656c6c6f2c20576f726c6421';     // "Hello, World!" 的 hex

      final jsCode = '''
(function(){
  function hexToU8(hex) {
    var u8 = new Uint8Array(hex.length / 2);
    for (var i = 0; i < hex.length; i += 2) {
      u8[i/2] = parseInt(hex.substr(i, 2), 16);
    }
    return u8;
  }
  function u8ToHex(u8) {
    var hex = '';
    for (var i = 0; i < u8.length; i++) {
      hex += (u8[i] < 16 ? '0' : '') + u8[i].toString(16);
    }
    return hex;
  }

  var key = hexToU8('$keyHex');
  var iv = hexToU8('$ivHex');
  var ct = hexToU8('$ctHex');

  try {
    var pt = __nativeCrypto.aesDecryptNative(ct, key, iv);
    if (!pt) return JSON.stringify({error: 'aesDecryptNative returned null'});
    var ptU8 = pt instanceof ArrayBuffer ? new Uint8Array(pt) : pt;
    var ptHex = u8ToHex(ptU8);
    return JSON.stringify({
      expected: '$expectedPtHex',
      actual: ptHex,
      match: ptHex === '$expectedPtHex'
    });
  } catch (e) {
    return JSON.stringify({error: String(e), keyLen: key.length, ivLen: iv.length, ctLen: ct.length});
  }
})()
''';

      final result = jsEngine.evaluate(jsCode) as String;
      // 解析 JSON 结果
      final Map<String, dynamic> parsed = jsonDecode(result);

      if (parsed.containsKey('error')) {
        fail('C 层 AES 解密失败: ${parsed['error']}'
             ' (keyLen=${parsed['keyLen']}, ivLen=${parsed['ivLen']}, ctLen=${parsed['ctLen']})');
      }

      expect(parsed['match'], true,
          reason: 'C 层 AES 解密结果与 Node.js 不一致: '
                  'expected=${parsed['expected']}, actual=${parsed['actual']}');
    });

    test('AES-CBC 批量解密: aesDecryptFromBase64Batch', () {
      // 测试批量解密与逐条解密结果一致
      const testCases = [
        ('Hello, World!', '1234567890123456', '1234567890123456'),
        ('你好，世界！', '1234567890123456', '1234567890123456'),
        ('Batch AES Decrypt Test', '1234567890123456', '1234567890123456'),
      ];

      // 先加密所有测试数据
      final cipherList = <String>[];
      for (final (plaintext, key, iv) in testCases) {
        final cipherB64 = jsEngine.evaluate(
          '(function(){ '
          'var p = _strToU8(${_jsString(plaintext)}); '
          'var k = _strToU8(${_jsString(key)}); '
          'var iv = _strToU8(${_jsString(iv)}); '
          'var c = __nativeCrypto.aesEncryptNative(p, k, iv); '
          'return _u8ToB64(c); })()'
        ) as String;
        cipherList.add(cipherB64);
      }

      // 构建批量解密的 JS 调用
      final cipherArrayJs = '[${cipherList.map((c) => _jsString(c)).join(',')}]';
      final batchResult = jsEngine.evaluate(
        '(function(){ '
        'var arr = $cipherArrayJs; '
        'var key = ${_jsString(testCases.first.$2)}; '
        'var iv = ${_jsString(testCases.first.$3)}; '
        'var results = __nativeCrypto.aesDecryptFromBase64Batch(arr, key, iv); '
        'return JSON.stringify(results); })()'
      ) as String;

      // 解析批量结果
      final results = (batchResult.isNotEmpty)
          ? (jsonDecode(batchResult) as List)
          : <dynamic>[];

      expect(results.length, testCases.length,
          reason: '批量解密结果数量不匹配');
      for (var i = 0; i < testCases.length; i++) {
        expect(results[i], testCases[i].$1,
            reason: '批量解密第 $i 项不一致');
      }
    });
  });
}

/// 将 Dart 字符串转为 JS 字符串字面量（带引号）
String _jsString(String s) {
  final escaped = s
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r');
  return "'$escaped'";
}
