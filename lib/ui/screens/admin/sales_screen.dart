import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sales = [];
  double _totalRevenue = 0;

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  Future<void> _fetchSales() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase.from('profiles').select('tenant_id, role').eq('id', user.id).single();
      final tenantId = profile['tenant_id'];

      var query = supabase.from('sales').select('*, profiles!inner(full_name, first_name, last_name)');

      if (tenantId != null) {
        query = query.eq('tenant_id', tenantId);
      }

      final response = await query.order('created_at', ascending: false);

      if (mounted) {
        final sales = List<Map<String, dynamic>>.from(response);
        final total = sales.fold(0.0, (sum, s) => sum + (s['total'] as num).toDouble());
        
        setState(() {
          _sales = sales;
          _totalRevenue = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getSellerName(dynamic profile) {
    if (profile == null) return "N/A";
    String name = profile['full_name'] ?? '';
    if (name.isEmpty) {
      name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? "Vendedor" : name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
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
                    Text("Historial de Ventas", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text("Registro detallado de transacciones y facturación.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                _buildRevenueBadge(),
              ],
            ).animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 48),
            
            _buildFilters(),
            const SizedBox(height: 32),
            
            _buildSalesTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text("TOTAL RECAUDADO", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text("\$${NumberFormat("#,##0.00").format(_totalRevenue)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: InputDecoration(
              hintText: "Buscar por ID de venta o vendedor...",
              prefixIcon: const Icon(LucideIcons.search, color: Colors.white24),
              filled: true,
              fillColor: AppTheme.surfaceDark,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _fetchSales,
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: const Text("Actualizar"),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceLight),
        ),
      ],
    );
  }

  Widget _buildSalesTable() {
    if (_isLoading) return const Center(child: Padding(padding: EdgeInsets.all(64), child: CircularProgressIndicator(color: Colors.red)));
    if (_sales.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(64), child: Text("No se registran ventas", style: TextStyle(color: Colors.white24))));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Transacciones Recientes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                columns: const [
                  DataColumn(label: Text("Venta ID")),
                  DataColumn(label: Text("Fecha")),
                  DataColumn(label: Text("Vendedor")),
                  DataColumn(label: Text("Total")),
                  DataColumn(label: Text("Método")),
                  DataColumn(label: Text("Acciones")),
                ],
                rows: _sales.map((sale) {
                  final date = DateTime.parse(sale['created_at']);
                  final seller = _getSellerName(sale['profiles']);
                  
                  return DataRow(cells: [
                    DataCell(Text("#${sale['id'].toString().substring(0, 8)}", style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                    DataCell(Text(DateFormat('dd/MM/yy HH:mm').format(date))),
                    DataCell(Text(seller)),
                    DataCell(Text("\$${(sale['total'] as num).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                      child: const Text("EFECTIVO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    )),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(LucideIcons.receipt, size: 16, color: Colors.white54), onPressed: () {}),
                        IconButton(icon: const Icon(LucideIcons.moreVertical, size: 16, color: Colors.white24), onPressed: () {}),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }
}
