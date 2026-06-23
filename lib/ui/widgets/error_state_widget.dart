import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ErrorStateWidget extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ErrorStateWidget({
    super.key,
    this.message = 'Error al cargar datos',
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyStateWidget extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyStateWidget({
    super.key,
    this.message = 'No hay datos disponibles',
    this.icon = LucideIcons.inbox,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white.withOpacity(0.03)),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white24, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
