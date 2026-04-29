import 'dart:convert';
import 'dart:typed_data';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'js_engine.dart';

enum RuleType { xpath, jsonPath, regex, jsoup, js }

class SourceRule {
  final String rule;
  final RuleType type;
  final List<String> steps;

  SourceRule({
    required this.rule,
    required this.type,
    this.steps = const [],
  });

  factory SourceRule.parse(String ruleStr) {
    if (ruleStr.isEmpty) {
      return SourceRule(rule: '', type: RuleType.jsoup);
    }

    final steps = ruleStr.split('##').where((s) => s.isNotEmpty).toList();
    RuleType type = RuleType.jsoup;

    for (final step in steps) {
      if (step.startsWith('//') || step.startsWith('./')) {
        type = RuleType.xpath;
        break;
      } else if (step.startsWith('\$.')) {
        type = RuleType.jsonPath;
        break;
      } else if (step.startsWith(':')) {
        type = RuleType.js;
        break;
      } else if (RegExp(r'^@css:').hasMatch(step)) {
        type = RuleType.jsoup;
        break;
      }
    }

    return SourceRule(rule: ruleStr, type: type, steps: steps);
  }
}

class AnalyzeRule {
  dynamic _content;
  String? _baseUrl;
  bool _isJson = false;
  dom.Document? _document;

  AnalyzeRule setContent(dynamic content, {String? baseUrl}) {
    _content = content;
    _baseUrl = baseUrl;

    if (content is String) {
      _isJson = _isJsonContent(content);
      if (!_isJson) {
        _document = html_parser.parse(content);
      }
    } else if (content is dom.Document) {
      _document = content;
      _isJson = false;
    } else if (content is dom.Element) {
      _document = html_parser.parse(content.outerHtml);
      _isJson = false;
    } else {
      _isJson = true;
    }

    return this;
  }

