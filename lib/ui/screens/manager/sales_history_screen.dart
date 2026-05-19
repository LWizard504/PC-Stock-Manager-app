import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pc_dev_flutter/ui/widgets/skeleton_loader.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _sales = [];
  bool _isLoading = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  Future<void> _fetchSales() async {
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
              .select('id, total, created_at, seller_id, branch_id, profiles!seller_id(full_name), branches!branch_id(name)')
              .eq('tenant_id', tenantId)
              .order('created_at', ascending: false);

          setState(() {
            _sales = List<Map<String, dynamic>>.from(data);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching sales: $e");
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
    final filteredSales = _sales.where((sale) {
      final idStr = sale['id'].toString();
      final len = idStr.length;
      final receiptId = "RCPT-${idStr.substring(0, len.clamp(0, 8))}".toLowerCase();
      final sellerName = (sale['profiles']?['full_name'] ?? 'Unknown').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return receiptId.contains(query) || sellerName.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Historial de Ventas",
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Registro global e histórico de todas las transacciones POS.",
                      style: TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw, color: AppTheme.primaryColor),
                  onPressed: _fetchSales,
                  tooltip: "Actualizar",
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Search Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(LucideIcons.search, color: Colors.white54),
                      hintText: "Buscar por recibo o cajero...",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF0F0F0F),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF1E1E1E)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF1E1E1E)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primaryColor),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: SkeletonLoader.table(rows: 6, columns: 5),
                    )
                  : filteredSales.isEmpty
                      ? Card(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(LucideIcons.history, size: 64, color: AppTheme.secondaryColor),
                                SizedBox(height: 16),
                                Text(
                                  "No se detectaron transacciones registradas.",
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
                                    DataColumn(label: Text("Recibo", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    DataColumn(label: Text("Cajero", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    DataColumn(label: Text("Sucursal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    DataColumn(label: Text("Monto", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    DataColumn(label: Text("Fecha", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                  ],
                                  rows: filteredSales.map((sale) {
                                    final rawId = sale['id'].toString();
                                    final receiptId = "RCPT-${rawId.substring(0, rawId.length.clamp(0, 8))}".toUpperCase();
                                    final sellerName = sale['profiles']?['full_name'] ?? 'Unknown Operative';
                                    final branchName = sale['branches']?['name'] ?? 'Primary Node';
                                    final total = double.tryParse(sale['total'].toString()) ?? 0.0;
                                    
                                    final dateString = sale['created_at'] != null 
                                      ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(sale['created_at']))
                                      : 'N/A';

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(receiptId, style: const TextStyle(color: AppTheme.primaryColor, fontFamily: 'monospace'))),
                                        DataCell(Text(sellerName, style: const TextStyle(color: Colors.white))),
                                        DataCell(Text(branchName, style: const TextStyle(color: Colors.white70))),
                                        DataCell(
                                          Text(
                                            "\$${total.toStringAsFixed(2)}",
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.black,
                                              color: total >= 0 ? Colors.greenAccent : Colors.redAccent,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(dateString, style: const TextStyle(color: Colors.white54, fontSize: 12))),
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
