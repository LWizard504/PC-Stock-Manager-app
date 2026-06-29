import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _supabase = Supabase.instance.client;
  late Future<Map<String, dynamic>> _adminDataFuture;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _adminDataFuture = _fetchAdminData();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    _channel = _supabase.channel('admin-dashboard-updates');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'audit_logs',
      callback: (_) {
        if (mounted) setState(() { _adminDataFuture = _fetchAdminData(); });
      },
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'sales',
      callback: (_) {
        if (mounted) setState(() { _adminDataFuture = _fetchAdminData(); });
      },
    );
    _channel!.subscribe();
  }

  Future<Map<String, dynamic>> _fetchAdminData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("No auth");

      // Tenant info
      Map<String, dynamic>? tenant;
      try {
        final profileRes = await _supabase
            .from('profiles')
            .select('tenant_id')
            .eq('id', user.id)
            .maybeSingle();
        if (profileRes != null && profileRes['tenant_id'] != null) {
          final tid = profileRes['tenant_id'] as String;
          final tenantRes = await _supabase
              .from('tenants')
              .select('subscription_tier, billing_interval')
              .eq('id', tid)
              .maybeSingle();
          if (tenantRes != null) tenant = tenantRes as Map<String, dynamic>?;
        }
      } catch (_) {}

      // Sales — total + monthly grouping
      final salesResponse = await _supabase
          .from('sales')
          .select('total_amount, created_at');
      final salesList = salesResponse as List;
      final totalRevenue = salesList.fold<double>(
        0,
        (sum, item) => sum + (item['total_amount'] as num).toDouble(),
      );
      final totalSalesCount = salesList.length;

      final monthlyRevenue = List<double>.filled(12, 0);
      for (final sale in salesList) {
        final date = DateTime.parse(sale['created_at'] as String);
        monthlyRevenue[date.month - 1] +=
            (sale['total_amount'] as num).toDouble();
      }

      // Revenue change: last 3 months vs previous 3 months
      final now = DateTime.now();
      final cm = now.month;
      double last3 = 0, prev3 = 0;
      for (int i = 0; i < 3; i++) {
        last3 += monthlyRevenue[(cm - 1 - i + 12) % 12];
        prev3 += monthlyRevenue[(cm - 1 - i - 3 + 12) % 12];
      }
      final revenueChange =
          prev3 > 0 ? ((last3 - prev3) / prev3 * 100) : 0.0;

      // Inventory low stock
      final inventoryResponse = await _supabase
          .from('inventory')
          .select('stock_level')
          .lt('stock_level', 5);
      final lowStockCount = (inventoryResponse as List).length;

      // Personnel
      final profilesResponse = await _supabase
          .from('profiles')
          .select('id')
          .inFilter('role', ['manager', 'employee', 'it']);
      final employeeCount = (profilesResponse as List).length;

      // Audit logs
      List<dynamic> auditLogs = [];
      try {
        final auditResponse = await _supabase
            .from('audit_logs')
            .select('*')
            .order('created_at', ascending: false)
            .limit(5);
        auditLogs = auditResponse as List;
      } catch (_) {}

      // Recent sales
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
        'monthlyRevenue': monthlyRevenue,
        'revenueChange': revenueChange,
        'auditLogs': auditLogs,
        'tenant': tenant,
      };
    } catch (e) {
      return {
        'totalRevenue': 0.0,
        'salesCount': 0,
        'lowStockCount': 0,
        'employeeCount': 0,
        'recentSales': [],
        'monthlyRevenue': List<double>.filled(12, 0),
        'revenueChange': 0.0,
        'auditLogs': [],
        'tenant': null,
      };
    }
  }

  String _getDisplayName(dynamic user) {
    if (user == null) return 'Usuario';
    final name = user['full_name'] as String? ?? '';
    if (name.isEmpty) {
      final first = user['first_name'] as String? ?? '';
      final last = user['last_name'] as String? ?? '';
      return '$first $last'.trim();
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
            return const Center(
                child: CircularProgressIndicator(color: Colors.red));
          }

          final data = snapshot.data ?? {};
          final recentSales = data['recentSales'] as List<dynamic>? ?? [];
          final monthlyRevenue =
              data['monthlyRevenue'] as List<double>? ??
                  List<double>.filled(12, 0);
          final auditLogs = data['auditLogs'] as List<dynamic>? ?? [];
          final revenueChange = data['revenueChange'] as double? ?? 0.0;
          final tenant = data['tenant'] as Map<String, dynamic>?;

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
                        Row(
                          children: [
                            Text(
                              "Dashboard Administrativo",
                              style: Theme.of(context)
                                  .textTheme
                                  .displayLarge
                                  ?.copyWith(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            if (tenant != null &&
                                tenant['subscription_tier'] != null)
                              ...[
                                const SizedBox(width: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    border: Border.all(
                                        color: Colors.red.withOpacity(0.2)),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    "${(tenant['subscription_tier'] as String).toUpperCase()} PLAN • ${(tenant['billing_interval'] as String? ?? 'MONTHLY').toUpperCase()}",
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Gestión operacional de sucursal.",
                          style: TextStyle(color: Colors.white60, fontSize: 16),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => setState(
                          () { _adminDataFuture = _fetchAdminData(); }),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text("Actualizar"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surfaceLight,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ).animate().fadeIn().slideY(begin: -0.2),

                const SizedBox(height: 48),

                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    SizedBox(
                      width: 300,
                      child: _buildStatCard(
                        "Ingresos Totales",
                        "\$${NumberFormat("#,##0.00").format(data['totalRevenue'])}",
                        "Ventas acumuladas",
                        LucideIcons.dollarSign,
                        Colors.red,
                        change: revenueChange,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: _buildStatCard(
                        "Personal",
                        data['employeeCount'].toString(),
                        "Nodos humanos activos",
                        LucideIcons.users,
                        AppTheme.primaryColor,
                        change: 2.4,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: _buildStatCard(
                        "Inventario Bajo",
                        data['lowStockCount'].toString(),
                        "Productos críticos",
                        LucideIcons.alertTriangle,
                        Colors.orangeAccent,
                        change: (data['lowStockCount'] as int) > 0
                            ? -1.1
                            : 0.0,
                      ),
                    ),
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
                          Expanded(
                            flex: 2,
                            child:
                                _buildRevenueChart(context, monthlyRevenue),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 1,
                            child: Column(
                              children: [
                                _buildAuditTelemetry(auditLogs),
                                const SizedBox(height: 24),
                                _buildRecentActivity(recentSales),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildRevenueChart(context, monthlyRevenue),
                        const SizedBox(height: 24),
                        _buildAuditTelemetry(auditLogs),
                        const SizedBox(height: 24),
                        _buildRecentActivity(recentSales),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color, {
    double? change,
  }) {
    final changeStr = change != null
        ? '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%'
        : null;
    final isPositive = change == null || change >= 0;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), Colors.transparent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
                Icon(icon, color: color),
              ],
            ),
            const SizedBox(height: 16),
            Text(value,
                style:
                    const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            if (changeStr != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isPositive
                        ? LucideIcons.trendingUp
                        : LucideIcons.trendingDown,
                    size: 14,
                    color:
                        isPositive ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    changeStr,
                    style: TextStyle(
                      color:
                          isPositive ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildRevenueChart(
      BuildContext context, List<double> monthlyRevenue) {
    final maxVal = monthlyRevenue.reduce((a, b) => a > b ? a : b);
    final effectiveMax = maxVal == 0 ? 100.0 : maxVal * 1.2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Proyección de Ventas",
                    style: Theme.of(context).textTheme.titleLarge),
                const Text("Rendimiento Mensual",
                    style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: effectiveMax,
                  barGroups: List.generate(12, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: monthlyRevenue[i],
                          color: Colors.red,
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          const months = [
                            'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
                            'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dec'
                          ];
                          final idx = value.toInt();
                          if (idx < 0 || idx >= months.length) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              months[idx],
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '\$${NumberFormat.compact().format(value)}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: effectiveMax / 4,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: Colors.white10, strokeWidth: 1),
                  ),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '\$${NumberFormat("#,##0.00").format(rod.toY)}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _buildAuditTelemetry(List<dynamic> logs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Audit Telemetry",
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.red,
                          blurRadius: 8,
                          spreadRadius: 1),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text("Sin registros de auditoría",
                    style: TextStyle(color: Colors.white24)),
              )
            else
              ...logs.map((log) {
                final severity =
                    log['severity'] as String? ?? 'INFO';
                final action = log['action'] as String? ?? '';
                final details = log['details'];
                final date =
                    DateTime.parse(log['created_at'] as String);
                final isCritical = severity == 'CRITICAL';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCritical
                              ? Colors.red
                              : Colors.green,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (isCritical ? Colors.red : Colors.green)
                                      .withOpacity(0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(action,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(height: 4),
                            if (details != null)
                              Text(
                                details.toString(),
                                style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('HH:mm').format(date),
                              style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildRecentActivity(List<dynamic> sales) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Últimas Transacciones",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (sales.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text("Sin transacciones detectadas",
                    style: TextStyle(color: Colors.white24)),
              )
            else
              ...sales.map((sale) {
                final date =
                    DateTime.parse(sale['created_at'] as String);
                final employeeName =
                    _getDisplayName(sale['profiles']);
                return _buildActivityItem(
                  "Venta # ${sale['id'].toString().substring(0, 4)}",
                  "\$${(sale['total_amount'] as num).toStringAsFixed(2)}",
                  "${DateFormat('HH:mm').format(date)} - $employeeName",
                  true,
                );
              }).toList(),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildActivityItem(
      String title, String amount, String time, bool isPositive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.shoppingBag,
                size: 16,
                color: isPositive ? Colors.red : Colors.white54),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        const TextStyle(fontWeight: FontWeight.w500)),
                Text(time,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Text(amount,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}
