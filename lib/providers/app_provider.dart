import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isNoImageMode = false;
  String? _nickname;
  int _concurrentSearchLimit = 5;

  // 自定义主题颜色（默认使用原版 legado 的默认主题 - Light Blue）
  // 日间模式：primary = Light Blue 600, accent = Pink 800
  Color _dayPrimaryColor = const Color(0xFF0288D1); // Light Blue 600
  Color _dayAccentColor = const Color(0xFFAD1457); // Pink 800
  Color _dayBackgroundColor = const Color(0xFFFAFAFA); // Grey 50
  Color _daySurfaceColor = const Color(0xFFFFFFFF); // White
  Color _dayNavBarColor = const Color(0xFFF5F5F5);
  // 夜间模式
  Color _nightPrimaryColor = const Color(0xFF303030); // 深灰
  Color _nightAccentColor = const Color(0xFFE0E0E0); // 浅灰
  Color _nightBackgroundColor = const Color(0xFF424242); // Grey 800
  Color _nightSurfaceColor = const Color(0xFF303030); // Grey 700
  Color _nightNavBarColor = const Color(0xFF000000);

  // 背景图片设置
  String? _dayBackgroundImage;
  String? _nightBackgroundImage;
  int _dayBackgroundBlur = 0;
  int _nightBackgroundBlur = 0;

  // 底栏配置
  String _navBarLayoutMode = 'floating'; // floating, standard, sidebar
  String _navBarEffectMode = 'glass'; // solid, glass, frosted
  int _navBarOpacity = 72;
  int? _navBarBorderColor;
  int _navBarBorderAlpha = 100;
  String? _navBarWallpaperPath;
  String? _navBarSidebarBackgroundPath;
  String _navBarSidebarGravity = 'start'; // start, end

  ThemeMode get themeMode => _themeMode;
  bool get isNoImageMode => _isNoImageMode;
  String? get nickname => _nickname;
  int get concurrentSearchLimit => _concurrentSearchLimit;

  Color get dayPrimaryColor => _dayPrimaryColor;
  Color get dayAccentColor => _dayAccentColor;
  Color get dayBackgroundColor => _dayBackgroundColor;
  Color get daySurfaceColor => _daySurfaceColor;
  Color get dayNavBarColor => _dayNavBarColor;
  Color get nightPrimaryColor => _nightPrimaryColor;
  Color get nightAccentColor => _nightAccentColor;
  Color get nightBackgroundColor => _nightBackgroundColor;
  Color get nightSurfaceColor => _nightSurfaceColor;
  Color get nightNavBarColor => _nightNavBarColor;

  // 背景图片 getter
  String? get dayBackgroundImage => _dayBackgroundImage;
  String? get nightBackgroundImage => _nightBackgroundImage;
  int get dayBackgroundBlur => _dayBackgroundBlur;
  int get nightBackgroundBlur => _nightBackgroundBlur;

  // 底栏配置 getter
  String get navBarLayoutMode => _navBarLayoutMode;
  String get navBarEffectMode => _navBarEffectMode;
  int get navBarOpacity => _navBarOpacity;
  int? get navBarBorderColor => _navBarBorderColor;
  int get navBarBorderAlpha => _navBarBorderAlpha;
  String? get navBarWallpaperPath => _navBarWallpaperPath;
  String? get navBarSidebarBackgroundPath => _navBarSidebarBackgroundPath;
  String get navBarSidebarGravity => _navBarSidebarGravity;

  // 获取当前主题的背景图片
  String? get currentBackgroundImage {
    if (_themeMode == ThemeMode.dark) {
      return _nightBackgroundImage;
    } else if (_themeMode == ThemeMode.light) {
      return _dayBackgroundImage;
    } else {
      // 跟随系统
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark ? _nightBackgroundImage : _dayBackgroundImage;
    }
  }

  // 获取当前主题的背景模糊度
  int get currentBackgroundBlur {
    if (_themeMode == ThemeMode.dark) {
      return _nightBackgroundBlur;
    } else if (_themeMode == ThemeMode.light) {
      return _dayBackgroundBlur;
    } else {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark ? _nightBackgroundBlur : _dayBackgroundBlur;
    }
  }

  Color get currentNavBarColor {
    if (_themeMode == ThemeMode.dark) {
      return _nightNavBarColor;
    } else if (_themeMode == ThemeMode.light) {
      return _dayNavBarColor;
    }
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark
        ? _nightNavBarColor
        : _dayNavBarColor;
  }

  // 获取日间主题
  ThemeData get lightTheme {
    // 如果有背景图片，Scaffold 背景色设置为透明，这样背景图片才能显示
    final scaffoldBgColor = (_dayBackgroundImage != null && _dayBackgroundImage!.isNotEmpty)
        ? Colors.transparent
        : _dayBackgroundColor;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: _dayPrimaryColor,
        secondary: _dayAccentColor,
        surface: _daySurfaceColor,
        background: _dayBackgroundColor,
        onPrimary: _foregroundFor(_dayPrimaryColor),
        onSecondary: _foregroundFor(_dayAccentColor),
        onSurface: Colors.black87, // surface 色上的文字颜色
        onBackground: Colors.black87, // background 色上的文字颜色
        error: const Color(0xFFE53935),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: scaffoldBgColor,
      appBarTheme: AppBarTheme(
        backgroundColor: _dayPrimaryColor,
        foregroundColor: _foregroundFor(_dayPrimaryColor),
        titleTextStyle: TextStyle(
          color: _foregroundFor(_dayPrimaryColor),
          fontSize: 20,
          fontWeight: FontWeight.normal,
        ),
      ),
      switchTheme: _switchTheme(_dayAccentColor),
      checkboxTheme: _checkboxTheme(_dayAccentColor),
      radioTheme: _radioTheme(_dayAccentColor),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _dayAccentColor,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _dayNavBarColor,
        selectedItemColor: _dayAccentColor,
        unselectedItemColor: Colors.black54,
        elevation: 4,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _dayNavBarColor,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? _dayAccentColor
                : Colors.black54,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _dayPrimaryColor,
        foregroundColor: _foregroundFor(_dayPrimaryColor),
      ),
      // 确保文字主题正确
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.black87),
        bodyMedium: TextStyle(color: Colors.black87),
        bodySmall: TextStyle(color: Colors.black54),
        titleLarge: TextStyle(color: Colors.black87),
        titleMedium: TextStyle(color: Colors.black87),
        titleSmall: TextStyle(color: Colors.black87),
      ),
    );
  }

  // 获取夜间主题
  ThemeData get darkTheme {
    // 如果有背景图片，Scaffold 背景色设置为透明，这样背景图片才能显示
    final scaffoldBgColor = (_nightBackgroundImage != null && _nightBackgroundImage!.isNotEmpty)
        ? Colors.transparent
        : _nightBackgroundColor;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: _nightPrimaryColor,
        secondary: _nightAccentColor,
        surface: _nightSurfaceColor,
        background: _nightBackgroundColor,
        onPrimary: _foregroundFor(_nightPrimaryColor),
        onSecondary: _foregroundFor(_nightAccentColor),
        onSurface: Colors.white70, // surface 色上的文字颜色
        onBackground: Colors.white70, // background 色上的文字颜色
        error: const Color(0xFFE53935),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: scaffoldBgColor,
      appBarTheme: AppBarTheme(
        backgroundColor: _nightPrimaryColor,
        foregroundColor: _foregroundFor(_nightPrimaryColor),
        titleTextStyle: TextStyle(
          color: _foregroundFor(_nightPrimaryColor),
          fontSize: 20,
          fontWeight: FontWeight.normal,
        ),
      ),
      switchTheme: _switchTheme(_nightAccentColor),
      checkboxTheme: _checkboxTheme(_nightAccentColor),
      radioTheme: _radioTheme(_nightAccentColor),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _nightAccentColor,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _nightNavBarColor,
        selectedItemColor: _nightAccentColor,
        unselectedItemColor: Colors.white70,
        elevation: 4,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _nightNavBarColor,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? _nightAccentColor
                : Colors.white70,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _nightPrimaryColor,
        foregroundColor: _foregroundFor(_nightPrimaryColor),
      ),
      // 确保文字主题正确
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white70),
        bodyMedium: TextStyle(color: Colors.white70),
        bodySmall: TextStyle(color: Colors.white54),
        titleLarge: TextStyle(color: Colors.white),
        titleMedium: TextStyle(color: Colors.white),
        titleSmall: TextStyle(color: Colors.white70),
      ),
    );
  }

  AppProvider() {
    _loadThemeSettings();
  }

  Future<void> _loadThemeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _dayPrimaryColor = Color(prefs.getInt('dayPrimaryColor') ?? 0xFF0288D1);
    _dayAccentColor = Color(prefs.getInt('dayAccentColor') ?? 0xFFAD1457);
    _dayBackgroundColor = Color(prefs.getInt('dayBackgroundColor') ?? 0xFFFAFAFA);
    _daySurfaceColor = Color(prefs.getInt('daySurfaceColor') ?? 0xFFFFFFFF);
    _dayNavBarColor = Color(prefs.getInt('dayNavBarColor') ?? 0xFFF5F5F5);
    _nightPrimaryColor = Color(prefs.getInt('nightPrimaryColor') ?? 0xFF303030);
    _nightAccentColor = Color(prefs.getInt('nightAccentColor') ?? 0xFFE0E0E0);
    _nightBackgroundColor = Color(prefs.getInt('nightBackgroundColor') ?? 0xFF424242);
    _nightSurfaceColor = Color(prefs.getInt('nightSurfaceColor') ?? 0xFF303030);
    _nightNavBarColor = Color(prefs.getInt('nightNavBarColor') ?? 0xFF000000);

    // 加载背景图片设置
    _dayBackgroundImage = prefs.getString('dayBackgroundImage');
    _nightBackgroundImage = prefs.getString('nightBackgroundImage');
    _dayBackgroundBlur = prefs.getInt('dayBackgroundBlur') ?? 0;
    _nightBackgroundBlur = prefs.getInt('nightBackgroundBlur') ?? 0;

    // 加载底栏配置
    _navBarLayoutMode = prefs.getString('navBarLayoutMode') ?? 'floating';
    _navBarEffectMode = prefs.getString('navBarEffectMode') ?? 'glass';
    _navBarOpacity = prefs.getInt('navBarOpacity') ?? 72;
    final borderColorValue = prefs.getInt('navBarBorderColor');
    _navBarBorderColor = borderColorValue != null && borderColorValue != 0 ? borderColorValue : null;
    _navBarBorderAlpha = prefs.getInt('navBarBorderAlpha') ?? 100;
    _navBarWallpaperPath = prefs.getString('navBarWallpaperPath');
    _navBarSidebarBackgroundPath = prefs.getString('navBarSidebarBackgroundPath');
    _navBarSidebarGravity = prefs.getString('navBarSidebarGravity') ?? 'start';

    notifyListeners();
  }

  Future<void> setDayThemeColors({
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? navBarColor,
    String? backgroundImage,
    int? backgroundBlur,
  }) async {
    if (primaryColor != null) _dayPrimaryColor = primaryColor;
    if (accentColor != null) _dayAccentColor = accentColor;
    if (backgroundColor != null) _dayBackgroundColor = backgroundColor;
    if (surfaceColor != null) _daySurfaceColor = surfaceColor;
    if (navBarColor != null) _dayNavBarColor = navBarColor;
    if (backgroundImage != null) _dayBackgroundImage = backgroundImage.isEmpty ? null : backgroundImage;
    if (backgroundBlur != null) _dayBackgroundBlur = backgroundBlur;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dayPrimaryColor', _dayPrimaryColor.value);
    await prefs.setInt('dayAccentColor', _dayAccentColor.value);
    await prefs.setInt('dayBackgroundColor', _dayBackgroundColor.value);
    await prefs.setInt('daySurfaceColor', _daySurfaceColor.value);
    await prefs.setInt('dayNavBarColor', _dayNavBarColor.value);
    if (backgroundImage != null) {
      if (backgroundImage.isEmpty) {
        await prefs.remove('dayBackgroundImage');
      } else {
        await prefs.setString('dayBackgroundImage', backgroundImage);
      }
    }
    if (backgroundBlur != null) {
      await prefs.setInt('dayBackgroundBlur', backgroundBlur);
    }

    notifyListeners();
  }

  Future<void> setNightThemeColors({
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? navBarColor,
    String? backgroundImage,
    int? backgroundBlur,
  }) async {
    if (primaryColor != null) _nightPrimaryColor = primaryColor;
    if (accentColor != null) _nightAccentColor = accentColor;
    if (backgroundColor != null) _nightBackgroundColor = backgroundColor;
    if (surfaceColor != null) _nightSurfaceColor = surfaceColor;
    if (navBarColor != null) _nightNavBarColor = navBarColor;
    if (backgroundImage != null) _nightBackgroundImage = backgroundImage.isEmpty ? null : backgroundImage;
    if (backgroundBlur != null) _nightBackgroundBlur = backgroundBlur;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('nightPrimaryColor', _nightPrimaryColor.value);
    await prefs.setInt('nightAccentColor', _nightAccentColor.value);
    await prefs.setInt('nightBackgroundColor', _nightBackgroundColor.value);
    await prefs.setInt('nightSurfaceColor', _nightSurfaceColor.value);
    await prefs.setInt('nightNavBarColor', _nightNavBarColor.value);
    if (backgroundImage != null) {
      if (backgroundImage.isEmpty) {
        await prefs.remove('nightBackgroundImage');
      } else {
        await prefs.setString('nightBackgroundImage', backgroundImage);
      }
    }
    if (backgroundBlur != null) {
      await prefs.setInt('nightBackgroundBlur', backgroundBlur);
    }

    notifyListeners();
  }

  static Color _foregroundFor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }

  static SwitchThemeData _switchTheme(Color accent) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent.withValues(alpha: 0.5)
            : null,
      ),
    );
  }

  static CheckboxThemeData _checkboxTheme(Color accent) {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : null,
      ),
    );
  }

  static RadioThemeData _radioTheme(Color accent) {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : null,
      ),
    );
  }

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

  // 设置底栏配置
  Future<void> setNavBarConfig({
    String? layoutMode,
    String? effectMode,
    int? opacity,
    int? borderColor,
    int? borderAlpha,
    String? wallpaperPath,
    String? sidebarBackgroundPath,
    String? sidebarGravity,
  }) async {
    if (layoutMode != null) _navBarLayoutMode = layoutMode;
    if (effectMode != null) _navBarEffectMode = effectMode;
    if (opacity != null) _navBarOpacity = opacity;
    if (borderColor != null) _navBarBorderColor = borderColor;
    if (borderAlpha != null) _navBarBorderAlpha = borderAlpha;
    if (wallpaperPath != null) _navBarWallpaperPath = wallpaperPath.isEmpty ? null : wallpaperPath;
    if (sidebarBackgroundPath != null) _navBarSidebarBackgroundPath = sidebarBackgroundPath.isEmpty ? null : sidebarBackgroundPath;
    if (sidebarGravity != null) _navBarSidebarGravity = sidebarGravity;

    final prefs = await SharedPreferences.getInstance();
    if (layoutMode != null) await prefs.setString('navBarLayoutMode', layoutMode);
    if (effectMode != null) await prefs.setString('navBarEffectMode', effectMode);
    if (opacity != null) await prefs.setInt('navBarOpacity', opacity);
    if (borderColor != null) await prefs.setInt('navBarBorderColor', borderColor);
    if (borderAlpha != null) await prefs.setInt('navBarBorderAlpha', borderAlpha);
    if (wallpaperPath != null) {
      if (wallpaperPath.isEmpty) {
        await prefs.remove('navBarWallpaperPath');
      } else {
        await prefs.setString('navBarWallpaperPath', wallpaperPath);
      }
    }
    if (sidebarBackgroundPath != null) {
      if (sidebarBackgroundPath.isEmpty) {
        await prefs.remove('navBarSidebarBackgroundPath');
      } else {
        await prefs.setString('navBarSidebarBackgroundPath', sidebarBackgroundPath);
      }
    }
    if (sidebarGravity != null) await prefs.setString('navBarSidebarGravity', sidebarGravity);

    notifyListeners();
  }
}
