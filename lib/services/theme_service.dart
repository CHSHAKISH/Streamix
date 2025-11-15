import 'package:flutter/material.dart';

// This class will hold the app's current theme state
class ThemeService with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // Default to system theme

  ThemeMode get themeMode => _themeMode;

  void setTheme(ThemeMode themeMode) {
    _themeMode = themeMode;
    notifyListeners(); // This tells the app to rebuild with the new theme
  }
}