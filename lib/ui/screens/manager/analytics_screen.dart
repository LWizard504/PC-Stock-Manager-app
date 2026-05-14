import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Analíticas de Negocio", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
            const SizedBox(height: 8),
            const Text("Rendimiento detallado de sucursales y empleados.", style: TextStyle(color: Colors.white60, fontSize: 16)),
            const SizedBox(height: 32),
            Expanded(
              child: Card(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.barChart2, size: 64, color: AppTheme.accentColor),
                      const SizedBox(height: 16),
                      const Text("Módulo de analíticas avanzadas en construcción", style: TextStyle(fontSize: 18, color: Colors.white70)),
                    ],
                  ),
                ),
              ).animate().fadeIn().slideY(),
            ),
          ],
        ),
      ),
    );
  }
}
