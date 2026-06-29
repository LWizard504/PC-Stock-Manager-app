import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccentColorNotifier extends ChangeNotifier {
  static const String _key = 'accent_color';

  static const List<Color> presetColors = [
    Color(0xFFEAB308), // Yellow
    Color(0xFF3B82F6), // Blue
    Color(0xFF10B981), // Emerald
    Color(0xFFF43F5E), // Rose
    Color(0xFF8B5CF6), // Violet
  ];

  Color _accentColor = presetColors[2];

  Color get accentColor => _accentColor;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_key);
    if (val != null) {
      _accentColor = Color(val);
      notifyListeners();
    }
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, color.toARGB32());
    notifyListeners();
  }
}
