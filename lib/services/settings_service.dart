import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 应用级别的设置。
class SettingsService extends ChangeNotifier {
  SettingsService._();

  /// 全局单例，设置在整个 App 内共享。
  static final SettingsService instance = SettingsService._();

  static const String _themeKey = 'app_theme_mode';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /// 从本地恢复设置，App 启动时调一次。
  Future<void> restore() async {
    try {
      final String? raw = await _storage.read(key: _themeKey);
      if (raw != null) {
        for (final ThemeMode mode in ThemeMode.values) {
          if (mode.name == raw) {
            _themeMode = mode;
            break;
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 换主题模式，选择会存到本地。
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
    try {
      await _storage.write(key: _themeKey, value: mode.name);
    } catch (_) {}
  }

  /// 主题模式给人看的名字。
  static String labelOf(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };
}
