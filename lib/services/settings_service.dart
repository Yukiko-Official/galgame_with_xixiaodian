import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 应用级别的设置。
class SettingsService extends ChangeNotifier {
  SettingsService._();

  /// 全局单例，设置在整个 App 内共享。
  static final SettingsService instance = SettingsService._();

  static const String _themeKey = 'app_theme_mode';
  static const String _easterEggKey = 'app_easter_egg';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ThemeMode _themeMode = ThemeMode.system;

  /// 彩蛋解锁过没。连点五次版本号解锁一次，之后开关就一直留着。
  bool _easterEggUnlocked = false;

  /// 彩蛋现在是开着的没。
  bool _easterEgg = false;

  ThemeMode get themeMode => _themeMode;
  bool get easterEggUnlocked => _easterEggUnlocked;
  bool get easterEgg => _easterEgg;

  /// 西小电在界面上显示的名字，彩蛋开着就换个叫法。
  String get assistantName => _easterEgg ? '嬉笑癫' : '西小电';

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

    try {
      final String? raw = await _storage.read(key: _easterEggKey);
      if (raw != null && raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _easterEggUnlocked = decoded['unlocked'] == true;
          _easterEgg = decoded['on'] == true;
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

  /// 解锁彩蛋，顺便打开它。
  Future<void> unlockEasterEgg() async {
    _easterEggUnlocked = true;
    _easterEgg = true;
    notifyListeners();
    await _saveEasterEgg();
  }

  /// 开关彩蛋。
  Future<void> setEasterEgg(bool value) async {
    if (_easterEgg == value) {
      return;
    }
    _easterEgg = value;
    notifyListeners();
    await _saveEasterEgg();
  }

  Future<void> _saveEasterEgg() async {
    try {
      await _storage.write(
        key: _easterEggKey,
        value: jsonEncode(<String, bool>{
          'unlocked': _easterEggUnlocked,
          'on': _easterEgg,
        }),
      );
    } catch (_) {}
  }

  /// 主题模式给人看的名字。
  static String labelOf(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };
}