  AnalyzeRule setBaseUrl(String? baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  bool _isJsonContent(String content) {
    final trimmed = content.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  String? getString(String ruleStr) {
    if (ruleStr.isEmpty) return null;

    final rule = SourceRule.parse(ruleStr);
    dynamic result = _content;

    for (final step in rule.steps) {
      result = _applyStep(result, step, rule.type);
      if (result == null) return null;
    }

    return _toString(result);
  }

  List<String> getStringList(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    final rule = SourceRule.parse(ruleStr);
    dynamic result = _content;

    for (final step in rule.steps) {
      result = _applyStep(result, step, rule.type, isList: true);
      if (result == null) return [];
    }

    return _toStringList(result);
  }

  List<Map<String, dynamic>> getMapList(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    final rule = SourceRule.parse(ruleStr);
    dynamic result = _content;

    for (final step in rule.steps) {
      result = _applyStep(result, step, rule.type, isList: true);
      if (result == null) return [];
    }

    return _toMapList(result);
  }

  dynamic _applyStep(dynamic content, String step, RuleType type, {bool isList = false}) {
    if (step.isEmpty) return content;

    if (step.startsWith('@css:')) {
      return _applyCssSelector(content, step.substring(5), isList: isList);
    }

    if (step.startsWith('@xpath:')) {
      return _applyXPath(content, step.substring(7), isList: isList);
    }

    if (step.startsWith('@json:')) {
      return _applyJsonPath(content, step.substring(6), isList: isList);
    }

    if (step.startsWith('@js:')) {
      return _applyJs(content, step.substring(4));
    }

    if (step.startsWith(':')) {
      return _applyJs(content, step.substring(1));
    }

    switch (type) {
      case RuleType.xpath:
        return _applyXPath(content, step, isList: isList);
      case RuleType.jsonPath:
        return _applyJsonPath(content, step, isList: isList);
      case RuleType.jsoup:
        return _applyCssSelector(content, step, isList: isList);
      case RuleType.js:
        return _applyJs(content, step);
      case RuleType.regex:
        return _applyRegex(content, step, isList: isList);
    }
  }

  dynamic _applyCssSelector(dynamic content, String selector, {bool isList = false}) {
    dom.Element? element;

    if (content is dom.Document) {
      element = content.body;
    } else if (content is dom.Element) {
      element = content;
    } else if (content is String) {
      final doc = html_parser.parse(content);
      element = doc.body;
    }

    if (element == null) return null;

    if (selector.startsWith('@')) {
      final attrName = selector.substring(1);
      if (isList) {
        return element.querySelectorAll('*').map((e) => e.attributes[attrName] ?? '').toList();
      }
      return element.attributes[attrName] ?? element.querySelector('*')?.attributes[attrName] ?? '';
    }

    if (selector == 'text' || selector == 'text()') {
      if (isList) {
        return element.querySelectorAll('*').map((e) => e.text.trim()).toList();
      }
      return element.text.trim();
    }

    if (selector == 'html' || selector == 'html()') {
      if (isList) {
        return element.querySelectorAll('*').map((e) => e.innerHtml).toList();
      }
      return element.innerHtml;
    }

    if (selector == 'outerHtml') {
      if (isList) {
        return element.querySelectorAll('*').map((e) => e.outerHtml).toList();
      }
      return element.outerHtml;
    }

    if (isList) {
      return element.querySelectorAll(selector).toList();
    }

    return element.querySelector(selector);
  }

  dynamic _applyXPath(dynamic content, String xpath, {bool isList = false}) {
    if (content is! String) {
      if (content is dom.Document) {
        content = content.outerHtml;
      } else if (content is dom.Element) {
        content = content.outerHtml;
      } else {
        return null;
      }
    }

    try {
      final results = <String>[];
      final htmlStr = content as String;
      
      if (xpath.contains('@')) {
        final attrMatch = RegExp(r'@(\w+)').firstMatch(xpath);
        if (attrMatch != null) {
          final attrName = attrMatch.group(1)!;
          final pattern = RegExp('$attrName=["\']([^"\']*)["\']', caseSensitive: false);
          final matches = pattern.allMatches(htmlStr);
          for (final m in matches) {
            results.add(m.group(1) ?? '');
          }
        }
      } else if (xpath.contains('text()')) {
        final tagMatch = RegExp(r'/(\w+)\[').firstMatch(xpath);
        if (tagMatch != null) {
          final tagName = tagMatch.group(1)!;
          final pattern = RegExp('<$tagName[^>]*>([^<]*)</$tagName>', caseSensitive: false);
          final matches = pattern.allMatches(htmlStr);
          for (final m in matches) {
            results.add(m.group(1)?.trim() ?? '');
          }
        } else {
          final textPattern = RegExp(r'>([^<]+)<');
          final matches = textPattern.allMatches(htmlStr);
          for (final m in matches) {
            final text = m.group(1)?.trim();
            if (text != null && text.isNotEmpty) {
              results.add(text);
            }
          }
        }
      } else {
        final tagMatch = RegExp(r'/(\w+)').firstMatch(xpath);
        if (tagMatch != null) {
          final tagName = tagMatch.group(1)!;
          final pattern = RegExp('<$tagName[^>]*>(.*?)</$tagName>', caseSensitive: false, dotAll: true);
          final matches = pattern.allMatches(htmlStr);
          for (final m in matches) {
            results.add(m.group(1)?.trim() ?? '');
          }
        }
      }

      if (isList) {
        return results;
      }
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      return null;
    }
  }

  dynamic _applyJsonPath(dynamic content, String jsonPath, {bool isList = false}) {
    if (content is String) {
      try {
        content = json.decode(content);
      } catch (_) {
        return null;
      }
    }

    if (content is! Map && content is! List) {
      return null;
    }

    final path = jsonPath.replaceAll('\$.', '').split('.');
    dynamic current = content;

    for (final key in path) {
      if (key.isEmpty) continue;

      if (current is Map) {
        current = current[key];
      } else if (current is List && key == '*') {
        return current;
      } else if (current is List) {
        final index = int.tryParse(key);
        if (index != null && index < current.length) {
          current = current[index];
        } else {
          current = current.map((item) {
            if (item is Map) return item[key];
            return null;
          }).toList();
        }
      } else {
        return null;
      }
    }

    return current;
  }

  dynamic _applyJs(dynamic content, String jsCode) async {
    try {
      final result = await JsEngine.instance.processJsRule(
        content?.toString() ?? '',
        jsCode,
        baseUrl: _baseUrl,
      );
      return result;
    } catch (e) {
      return null;
    }
  }

  dynamic _applyRegex(dynamic content, String pattern, {bool isList = false}) {
    final str = content.toString();
    final regex = RegExp(pattern, multiLine: true, dotAll: true);

    if (isList) {
      return regex.allMatches(str).map((m) {
        if (m.groupCount > 0) {
          return m.group(1) ?? m.group(0) ?? '';
        }
        return m.group(0) ?? '';
      }).toList();
    }

    final match = regex.firstMatch(str);
    if (match != null) {
      if (match.groupCount > 0) {
        return match.group(1) ?? match.group(0) ?? '';
      }
      return match.group(0) ?? '';
    }
    return null;
  }

  String? _toString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is dom.Element) return value.text.trim();
    if (value is List) return value.isNotEmpty ? _toString(value.first) : null;
    return value.toString();
  }

  List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is String) return [value];
    if (value is List) {
      return value.map((e) => _toString(e) ?? '').where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> _toMapList(dynamic value) {
    if (value == null) return [];
    if (value is Map) return [Map<String, dynamic>.from(value)];
    if (value is List) {
      return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }
}
