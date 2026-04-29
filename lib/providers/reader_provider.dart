import 'package:flutter/material.dart';
import '../services/storage_service.dart';

enum PageMode { simulation, scroll, slide }

class ReaderProvider extends ChangeNotifier {
  PageMode _pageMode = PageMode.simulation;
  double _fontSize = 18.0;
  double _lineHeight = 1.5;
  Color _backgroundColor = const Color(0xFFFFF8E1);
  Color _textColor = Colors.black87;
  double _brightness = 1.0;
  bool _isNightMode = false;
  bool _initialized = false;

  PageMode get pageMode => _pageMode;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  Color get backgroundColor => _backgroundColor;
  Color get textColor => _textColor;
  double get brightness => _brightness;
  bool get isNightMode => _isNightMode;

  Future<void> loadFromStorage() async {
    if (_initialized) return;
    final config = StorageService.instance.getReaderConfig();
    if (config != null) {
      _fontSize = (config['fontSize'] as num?)?.toDouble() ?? 18.0;
      _lineHeight = (config['lineHeight'] as num?)?.toDouble() ?? 1.5;
      _brightness = (config['brightness'] as num?)?.toDouble() ?? 1.0;
      _isNightMode = config['isNightMode'] as bool? ?? false;
      final bgValue = config['backgroundColor'] as int?;
      if (bgValue != null) _backgroundColor = Color(bgValue);
      final modeIndex = config['pageMode'] as int?;
      if (modeIndex != null && modeIndex < PageMode.values.length) {
        _pageMode = PageMode.values[modeIndex];
      }
      if (_isNightMode) {
        _backgroundColor = const Color(0xFF1A1A1A);
        _textColor = Colors.white70;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _saveToStorage() async {
    await StorageService.instance.saveReaderConfig({
      'fontSize': _fontSize,
      'lineHeight': _lineHeight,
      'brightness': _brightness,
      'isNightMode': _isNightMode,
      'backgroundColor': _backgroundColor.value,
      'pageMode': _pageMode.index,
    });
  }

  void setPageMode(PageMode mode) {
    _pageMode = mode;
    _saveToStorage();
    notifyListeners();
  }

  void setFontSize(double size) {
    _fontSize = size;
    _saveToStorage();
    notifyListeners();
  }

  void setLineHeight(double height) {
    _lineHeight = height;
    _saveToStorage();
    notifyListeners();
  }

  void setBackgroundColor(Color color) {
    _backgroundColor = color;
    _saveToStorage();
    notifyListeners();
  }

  void setTextColor(Color color) {
    _textColor = color;
    notifyListeners();
  }

  void setBrightness(double value) {
    _brightness = value;
    _saveToStorage();
    notifyListeners();
  }

  void toggleNightMode() {
    _isNightMode = !_isNightMode;
    if (_isNightMode) {
      _backgroundColor = const Color(0xFF1A1A1A);
      _textColor = Colors.white70;
    } else {
      _backgroundColor = const Color(0xFFFFF8E1);
      _textColor = Colors.black87;
    }
    _saveToStorage();
    notifyListeners();
  }
}
