import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
  Map<String, double> _salesByCategory = {};
  List<Map<String, dynamic>> _dailyRevenue = [];

  String _selectedPeriod = 'month';
  final List<Map<String, String>> _periods = [
    {'key': 'today', 'label': 'Hoy'},
    {'key': 'week', 'label': 'Semana'},
    {'key': 'month', 'label': 'Mes'},
    {'key': 'year', 'label': 'Año'},
    {'key': 'all', 'label': 'Todo'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  DateTime? _getPeriodStart(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'week':
        return now.subtract(Duration(days: now.weekday - 1));
      case 'month':
        return DateTime(now.year, now.month, 1);
      case 'year':
        return DateTime(now.year, 1, 1);
      case 'all':
      default:
        return null;
    }
  }

  Future<void> _fetchAnalytics() async {
    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .single();

      final tenantId = profile['tenant_id'];
      if (tenantId == null) return;

      final periodStart = _getPeriodStart(_selectedPeriod);

      var salesQuery = _supabase
          .from('sales')
          .select('total_amount, created_at, profiles!seller_id(full_name), branches!branch_id(name)')
          .eq('tenant_id', tenantId);

      if (periodStart != null) {
        salesQuery = salesQuery.gte('created_at', periodStart.toIso8601String());
      }
      if (_selectedPeriod == 'today') {
        final endOfDay = periodStart!.add(const Duration(days: 1));
        salesQuery = salesQuery.lt('created_at', endOfDay.toIso8601String());
      }

      final data = await salesQuery.order('created_at', ascending: false);

      final salesList = List<Map<String, dynamic>>.from(data);

      double revenue = 0.0;
      Map<String, double> sellerSales = {};
      Map<String, double> branchSales = {};
      Map<String, double> dailyMap = {};

      for (var sale in salesList) {
        final total = double.tryParse(sale['total_amount'].toString()) ?? 0.0;
        revenue += total;

        final seller = sale['profiles']?['full_name'] ?? 'Unknown';
        final branch = sale['branches']?['name'] ?? 'Primary Branch';
        final day = sale['created_at'] != null
            ? DateFormat('yyyy-MM-dd').format(DateTime.parse(sale['created_at']))
            : 'Unknown';

        sellerSales[seller] = (sellerSales[seller] ?? 0.0) + total;
        branchSales[branch] = (branchSales[branch] ?? 0.0) + total;
        dailyMap[day] = (dailyMap[day] ?? 0.0) + total;
      }

      final dailyEntries = dailyMap.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final dailyRevenue = dailyEntries
          .map((e) => {'date': e.key, 'total': e.value})
          .toList();

      Map<String, double> categorySales = {};
      try {
        final itemsData = await _supabase
            .from('items')
            .select('category, stock_level')
            .eq('tenant_id', tenantId);
        final itemsList = List<Map<String, dynamic>>.from(itemsData);
        for (var item in itemsList) {
          final cat = item['category']?.toString() ?? 'Uncategorized';
          final stock = int.tryParse(item['stock_level']?.toString() ?? '0') ?? 0;
          categorySales[cat] = (categorySales[cat] ?? 0.0) + stock;
        }
      } catch (_) {
        categorySales = {'No data': 1.0};
      }

      setState(() {
        _totalRevenue = revenue;
        _transactionCount = salesList.length;
        _averageTicket = _transactionCount > 0 ? (revenue / _transactionCount) : 0.0;
        _salesBySeller = sellerSales;
        _salesByBranch = branchSales;
        _salesByCategory = categorySales;
        _dailyRevenue = dailyRevenue;
      });
    } catch (e) {
      debugPrint("Error fetching analytics: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.fileText, color: AppTheme.accentColor),
                      onPressed: () => ToastUtils.showCustomToast(context, "Exportación de reportes — Próximamente"),
                      tooltip: "Exportar",
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(LucideIcons.refreshCw, color: AppTheme.accentColor),
                      onPressed: _fetchAnalytics,
                      tooltip: "Actualizar",
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPeriodFilter(),
            const SizedBox(height: 24),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.accentColor)))
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      if (_dailyRevenue.isNotEmpty) ...[
                        _buildBarChart(),
                        const SizedBox(height: 32),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                      }),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
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
                                      }),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      if (_salesByCategory.isNotEmpty) _buildPieChart(),
                    ],
                  ).animate().fadeIn().slideY(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodFilter() {
    return Row(
      children: _periods.map((p) {
        final active = _selectedPeriod == p['key'];
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ChoiceChip(
            label: Text(p['label']!),
            selected: active,
            onSelected: (_) {
              setState(() => _selectedPeriod = p['key']!);
              _fetchAnalytics();
            },
            selectedColor: AppTheme.accentColor.withOpacity(0.3),
            backgroundColor: Colors.white.withOpacity(0.05),
            labelStyle: TextStyle(
              color: active ? AppTheme.accentColor : Colors.white60,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            side: BorderSide(
              color: active ? AppTheme.accentColor.withOpacity(0.6) : Colors.white10,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBarChart() {
    if (_dailyRevenue.isEmpty) return const SizedBox.shrink();
    final maxY = _dailyRevenue.fold<double>(0.0, (max, d) => (d['total'] as double) > max ? (d['total'] as double) : max);
    final chartMax = maxY > 0 ? maxY * 1.2 : 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Ingresos Diarios", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text("Distribución de ingresos en el período seleccionado", style: TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 24),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: chartMax,
                  minY: 0,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final day = _dailyRevenue[groupIndex]['date'] as String;
                          final val = rod.toY;
                        return BarTooltipItem(
                          '${DateFormat('MMM dd').format(DateTime.parse(day))}\n\$${val.toStringAsFixed(2)}',
                          const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _dailyRevenue.length) return const SizedBox.shrink();
                          final dateStr = _dailyRevenue[idx]['date'] as String;
                          final label = DateFormat('dd/MM').format(DateTime.parse(dateStr));
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '\$${value.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.white38, fontSize: 9),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: chartMax / 4,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                  ),
                  barGroups: _dailyRevenue.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value['total'] as double,
                          color: AppTheme.accentColor,
                          width: _dailyRevenue.length > 15 ? 10 : 20,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    final total = _salesByCategory.values.fold<double>(0.0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();
    final colors = [
      Colors.blueAccent, Colors.greenAccent, Colors.orangeAccent,
      Colors.purpleAccent, Colors.redAccent, Colors.tealAccent,
      Colors.pinkAccent, Colors.yellowAccent, Colors.cyanAccent,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Distribución por Categoría", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text("Participación de categorías de inventario", style: TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: _salesByCategory.entries.toList().asMap().entries.map((entry) {
                        final idx = entry.key;
                        final e = entry.value;
                        final pct = e.value / total;
                        return PieChartSectionData(
                          color: colors[idx % colors.length],
                          value: pct * 100,
                          title: '${(pct * 100).toStringAsFixed(0)}%',
                          radius: 50,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: _salesByCategory.entries.toList().asMap().entries.map((entry) {
                      final idx = entry.key;
                      final e = entry.value;
                      final pct = e.value / total;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colors[idx % colors.length],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${e.key} (${(pct * 100).toStringAsFixed(1)}%)',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
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
