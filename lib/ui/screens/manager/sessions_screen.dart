import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Sesiones de Empleados", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
            const SizedBox(height: 8),
            const Text("Monitorea entradas, salidas y turnos.", style: TextStyle(color: Colors.white60, fontSize: 16)),
            const SizedBox(height: 32),
            Expanded(
              child: Card(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.clock, size: 64, color: AppTheme.secondaryColor),
                      const SizedBox(height: 16),
                      const Text("Monitoreo de tiempo y asistencia no configurado", style: TextStyle(fontSize: 18, color: Colors.white70)),
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
