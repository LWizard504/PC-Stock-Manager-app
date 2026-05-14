import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class SalesHistoryScreen extends StatelessWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Historial de Ventas", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
            const SizedBox(height: 8),
            const Text("Registro global de todas las transacciones.", style: TextStyle(color: Colors.white60, fontSize: 16)),
            const SizedBox(height: 32),
            Expanded(
              child: Card(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.history, size: 64, color: Colors.white54),
                      const SizedBox(height: 16),
                      const Text("Cargando base de datos de ventas...", style: TextStyle(fontSize: 18, color: Colors.white70)),
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
