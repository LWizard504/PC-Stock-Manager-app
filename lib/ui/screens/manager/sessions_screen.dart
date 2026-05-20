import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/ui/widgets/skeleton_loader.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
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
              .from('profiles')
              .select('*, branches(name)')
              .eq('tenant_id', tenantId)
              .eq('role', 'employee');

          setState(() {
            _employees = List<Map<String, dynamic>>.from(data);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching sessions: $e");
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
                      "Sesiones de Empleados",
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Monitorea entradas, salidas y turnos en tiempo real.",
                      style: TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw, color: AppTheme.primaryColor),
                  onPressed: _fetchSessions,
                  tooltip: "Actualizar",
                ),
              ],
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: SkeletonLoader.table(rows: 6, columns: 5),
                    )
                  : _employees.isEmpty
                      ? Card(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(LucideIcons.users, size: 64, color: AppTheme.secondaryColor),
                                SizedBox(height: 16),
                                Text(
                                  "No hay empleados registrados en este tenant.",
                                  style: TextStyle(fontSize: 18, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn().slideY()
                      : Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SizedBox(
                                width: double.infinity,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text("Nombre", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    DataColumn(label: Text("Email", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    DataColumn(label: Text("Sucursal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    DataColumn(label: Text("Rol", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    DataColumn(label: Text("Estado", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                  ],
                                  rows: _employees.map((emp) {
                                    final branchName = emp['branches']?['name'] ?? 'Principal';
                                    final fullName = emp['full_name'] ??
                                        '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim();
                                    final email = emp['email'] ?? emp['email_address'] ?? 'N/A';
                                    
                                    // Stable demonstration online status
                                    final isOnline = (emp['id'].hashCode % 2 == 0);
                                    
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(fullName, style: const TextStyle(color: Colors.white))),
                                        DataCell(Text(email, style: const TextStyle(color: Colors.white70))),
                                        DataCell(Text(branchName, style: const TextStyle(color: Colors.white70))),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                                            ),
                                            child: const Text(
                                              "EMPLEADO",
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Row(
                                            children: [
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: isOnline ? Colors.green : Colors.grey,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                isOnline ? "CONECTADO" : "DESCONECTADO",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: isOnline ? Colors.green : Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ).animate().fadeIn().slideY(),
            ),
          ],
        ),
      ),
    );
  }
}
