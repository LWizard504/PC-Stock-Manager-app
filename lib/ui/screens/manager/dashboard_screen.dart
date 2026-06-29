import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pc_dev_flutter/services/signaling_service.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final _supabase = Supabase.instance.client;
  late Future<Map<String, dynamic>> _managerDataFuture;
  bool _showTutorial = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => SignalingService().init());
    _managerDataFuture = _fetchManagerData();
    _initRealtime();
    _checkTutorial();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkTutorial() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final data = await _supabase
          .from('profiles')
          .select('tutorial_completed')
          .eq('id', user.id)
          .single();
      if (data['tutorial_completed'] == false) {
        setState(() => _showTutorial = true);
      }
    } catch (_) {}
  }

  void _initRealtime() {
    _channel = _supabase.channel('dashboard-realtime');
    _channel?.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'sales',
      callback: (_) => _refreshData(),
    );
    _channel?.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'inventory',
      callback: (_) => _refreshData(),
    );
    _channel?.subscribe();
  }

  void _refreshData() {
    setState(() {
      _managerDataFuture = _fetchManagerData();
    });
  }

  Future<Map<String, dynamic>> _fetchManagerData() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      final salesResponse = await _supabase
          .from('sales')
          .select('total_amount')
          .gte('created_at', todayStart);
      final double totalToday = (salesResponse as List).fold(
          0,
          (sum, item) =>
              sum + (item['total_amount'] as num).toDouble());
      final int countToday = salesResponse.length;

      final sessionsResponse = await _supabase
          .from('staff_sessions')
          .select('id')
          .isFilter('ended_at', null);
      final int activeSessions = (sessionsResponse as List).length;

      final inventoryResponse = await _supabase
          .from('inventory')
          .select('stock_level')
          .lt('stock_level', 10);
      final int stockAlerts = (inventoryResponse as List).length;

      final hourlySalesResponse = await _supabase
          .from('sales')
          .select('total_amount, created_at')
          .gte('created_at', todayStart);
      final Map<int, double> hourlySales = {};
      for (int h = 8; h <= 16; h++) hourlySales[h] = 0.0;
      for (final sale in hourlySalesResponse as List) {
        final createdAt = DateTime.parse(sale['created_at'] as String);
        final hour = createdAt.hour;
        if (hour >= 8 && hour <= 16) {
          hourlySales[hour] =
              (hourlySales[hour] ?? 0.0) +
              (sale['total_amount'] as num).toDouble();
        }
      }

      final lowStockResponse = await _supabase
          .from('inventory')
          .select('name, stock_level')
          .lt('stock_level', 10)
          .order('stock_level');

      final currentUser = _supabase.auth.currentUser;
      List<dynamic> profilesList = [];
      if (currentUser != null) {
        final profileResponse = await _supabase
            .from('profiles')
            .select('tenant_id')
            .eq('id', currentUser.id)
            .single();
        final tenantId = profileResponse['tenant_id'];
        if (tenantId != null) {
          final employeeResponse = await _supabase
              .from('profiles')
              .select('id, full_name, first_name, last_name, role')
              .eq('tenant_id', tenantId);
          profilesList = employeeResponse as List<dynamic>;
        }
      }

      return {
        'totalToday': totalToday,
        'countToday': countToday,
        'activeSessions': activeSessions,
        'stockAlerts': stockAlerts,
        'hourlySales': hourlySales,
        'lowStockItems': lowStockResponse,
        'profiles': profilesList,
      };
    } catch (e) {
      return {
        'totalToday': 0.0,
        'countToday': 0,
        'activeSessions': 0,
        'stockAlerts': 0,
        'hourlySales': <int, double>{},
        'lowStockItems': [],
        'profiles': [],
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _managerDataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.red));
              }

              final data = snapshot.data ?? {};
              final hourlySales =
                  data['hourlySales'] as Map<int, double>? ?? {};
              final lowStockItems =
                  data['lowStockItems'] as List<dynamic>? ?? [];

              return SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Gestión Operativa",
                            style: Theme.of(context)
                                .textTheme
                                .displayLarge
                                ?.copyWith(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                            "Monitoreo en tiempo real de sucursal.",
                            style: TextStyle(
                                color: Colors.white60, fontSize: 16)),
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
                              "Ventas de Hoy",
                              "\$${data['totalToday'].toStringAsFixed(2)}",
                              "${data['countToday']} transacciones",
                              LucideIcons.trendingUp,
                              Colors.red)),
                        SizedBox(
                          width: 300,
                          child: _buildStatCard(
                              "Cajas Activas",
                              data['activeSessions'].toString(),
                              "Personal en turno",
                              LucideIcons.monitorSmartphone,
                              AppTheme.primaryColor)),
                        SizedBox(
                          width: 300,
                          child: _buildStatCard(
                              "Alertas de Stock",
                              data['stockAlerts'].toString(),
                              "Productos bajo el mínimo",
                              LucideIcons.packageOpen,
                              Colors.orangeAccent)),
                      ],
                    ),
                    const SizedBox(height: 32),

                    _buildHourlySalesChart(hourlySales),
                    const SizedBox(height: 32),

                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 800;
                        final profiles =
                            data['profiles'] as List<dynamic>? ?? [];
                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  flex: 1,
                                  child:
                                      _buildLowStockCard(lowStockItems)),
                              const SizedBox(width: 24),
                              Expanded(
                                  flex: 1,
                                  child: _buildEmployeeStatusCard(
                                      profiles)),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              _buildLowStockCard(lowStockItems),
                              const SizedBox(height: 24),
                              _buildEmployeeStatusCard(profiles),
                            ],
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          _buildTutorialOverlay(),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, String subtitle, IconData icon, Color color) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
              colors: [color.withOpacity(0.1), Colors.transparent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
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
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 16)),
                Icon(icon, color: color),
              ],
            ),
            const SizedBox(height: 16),
            Text(value,
                style: const TextStyle(
                    fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildHourlySalesChart(Map<int, double> hourlySales) {
    final maxVal = hourlySales.values.isEmpty
        ? 0.0
        : hourlySales.values.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal == 0 ? 100.0 : maxVal * 1.2;

    final barGroups = hourlySales.entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value,
            color: AppTheme.primaryColor,
            width: 20,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Ventas por Hora",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barGroups: barGroups,
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding:
                                const EdgeInsets.only(top: 8),
                            child: Text(
                              '${value.toInt()}:00',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildLowStockCard(List<dynamic> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Productos con Stock Bajo",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(LucideIcons.checkCircle,
                        color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text("No hay productos con stock bajo.",
                        style:
                            TextStyle(color: Colors.white54)),
                  ],
                ),
              )
            else
              ...items.map((item) => _buildLowStockItem(
                    item['name'],
                    (item['stock_level'] as num).toInt(),
                  )),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _buildLowStockItem(String name, int stock) {
    final percent = (stock / 10.0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis)),
              Text(
                "$stock unidades",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: stock < 5
                      ? Colors.red
                      : Colors.orangeAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percent,
            backgroundColor: AppTheme.surfaceLight,
            color: stock < 5 ? Colors.red : Colors.orangeAccent,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeStatusCard(List<dynamic> profiles) {
    if (profiles.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Estado de Sesiones",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      "No se encontraron colaboradores.",
                      style: TextStyle(color: Colors.white38)),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn().slideX(begin: 0.1);
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: SignalingService().onlineUsersNotifier,
      builder: (context, onlineUserIds, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Estado de Sesiones",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                ...profiles.map((profile) {
                  final String userId =
                      profile['id'].toString();
                  final isOnline =
                      onlineUserIds.contains(userId);
                  String name = profile['full_name'] ?? '';
                  if (name.isEmpty) {
                    name =
                        '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
                            .trim();
                  }
                  if (name.isEmpty) {
                    name = "Colaborador Desconocido";
                  }

                  final role = (profile['role']
                              ?.toString() ??
                          'employee')
                      .toUpperCase();
                  final status =
                      isOnline ? "Online" : "Offline";

                  return _buildEmployeeItem(
                      name, role, status, isOnline);
                }),
              ],
            ),
          ),
        );
      },
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildEmployeeItem(
      String name, String role, String status, bool isOnline) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.red.withOpacity(0.1),
            child: Icon(LucideIcons.user,
                color: isOnline ? Colors.red : Colors.white24,
                size: 16),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500)),
                Text(role,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOnline
                  ? Colors.red.withOpacity(0.1)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(status,
                style: TextStyle(
                    color: isOnline
                        ? Colors.red
                        : Colors.white54,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialOverlay() {
    if (!_showTutorial) return const SizedBox.shrink();

    return Stack(
      children: [
        GestureDetector(
          onTap: () {},
          child: Container(color: Colors.black54),
        ),
        Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.info,
                          color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Text("Bienvenido al Panel",
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildTutorialTip(LucideIcons.trendingUp,
                      "Monitorea las ventas del día en tiempo real."),
                  const SizedBox(height: 12),
                  _buildTutorialTip(LucideIcons.barChart3,
                      "Revisa el desglose por hora de las ventas."),
                  const SizedBox(height: 12),
                  _buildTutorialTip(LucideIcons.packageOpen,
                      "Recibe alertas cuando el stock esté bajo."),
                  const SizedBox(height: 12),
                  _buildTutorialTip(LucideIcons.monitorSmartphone,
                      "Observa quién está en línea en tu sucursal."),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _dismissTutorial,
                      child: const Text("Entendido"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTutorialTip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon,
            color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }

  Future<void> _dismissTutorial() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      await _supabase
          .from('profiles')
          .update({'tutorial_completed': true})
          .eq('id', user.id);
    }
    setState(() => _showTutorial = false);
  }
}
