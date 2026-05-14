import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class TicketsScreen extends StatelessWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Soporte y Tickets", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
                    const SizedBox(height: 8),
                    const Text("Gestión de incidencias y soporte técnico.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(LucideIcons.plus),
                  label: const Text("Nuevo Ticket"),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                ),
              ],
            ).animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 32),
            Expanded(
              child: Card(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.ticket, size: 64, color: AppTheme.secondaryColor),
                      const SizedBox(height: 16),
                      const Text("No hay tickets activos", style: TextStyle(fontSize: 18, color: Colors.white70)),
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
