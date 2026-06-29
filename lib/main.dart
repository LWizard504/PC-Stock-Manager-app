import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/screens/login_screen.dart';
import 'package:pc_dev_flutter/ui/screens/launcher_screen.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';
import 'package:pc_dev_flutter/services/config.dart';
import 'package:pc_dev_flutter/services/offline_sync_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pc_dev_flutter/services/tray_service.dart';
import 'package:pc_dev_flutter/services/accent_color_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase with production URL and Anon Key
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Initialize OfflineSyncManager
  await OfflineSyncManager.instance.init();

  await windowManager.ensureInitialized();
  
  // Initialize system tray service
  await TrayService.instance.init();

  WindowOptions windowOptions = const WindowOptions(
    title: 'StockManager',
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    // Intercept window close to minimize to tray
    await windowManager.setPreventClose(true);
  });

  final accentNotifier = AccentColorNotifier();
  await accentNotifier.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider.value(value: accentNotifier),
      ],
      child: const StockManagerApp(),
    ),
  );
}

class StockManagerApp extends StatefulWidget {
  const StockManagerApp({super.key});

  @override
  State<StockManagerApp> createState() => _StockManagerAppState();
}

class _StockManagerAppState extends State<StockManagerApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    try {
      bool isPrevent = await windowManager.isPreventClose();
      if (isPrevent) {
        debugPrint('StockManagerApp: Window close prevented. Hiding window to system tray.');
        await windowManager.hide();
      }
    } catch (e) {
      debugPrint('StockManagerApp: Error hiding window on close: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final accentNotifier = Provider.of<AccentColorNotifier>(context);
    final accentColor = accentNotifier.accentColor;

    return MaterialApp(
      title: 'StockManager',
      debugShowCheckedModeBanner: false,
      locale: localeProvider.locale,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.backgroundDark,
        colorScheme: ColorScheme.dark(
          primary: accentColor,
          secondary: accentColor,
          surface: AppTheme.surfaceDark,
        ),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const LauncherScreen(),
    );
  }
}
