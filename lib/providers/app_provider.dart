import 'package:flutter/material.dart';

class AppProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isNoImageMode = false;
  String? _nickname;
  int _concurrentSearchLimit = 5;

  ThemeMode get themeMode => _themeMode;
  bool get isNoImageMode => _isNoImageMode;
  String? get nickname => _nickname;
  int get concurrentSearchLimit => _concurrentSearchLimit;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void toggleNoImageMode() {
    _isNoImageMode = !_isNoImageMode;
    notifyListeners();
  }

  void setNickname(String name) {
    _nickname = name;
    notifyListeners();
  }

  void setConcurrentSearchLimit(int limit) {
    _concurrentSearchLimit = limit;
    notifyListeners();
  }
}
