import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';

enum DateFilter { days, months, years }

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final _supabase = Supabase.instance.client;
  bool _showGraph = true;
  DateFilter _selectedFilter = DateFilter.months;
  late Future<Map<String, dynamic>> _dashboardDataFuture;
  List<dynamic> _allProfiles = [];

  @override
  void initState() {
    super.initState();
    _dashboardDataFuture = _fetchDashboardData();
  }

  Future<Map<String, dynamic>> _fetchDashboardData() async {
    try {
      // 1. Fetch global stats via RPC
      final statsResponse = await _supabase.rpc('get_global_network_stats');
      
      // 2. Fetch profiles using wildcard for resilience
      final profilesResponse = await _supabase
          .from('profiles')
          .select('*')
          .order('created_at', ascending: false);
      
      _allProfiles = profilesResponse as List<dynamic>;
      
      final int totalRegistered = _allProfiles.length;
      final int activeUsers = (totalRegistered * 0.7).round();
      final recentUsers = _allProfiles.take(6).toList();

      return {
        'totalRegistered': totalRegistered,
        'activeUsers': activeUsers,
        'recentUsers': recentUsers,
        'totalTenants': statsResponse['total_tenants'] ?? 0,
        'activeNodes': statsResponse['active_nodes_pct'] ?? 100,
      };
    } catch (e) {
      return {
        'totalRegistered': 0,
        'activeUsers': 0,
        'recentUsers': [],
        'totalTenants': 0,
        'activeNodes': 100,
      };
    }
  }

  Map<String, dynamic> _generateGraphData() {
    List<FlSpot> spots = [];
    List<String> labels = [];
    final now = DateTime.now();

    if (_selectedFilter == DateFilter.days) {
      Map<String, int> counts = {};
      for (int i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: 6 - i));
        counts[DateFormat('yyyy-MM-dd').format(date)] = 0;
      }
      
      for (var p in _allProfiles) {
        final dateStr = p['created_at'];
        if (dateStr != null) {
          final date = DateTime.parse(dateStr);
          final key = DateFormat('yyyy-MM-dd').format(date);
          if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
        }
      }

      int i = 0;
      counts.forEach((key, val) {
        spots.add(FlSpot(i.toDouble(), val.toDouble()));
        labels.add(DateFormat('dd/MM').format(DateTime.parse(key)));
        i++;
      });
    } else if (_selectedFilter == DateFilter.months) {
      Map<String, int> counts = {};
      for (int i = 0; i < 6; i++) {
        final date = DateTime(now.year, now.month - (5 - i), 1);
        counts[DateFormat('yyyy-MM').format(date)] = 0;
      }

      for (var p in _allProfiles) {
        final dateStr = p['created_at'];
        if (dateStr != null) {
          final date = DateTime.parse(dateStr);
          final key = DateFormat('yyyy-MM').format(date);
          if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
        }
      }

      int i = 0;
      counts.forEach((key, val) {
        spots.add(FlSpot(i.toDouble(), val.toDouble()));
        labels.add(DateFormat('MMM').format(DateTime.parse('$key-01')));
        i++;
      });
    } else {
      Map<int, int> counts = {};
      for (int i = 0; i < 5; i++) {
        counts[now.year - (4 - i)] = 0;
      }

      for (var p in _allProfiles) {
        final dateStr = p['created_at'];
        if (dateStr != null) {
          final date = DateTime.parse(dateStr);
          if (counts.containsKey(date.year)) counts[date.year] = counts[date.year]! + 1;
        }
      }

      int i = 0;
      counts.forEach((year, val) {
        spots.add(FlSpot(i.toDouble(), val.toDouble()));
        labels.add(year.toString());
        i++;
      });
    }

    if (spots.isEmpty) spots = [const FlSpot(0, 0)];
    return {'spots': spots, 'labels': labels};
  }

  String _getDisplayName(dynamic user) {
    String name = user['full_name'] ?? '';
    if (name.isEmpty) {
      final first = user['first_name'] ?? '';
      final last = user['last_name'] ?? '';
      name = '$first $last'.trim();
    }
    return name.isEmpty ? 'Identity' : name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _dashboardDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.red));
          }

          final data = snapshot.data ?? {};
          final graphData = _generateGraphData();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader().animate().fadeIn().slideY(begin: -0.2),
                const SizedBox(height: 48),
                
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    _buildStatCard("Usuarios Activos", data['activeUsers'].toString(), "Simulación de tráfico", LucideIcons.activity, Colors.red),
                    _buildStatCard("Usuarios Totales", data['totalRegistered'].toString(), "Nodos en la red", LucideIcons.users, AppTheme.primaryColor),
                    _buildStatCard("Empresas", data['totalTenants'].toString(), "Tenants operativos", LucideIcons.building, AppTheme.secondaryColor),
                    _buildStatCard("Uptime Nodos", "${data['activeNodes']}%", "Estabilidad global", LucideIcons.server, Colors.green),
                  ],
                ),
                
                const SizedBox(height: 48),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildInteractiveCard(graphData)),
                    const SizedBox(width: 32),
                    Expanded(flex: 1, child: _buildRecentActivityCard(data['recentUsers'] ?? [])),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Control Center", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
        const SizedBox(height: 8),
        Text("Infraestructura de Stakia Solutions", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16)),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, IconData icon, Color color) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.w500)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
        ],
      ),
    ).animate().fadeIn().scale(delay: 100.ms);
  }

  Widget _buildInteractiveCard(Map<String, dynamic> graphData) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
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
                  const Text("Analítica de Crecimiento", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text("Progreso de registros en el tiempo", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    _buildFilterButton("Días", DateFilter.days),
                    _buildFilterButton("Meses", DateFilter.months),
                    _buildFilterButton("Años", DateFilter.years),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _showGraph = !_showGraph),
                icon: Icon(_showGraph ? LucideIcons.table : LucideIcons.lineChart, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 48),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showGraph 
              ? _buildGraph(graphData['spots'], graphData['labels'])
              : _buildTable(),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.05);
  }

  Widget _buildFilterButton(String label, DateFilter filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: isSelected ? Colors.red : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildGraph(List<FlSpot> spots, List<String> labels) {
    return SizedBox(
      height: 350,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.03), strokeWidth: 1)),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) {
              int idx = val.toInt();
              if (idx >= 0 && idx < labels.length) return Padding(padding: const EdgeInsets.only(top: 12), child: Text(labels[idx], style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)));
              return const SizedBox();
            })),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.red,
              barWidth: 4,
              belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.red.withOpacity(0.2), Colors.red.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    return SizedBox(
      height: 350,
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [DataColumn(label: Text("Nombre")), DataColumn(label: Text("Rol")), DataColumn(label: Text("Registro"))],
          rows: _allProfiles.take(10).map((p) {
            return DataRow(cells: [
              DataCell(Text(_getDisplayName(p))),
              DataCell(Text(p['role']?.toString().toUpperCase() ?? 'USER')),
              DataCell(Text(DateFormat('dd/MM/yy').format(DateTime.parse(p['created_at'])))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRecentActivityCard(List<dynamic> users) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.surfaceDark, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05))),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Últimos Registros", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 32),
          if (users.isEmpty) const Text("Sin registros recientes", style: TextStyle(color: Colors.white24))
          else ...users.map((u) => _buildActivityItem(u)).toList(),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.05);
  }

  Widget _buildActivityItem(dynamic user) {
    final date = DateTime.parse(user['created_at']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: Colors.red.withOpacity(0.1), child: const Icon(LucideIcons.userPlus, color: Colors.red, size: 16)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_getDisplayName(user), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(DateFormat('dd MMM, HH:mm').format(date), style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
