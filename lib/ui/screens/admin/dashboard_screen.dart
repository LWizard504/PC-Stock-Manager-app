import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _supabase = Supabase.instance.client;
  late Future<Map<String, dynamic>> _adminDataFuture;

  @override
  void initState() {
    super.initState();
    _adminDataFuture = _fetchAdminData();
  }

  Future<Map<String, dynamic>> _fetchAdminData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("No auth");

      final salesResponse = await _supabase.from('sales').select('total_amount');
      final double totalRevenue = (salesResponse as List).fold(0, (sum, item) => sum + (item['total_amount'] as num).toDouble());
      final int totalSalesCount = salesResponse.length;

      final inventoryResponse = await _supabase.from('inventory').select('quantity').lt('quantity', 5);
      final int lowStockCount = (inventoryResponse as List).length;

      final profilesResponse = await _supabase.from('profiles').select('id').inFilter('role', ['manager', 'employee', 'it']);
      final int employeeCount = (profilesResponse as List).length;

      // Resilient recent sales fetch
      final recentSalesResponse = await _supabase
          .from('sales')
          .select('id, total_amount, created_at, profiles!inner(*)')
          .order('created_at', ascending: false)
          .limit(5);

      return {
        'totalRevenue': totalRevenue,
        'salesCount': totalSalesCount,
        'lowStockCount': lowStockCount,
        'employeeCount': employeeCount,
        'recentSales': recentSalesResponse,
      };
    } catch (e) {
      return {
        'totalRevenue': 0.0,
        'salesCount': 0,
        'lowStockCount': 0,
        'employeeCount': 0,
        'recentSales': [],
      };
    }
  }

  String _getDisplayName(dynamic user) {
    if (user == null) return 'Usuario';
    String name = user['full_name'] ?? '';
    if (name.isEmpty) {
      final first = user['first_name'] ?? '';
      final last = user['last_name'] ?? '';
      name = '$first $last'.trim();
    }
    return name.isEmpty ? 'Operador' : name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _adminDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.red));
          }

          final data = snapshot.data ?? {};
          final recentSales = data['recentSales'] as List<dynamic>? ?? [];

          return SingleChildScrollView(
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
                        Text("Dashboard Administrativo", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text("Gestión operacional de sucursal.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => setState(() { _adminDataFuture = _fetchAdminData(); }),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text("Actualizar"),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceLight, foregroundColor: Colors.white),
                    ),
                  ],
                ).animate().fadeIn().slideY(begin: -0.2),
                const SizedBox(height: 48),
                
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    SizedBox(width: 300, child: _buildStatCard("Ingresos Totales", "\$${NumberFormat("#,##0.00").format(data['totalRevenue'])}", "Ventas acumuladas", LucideIcons.dollarSign, Colors.red)),
                    SizedBox(width: 300, child: _buildStatCard("Personal", data['employeeCount'].toString(), "Nodos humanos activos", LucideIcons.users, AppTheme.primaryColor)),
                    SizedBox(width: 300, child: _buildStatCard("Inventario Bajo", data['lowStockCount'].toString(), "Productos críticos", LucideIcons.alertTriangle, Colors.orangeAccent)),
                  ],
                ),
                const SizedBox(height: 32),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 800;
                    return isDesktop 
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 2, child: _buildRevenueChart(context)), const SizedBox(width: 24), Expanded(flex: 1, child: _buildRecentActivity(recentSales))])
                      : Column(children: [_buildRevenueChart(context), const SizedBox(height: 24), _buildRecentActivity(recentSales)]);
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
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: [color.withOpacity(0.1), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(color: Colors.white70, fontSize: 16)), Icon(icon, color: color)]),
            const SizedBox(height: 16),
            Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildRevenueChart(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Proyección de Ventas", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(height: 300, child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(LucideIcons.barChart, size: 64, color: Colors.red), const SizedBox(height: 16), Text("Analítica operacional cargando...", style: TextStyle(color: Colors.white.withOpacity(0.5)))]))),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _buildRecentActivity(List<dynamic> sales) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Últimas Transacciones", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (sales.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text("Sin transacciones detectadas", style: TextStyle(color: Colors.white24)))
            else ...sales.map((sale) {
              final date = DateTime.parse(sale['created_at']);
              final employeeName = _getDisplayName(sale['profiles']);
              return _buildActivityItem("Venta # ${sale['id'].toString().substring(0, 4)}", "\$${sale['total_amount'].toStringAsFixed(2)}", "${DateFormat('HH:mm').format(date)} - $employeeName", true);
            }).toList(),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildActivityItem(String title, String amount, String time, bool isPositive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(10)), child: Icon(LucideIcons.shoppingBag, size: 16, color: isPositive ? Colors.red : Colors.white54)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w500)), Text(time, style: const TextStyle(color: Colors.white54, fontSize: 12))])),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}
