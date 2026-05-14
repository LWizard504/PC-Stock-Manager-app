import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final _supabase = Supabase.instance.client;
  late Future<Map<String, dynamic>> _managerDataFuture;

  @override
  void initState() {
    super.initState();
    _managerDataFuture = _fetchManagerData();
  }

  Future<Map<String, dynamic>> _fetchManagerData() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      // 1. Sales Today
      final salesResponse = await _supabase.from('sales').select('total').gte('created_at', todayStart);
      final double totalToday = (salesResponse as List).fold(0, (sum, item) => sum + (item['total'] as num).toDouble());
      final int countToday = salesResponse.length;

      // 2. Open Sessions
      final sessionsResponse = await _supabase.from('staff_sessions').select('id').isFilter('ended_at', null);
      final int activeSessions = (sessionsResponse as List).length;

      // 3. Stock Alertas
      final inventoryResponse = await _supabase.from('inventory').select('quantity').lt('quantity', 10);
      final int stockAlerts = (inventoryResponse as List).length;

      // 4. Top Products (Simulated based on products table for now)
      final productsResponse = await _supabase.from('products').select('name, price').limit(5);

      return {
        'totalToday': totalToday,
        'countToday': countToday,
        'activeSessions': activeSessions,
        'stockAlerts': stockAlerts,
        'topProducts': productsResponse,
      };
    } catch (e) {
      return {
        'totalToday': 0.0,
        'countToday': 0,
        'activeSessions': 0,
        'stockAlerts': 0,
        'topProducts': [],
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _managerDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.red));
          }

          final data = snapshot.data ?? {};
          final topProducts = data['topProducts'] as List<dynamic>? ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Gestión Operativa", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text("Monitoreo en tiempo real de sucursal.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ).animate().fadeIn().slideY(begin: -0.2),
                const SizedBox(height: 48),
                
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    SizedBox(width: 300, child: _buildStatCard("Ventas de Hoy", "\$${data['totalToday'].toStringAsFixed(2)}", "${data['countToday']} transacciones", LucideIcons.trendingUp, Colors.red)),
                    SizedBox(width: 300, child: _buildStatCard("Cajas Activas", data['activeSessions'].toString(), "Personal en turno", LucideIcons.monitorSmartphone, AppTheme.primaryColor)),
                    SizedBox(width: 300, child: _buildStatCard("Alertas de Stock", data['stockAlerts'].toString(), "Productos bajo el mínimo", LucideIcons.packageOpen, Colors.orangeAccent)),
                  ],
                ),
                const SizedBox(height: 32),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 800;
                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 1, child: _buildTopProductsCard(topProducts)),
                          const SizedBox(width: 24),
                          Expanded(flex: 1, child: _buildEmployeeStatusCard()),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildTopProductsCard(topProducts),
                          const SizedBox(height: 24),
                          _buildEmployeeStatusCard(),
                        ],
                      );
                    }
                  }
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, IconData icon, Color color) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: [color.withOpacity(0.1), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(title, style: const TextStyle(color: Colors.white70, fontSize: 16)), Icon(icon, color: color)],
            ),
            const SizedBox(height: 16),
            Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildTopProductsCard(List<dynamic> products) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Productos del Inventario", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (products.isEmpty)
              const Text("Sin datos de inventario")
            else
              ...products.map((p) => _buildProductRow(p['name'], "\$${p['price']}", 0.8)).toList(),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _buildProductRow(String name, String value, double percent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(name), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percent,
            backgroundColor: AppTheme.surfaceLight,
            color: Colors.red,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Estado de Sesiones", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _buildEmployeeItem("Caja Principal", "Activa", "Online", true),
            _buildEmployeeItem("Caja Secundaria", "Inactiva", "Offline", false),
            _buildEmployeeItem("Administración", "Activa", "Online", true),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildEmployeeItem(String name, String role, String status, bool isOnline) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.red.withOpacity(0.1),
            child: Icon(LucideIcons.user, color: isOnline ? Colors.red : Colors.white24, size: 16),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(role, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOnline ? Colors.red.withOpacity(0.1) : Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(status, style: TextStyle(color: isOnline ? Colors.red : Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
