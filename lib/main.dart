import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase with production URL and Anon Key
  await Supabase.initialize(
    url: 'https://fctewfmsofdcqrwlxoyo.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjdGV3Zm1zb2ZkY3Fyd2x4b3lvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3NDYzNDUsImV4cCI6MjA5MjMyMjM0NX0.efBvCsV_hfUYWskDoVmc5PPEB97RoCsDkgctj7X8g4g',
  );

  runApp(const StockManagerApp());
}

class StockManagerApp extends StatelessWidget {
  const StockManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockManager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.backgroundDark,
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.primaryColor,
          secondary: AppTheme.secondaryColor,
          surface: AppTheme.surfaceDark,
        ),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
