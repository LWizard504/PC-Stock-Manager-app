import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParticlePreferences {
  static const _keyEnabled = 'particles_enabled';
  static const _keyPrimaryColor = 'particles_primary_color';
  static const _keySecondaryColor = 'particles_secondary_color';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? true;
  }

  static Future<Color> getPrimaryColor() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_keyPrimaryColor);
    return val != null ? Color(val) : Colors.white;
  }

  static Future<Color> getSecondaryColor() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_keySecondaryColor);
    return val != null ? Color(val) : const Color(0xFF6366F1);
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
  }

  static Future<void> setPrimaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPrimaryColor, color.toARGB32());
  }

  static Future<void> setSecondaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySecondaryColor, color.toARGB32());
  }
}
