import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A simple theme provider that persists the selected theme to local storage.
///
/// This ensures that dark mode stays enabled even if the app is restarted or
/// if network-based preference syncing fails.
class ThemeProvider extends ChangeNotifier {
  static const _prefKey = 'isDarkMode';

  bool _isDarkMode = false;
  bool _isInitialized = false;
  bool _manuallySet = false;
  SharedPreferences? _prefs;

  bool get isDarkMode => _isDarkMode;
  bool get isInitialized => _isInitialized;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  /// Loads the persisted theme value from local storage.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs?.getBool(_prefKey) ?? false;
    _isInitialized = true;
    notifyListeners();
  }

  /// Persists the theme value and notifies listeners.
  Future<void> _save(bool value) async {
    _isDarkMode = value;
    _manuallySet = true;
    await _prefs?.setBool(_prefKey, value);
    notifyListeners();
  }

  /// Toggle theme and persist.
  Future<void> toggleTheme() async {
    await _save(!_isDarkMode);
  }

  /// Set theme as dark or light and persist.
  Future<void> setDarkMode(bool isDark) async {
    await _save(isDark);
  }

  /// Optionally initialize from remote preferences, but only if the user hasn't
  /// manually set a theme locally yet.
  void initializeFromPreferences(bool isDark) {
    if (!_isInitialized || !_manuallySet) {
      _isDarkMode = isDark;
      _isInitialized = true;
      notifyListeners();
    }
  }
}
