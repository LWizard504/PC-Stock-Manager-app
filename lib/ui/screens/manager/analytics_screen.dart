import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  double _totalRevenue = 0.0;
  int _transactionCount = 0;
  double _averageTicket = 0.0;
  Map<String, double> _salesBySeller = {};
  Map<String, double> _salesByBranch = {};

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final profile = await _supabase
            .from('profiles')
            .select('tenant_id')
            .eq('id', user.id)
            .single();

        final tenantId = profile['tenant_id'];
        if (tenantId != null) {
          final data = await _supabase
              .from('sales')
              .select('total, profiles!seller_id(full_name), branches!branch_id(name)')
              .eq('tenant_id', tenantId);

          final salesList = List<Map<String, dynamic>>.from(data);
          
          double revenue = 0.0;
          Map<String, double> sellerSales = {};
          Map<String, double> branchSales = {};

          for (var sale in salesList) {
            final total = double.tryParse(sale['total'].toString()) ?? 0.0;
            revenue += total;

            final seller = sale['profiles']?['full_name'] ?? 'Unknown';
            final branch = sale['branches']?['name'] ?? 'Primary Branch';

            sellerSales[seller] = (sellerSales[seller] ?? 0.0) + total;
            branchSales[branch] = (branchSales[branch] ?? 0.0) + total;
          }

          setState(() {
            _totalRevenue = revenue;
            _transactionCount = salesList.length;
            _averageTicket = _transactionCount > 0 ? (revenue / _transactionCount) : 0.0;
            _salesBySeller = sellerSales;
            _salesByBranch = branchSales;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching analytics: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

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
                    Text(
                      "Analíticas de Negocio",
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Rendimiento detallado de sucursales, ventas y cajeros en tiempo real.",
                      style: TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw, color: AppTheme.accentColor),
                  onPressed: _fetchAnalytics,
                  tooltip: "Actualizar",
                ),
              ],
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.accentColor)))
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stat Cards Grid
                      GridView.count(
                        crossAxisCount: 3,
                        crossAxisSpacing: 24,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildStatCard("Ingresos Totales", "\$${_totalRevenue.toStringAsFixed(2)}", LucideIcons.dollarSign, Colors.greenAccent),
                          _buildStatCard("Total Transacciones", "$_transactionCount", LucideIcons.shoppingBag, AppTheme.accentColor),
                          _buildStatCard("Ticket Promedio", "\$${_averageTicket.toStringAsFixed(2)}", LucideIcons.trendingUp, Colors.blueAccent),
                        ],
                      ),
                      const SizedBox(height: 32),
                      // Charts & Breakdowns
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sales by Branch
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Ventas por Sucursal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                    const SizedBox(height: 24),
                                    if (_salesByBranch.isEmpty)
                                      const Text("No hay datos de sucursales", style: TextStyle(color: Colors.white38))
                                    else
                                      ..._salesByBranch.entries.map((entry) {
                                        final pct = _totalRevenue > 0 ? (entry.value / _totalRevenue) : 0.0;
                                        return _buildProgressRow(entry.key, entry.value, pct, Colors.blueAccent);
                                      }).toList(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // Sales by Seller
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Ventas por Cajero", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                    const SizedBox(height: 24),
                                    if (_salesBySeller.isEmpty)
                                      const Text("No hay datos de cajeros", style: TextStyle(color: Colors.white38))
                                    else
                                      ..._salesBySeller.entries.map((entry) {
                                        final pct = _totalRevenue > 0 ? (entry.value / _totalRevenue) : 0.0;
                                        return _buildProgressRow(entry.key, entry.value, pct, Colors.greenAccent);
                                      }).toList(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ).animate().fadeIn().slideY(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, color: Colors.white60)),
                  const SizedBox(height: 8),
                  Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow(String label, double value, double pct, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              Text("\$${value.toStringAsFixed(2)}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
