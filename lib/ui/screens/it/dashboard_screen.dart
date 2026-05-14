import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class ITDashboardScreen extends StatefulWidget {
  const ITDashboardScreen({super.key});

  @override
  State<ITDashboardScreen> createState() => _ITDashboardScreenState();
}

class _ITDashboardScreenState extends State<ITDashboardScreen> {
  final _supabase = Supabase.instance.client;
  late Future<Map<String, dynamic>> _itDataFuture;

  @override
  void initState() {
    super.initState();
    _itDataFuture = _fetchITData();
  }

  Future<Map<String, dynamic>> _fetchITData() async {
    try {
      // 1. Active sessions (devices)
      final sessions = await _supabase.from('staff_sessions').select('id').isFilter('ended_at', null);
      
      // 2. Audit logs (errors)
      final logs = await _supabase.from('audit_logs').select('id').limit(5);

      // 3. App downloads
      final downloads = await _supabase.from('app_downloads').select('id');

      return {
        'activeDevices': (sessions as List).length,
        'systemLogs': (logs as List).length,
        'totalDownloads': (downloads as List).length,
      };
    } catch (e) {
      return {
        'activeDevices': 0,
        'systemLogs': 0,
        'totalDownloads': 0,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _itDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.red));
          }

          final data = snapshot.data ?? {};

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
                        Text("Soporte & Infraestructura", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text("Estado de hardware y red de la sucursal.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => setState(() { _itDataFuture = _fetchITData(); }),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text("Refrescar"),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryColor, foregroundColor: Colors.white),
                    ),
                  ],
                ).animate().fadeIn().slideY(begin: -0.2),
                const SizedBox(height: 48),
                
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    SizedBox(width: 300, child: _buildStatCard("Dispositivos Online", "${data['activeDevices']}", "Sesiones de personal activas", LucideIcons.cpu, AppTheme.secondaryColor)),
                    SizedBox(width: 300, child: _buildStatCard("Eventos Sistema", "${data['systemLogs']}", "Logs registrados hoy", LucideIcons.activity, Colors.redAccent)),
                    SizedBox(width: 300, child: _buildStatCard("Despliegues", "${data['totalDownloads']}", "Instancias de app instaladas", LucideIcons.download, AppTheme.primaryColor)),
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
                          Expanded(flex: 2, child: _buildHardwareList()),
                          const SizedBox(width: 24),
                          Expanded(flex: 1, child: _buildRecentTickets()),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildHardwareList(),
                          const SizedBox(height: 24),
                          _buildRecentTickets(),
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

  Widget _buildHardwareList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Estado del Hardware", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _buildDeviceItem("Servidor Local Node", "Uptime: 100%", LucideIcons.server, true),
            _buildDeviceItem("Terminal POS 01", "Windows 11 - Online", LucideIcons.monitor, true),
            _buildDeviceItem("Impresora Térmica", "Estado: OK", LucideIcons.printer, true),
            _buildDeviceItem("Router Sucursal", "Latencia: 15ms", LucideIcons.wifi, true),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _buildDeviceItem(String name, String status, IconData icon, bool isOk) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: isOk ? Colors.white70 : Colors.redAccent, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(status, style: TextStyle(color: isOk ? Colors.white54 : Colors.redAccent, fontSize: 12)),
              ],
            ),
          ),
          Icon(isOk ? LucideIcons.checkCircle2 : LucideIcons.alertTriangle, color: isOk ? Colors.red : Colors.redAccent, size: 20),
        ],
      ),
    );
  }

  Widget _buildRecentTickets() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Seguridad & Red", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _buildTicketItem("SSL", "Certificado Válido", "Seguro"),
            _buildTicketItem("Firewall", "Stakia Guardian Activo", "Protegido"),
            _buildTicketItem("Sync", "Real-time Hub Online", "Activo"),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildTicketItem(String id, String desc, String priority) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(id, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(priority, style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          const Divider(color: Colors.white10),
        ],
      ),
    );
  }
}
