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
  List<dynamic> _recentTenants = [];

  @override
  void initState() {
    super.initState();
    _dashboardDataFuture = _fetchDashboardData();
  }

  Future<Map<String, dynamic>> _fetchDashboardData() async {
    try {
      // 1. Fetch global stats via RPC
      final statsResponse = await _supabase.rpc('get_global_network_stats');
      
      // 2. Fetch profiles
      final profilesResponse = await _supabase
          .from('profiles')
          .select('*')
          .order('created_at', ascending: false);
      _allProfiles = profilesResponse as List<dynamic>;

      // 3. Fetch Recent Tenants (Clients) with their admin profile
      final tenantsResponse = await _supabase
          .from('tenants')
          .select('*, profiles(*)')
          .order('created_at', ascending: false)
          .limit(6);
      _recentTenants = tenantsResponse as List<dynamic>;
      
      final int totalRegistered = _allProfiles.length;
      final int activeUsers = (totalRegistered * 0.7).round();

      return {
        'totalRegistered': totalRegistered,
        'activeUsers': activeUsers,
        'recentTenants': _recentTenants,
        'totalTenants': statsResponse['total_tenants'] ?? 0,
        'activeNodes': statsResponse['active_nodes_pct'] ?? 100,
      };
    } catch (e) {
      debugPrint("Dashboard Fetch Error: $e");
      return {
        'totalRegistered': 0,
        'activeUsers': 0,
        'recentTenants': [],
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
                    Expanded(flex: 1, child: _buildRecentActivityCard(data['recentTenants'] ?? [])),
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

  Widget _buildRecentActivityCard(List<dynamic> tenants) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark, 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: Colors.white.withOpacity(0.05))
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Clientes Recientes", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 32),
          if (tenants.isEmpty) 
            const Text("Sin clientes recientes", style: TextStyle(color: Colors.white24))
          else 
            ...tenants.map((t) => _buildClientItem(t)).toList(),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.05);
  }

  Widget _buildClientItem(dynamic tenant) {
    final profiles = tenant['profiles'] as List? ?? [];
    final admin = profiles.firstWhere((p) => p['role'] == 'admin', orElse: () => profiles.isNotEmpty ? profiles[0] : null);
    final clientName = admin != null ? _getDisplayName(admin) : 'Sin Contacto';

    return InkWell(
      onTap: () => _showClientDetails(tenant, admin),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24, top: 8, left: 8, right: 8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primaryColor.withOpacity(0.1), 
              backgroundImage: admin?['avatar_url'] != null ? NetworkImage(admin!['avatar_url']) : null,
              child: admin?['avatar_url'] == null ? const Icon(LucideIcons.building, color: AppTheme.primaryColor, size: 16) : null
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clientName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(tenant['name'] ?? 'Empresa', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 16, color: Colors.white.withOpacity(0.2)),
          ],
        ),
      ),
    );
  }

  void _showClientDetails(dynamic tenant, dynamic admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.primaryColor, AppTheme.secondaryColor]),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(top: 16, right: 16, child: IconButton(icon: const Icon(LucideIcons.x, color: Colors.white), onPressed: () => Navigator.pop(context))),
                    Positioned(
                      bottom: -30,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: AppTheme.surfaceDark,
                        child: CircleAvatar(
                          radius: 46,
                          backgroundImage: admin?['avatar_url'] != null ? NetworkImage(admin!['avatar_url']) : null,
                          child: admin?['avatar_url'] == null ? const Icon(LucideIcons.user, size: 40) : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(admin?['full_name'] ?? 'Nombre no disponible', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(tenant['name'] ?? 'Empresa', style: TextStyle(color: Colors.white.withOpacity(0.5))),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildDetailRow("ID Cliente", (admin?['id'] ?? '---').toString().substring(0, 8)),
                    _buildDetailRow("Suscripción", tenant['subscription_tier'] ?? 'Básica'),
                    _buildDetailRow("Estado Pago", tenant['payment_status'] ?? 'Activo'),
                    _buildDetailRow("Vencimiento", tenant['trial_ends_at'] != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(tenant['trial_ends_at'])) : '30/12/2026'),
                    _buildDetailRow("Registrado", DateFormat('dd MMM yyyy').format(DateTime.parse(tenant['created_at']))),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}
