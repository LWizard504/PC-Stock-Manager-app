import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.downloadCloud, size: 80, color: AppTheme.primaryColor),
            const SizedBox(height: 24),
            Text("Binarios y Descargas", style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 16),
            const Text("Sube y gestiona las versiones de StockManager Desktop y Android.", style: TextStyle(color: Colors.white54)),
          ],
        ).animate().fadeIn().slideY(),
      ),
    );
  }
}
