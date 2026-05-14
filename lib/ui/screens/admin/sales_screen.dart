import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';
import 'package:intl/intl.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  double _totalRevenue = 0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSales();
    _searchController.addListener(_filterSales);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          _filteredSales = sales;
          _totalRevenue = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterSales() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredSales = _sales.where((s) {
        final seller = _getSellerName(s['profiles']).toLowerCase();
        final id = s['id'].toString().toLowerCase();
        return seller.contains(query) || id.contains(query);
      }).toList();
    });
  }

  String _getSellerName(dynamic profile) {
    if (profile == null) return "N/A";
    String name = profile['full_name'] ?? '';
    if (name.isEmpty) {
      name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? "System" : name;
  }

  void _exportPDF() {
    ToastUtils.showToast(context, message: "Generating PDF Ledger...");
    // Logic for PDF generation will go here after package install
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocaleProvider>(context).t;

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
                    Text("Sales Ledger", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text("Corporate transaction record and fiscal sync logs.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                Row(
                  children: [
                    _buildRevenueBadge(),
                    const SizedBox(width: 24),
                    ElevatedButton.icon(
                      onPressed: _exportPDF,
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: const Text("Export PDF"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  ],
                ),
              ],
            ).animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 48),
            
            _buildFilters(t),
            const SizedBox(height: 32),
            
            _buildSalesTable(t),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text("TOTAL REVENUE", style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.black, letterSpacing: 1.2)),
          Text("\$${NumberFormat("#,##0.00").format(_totalRevenue)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
        ],
      ),
    );
  }

  Widget _buildFilters(String Function(String) t) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search by ID or seller identity...",
              prefixIcon: const Icon(LucideIcons.search, color: Colors.white24, size: 18),
              filled: true,
              fillColor: AppTheme.surfaceDark,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          onPressed: _fetchSales,
          icon: const Icon(LucideIcons.refreshCw, size: 18, color: Colors.white38),
          tooltip: t('refresh'),
        ),
      ],
    );
  }

  Widget _buildSalesTable(String Function(String) t) {
    if (_isLoading) return const Center(child: Padding(padding: EdgeInsets.all(64), child: CircularProgressIndicator(color: Colors.red)));
    if (_filteredSales.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(64), child: Text("No entries found in ledger", style: TextStyle(color: Colors.white24))));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Global Sales Stream", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white70)),
            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(color: Colors.white38, fontWeight: FontWeight.black, fontSize: 10, letterSpacing: 1),
                columns: const [
                  DataColumn(label: Text("RECEIPT ID")),
                  DataColumn(label: Text("TIMESTAMP")),
                  DataColumn(label: Text("OPERATIVE")),
                  DataColumn(label: Text("VALUATION")),
                  DataColumn(label: Text("STATUS")),
                  DataColumn(label: Text("ACTIONS")),
                ],
                rows: _filteredSales.map((sale) {
                  final date = DateTime.parse(sale['created_at']);
                  final seller = _getSellerName(sale['profiles']);
                  
                  return DataRow(cells: [
                    DataCell(Text("#${sale['id'].toString().substring(0, 8)}", style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70))),
                    DataCell(Text(DateFormat('MMM dd, HH:mm').format(date).toUpperCase(), style: const TextStyle(fontSize: 11))),
                    DataCell(Text(seller, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataCell(Text("\$${(sale['total'] as num).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primaryColor))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.withOpacity(0.2))),
                      child: const Text("SYNCED", style: TextStyle(fontSize: 8, fontWeight: FontWeight.black, color: Colors.green)),
                    )),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(LucideIcons.receipt, size: 14, color: Colors.white38), onPressed: () {}),
                        IconButton(icon: const Icon(LucideIcons.share2, size: 14, color: Colors.white24), onPressed: () {}),
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
