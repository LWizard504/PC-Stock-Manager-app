import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  static TrayService get instance => _instance;

  Future<void> init() async {
    try {
      debugPrint('TrayService: Initializing system tray...');
      
      // Set the tray icon - using the native resource app_icon.ico on Windows
      String iconPath = 'windows/runner/resources/app_icon.ico';
      if (Platform.isMacOS || Platform.isLinux) {
        iconPath = 'windows/runner/resources/app_icon.png';
      }
      
      await trayManager.setIcon(iconPath);
      
      // Configure standard context menu items
      List<MenuItem> items = [
        MenuItem(
          key: 'show_window',
          label: 'Mostrar StockManager',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'Salir',
        ),
      ];
      
      await trayManager.setContextMenu(Menu(items: items));
      trayManager.addListener(this);
      
      debugPrint('TrayService: System tray successfully configured.');
    } catch (e) {
      debugPrint('TrayService: Error initializing system tray: $e');
    }
  }

  @override
  void onTrayIconClick() async {
    debugPrint('TrayService: Tray icon clicked.');
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('TrayService: Error showing window on tray click: $e');
    }
  }

  @override
  void onTrayIconRightClick() async {
    debugPrint('TrayService: Tray icon right-clicked.');
    try {
      await trayManager.popUpContextMenu();
    } catch (e) {
      debugPrint('TrayService: Error popping up tray menu: $e');
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    debugPrint('TrayService: Tray menu item clicked: ${menuItem.key}');
    if (menuItem.key == 'show_window') {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        debugPrint('TrayService: Error focusing window: $e');
      }
    } else if (menuItem.key == 'exit_app') {
      try {
        debugPrint('TrayService: Exiting application completely.');
        // Disable prevent close so the windowManager actually terminates the app
        await windowManager.setPreventClose(false);
        await windowManager.close();
      } catch (e) {
        debugPrint('TrayService: Error closing application: $e');
        exit(0);
      }
    }
  }
}
