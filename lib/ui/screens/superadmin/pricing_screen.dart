import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class PricingScreen extends StatelessWidget {
  const PricingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Pricing Engine", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
            const SizedBox(height: 8),
            const Text("Configura los planes de suscripción globales", style: TextStyle(color: Colors.white60, fontSize: 16)),
            const SizedBox(height: 48),
            Row(
              children: [
                _buildPricingCard("Básico", "9.99", ["1 Nodo", "Soporte Standard", "Updates Mensuales"], false, context),
                const SizedBox(width: 24),
                _buildPricingCard("Pro", "29.99", ["Nodos Ilimitados", "Soporte 24/7", "Updates Diarios", "Neural Chat"], true, context),
                const SizedBox(width: 24),
                _buildPricingCard("Enterprise", "99.99", ["Nodos Ilimitados", "Soporte Dedicado", "Infraestructura Propia"], false, context),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPricingCard(String title, String price, List<String> features, bool isPopular, BuildContext context) {
    return Expanded(
      child: Card(
        color: isPopular ? AppTheme.primaryColor.withOpacity(0.1) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: isPopular ? const BorderSide(color: AppTheme.primaryColor, width: 2) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(12)),
                  child: const Text("Más Popular", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("\$$price", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                  const Padding(padding: EdgeInsets.only(bottom: 8.0), child: Text("/mes", style: TextStyle(color: Colors.white54))),
                ],
              ),
              const SizedBox(height: 32),
              ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(children: [const Icon(LucideIcons.checkCircle2, color: AppTheme.accentColor, size: 20), const SizedBox(width: 12), Text(f)]),
              )).toList(),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPopular ? AppTheme.primaryColor : AppTheme.surfaceLight,
                  ),
                  child: const Text("Editar Plan"),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn().slideY(),
    );
  }
}
