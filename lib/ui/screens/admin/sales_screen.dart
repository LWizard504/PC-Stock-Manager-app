import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  DateTime? _startDate;
  DateTime? _endDate;
  String _statusFilter = 'all';

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

      var query = supabase.from('sales').select('*, profiles!seller_id(full_name, first_name, last_name), branches!branch_id(name)');

      if (tenantId != null) {
        query = query.eq('tenant_id', tenantId);
      }

      final response = await query.order('created_at', ascending: false);

      if (mounted) {
        final sales = List<Map<String, dynamic>>.from(response);

        for (var sale in sales) {
          try {
            final itemsResult = await supabase
                .from('sale_items')
                .select('id, quantity, price')
                .eq('sale_id', sale['id']);
            sale['_items'] = itemsResult;
            sale['_itemsCount'] = itemsResult.length;
          } catch (_) {
            sale['_items'] = [];
            sale['_itemsCount'] = 0;
          }
        }

        final total = sales.fold(0.0, (sum, s) => sum + ((s['total_amount'] as num?)?.toDouble() ?? 0.0));

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
        final queryMatch = seller.contains(query) || id.contains(query);

        bool dateMatch = true;
        if (_startDate != null && s['created_at'] != null) {
          final saleDate = DateTime.parse(s['created_at']);
          dateMatch = saleDate.isAfter(_startDate!.subtract(const Duration(days: 1)));
        }
        if (_endDate != null && s['created_at'] != null && dateMatch) {
          final saleDate = DateTime.parse(s['created_at']);
          dateMatch = saleDate.isBefore(_endDate!.add(const Duration(days: 1)));
        }

        bool statusMatch = true;
        if (_statusFilter != 'all') {
          final saleStatus = s['status']?.toString() ?? 'completed';
          statusMatch = saleStatus == _statusFilter;
        }

        return queryMatch && dateMatch && statusMatch;
      }).toList();
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primaryColor,
            surface: Color(0xFF1A1A1A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _filterSales();
    }
  }

  Future<void> _exportPDF() async {
    try {
      ToastUtils.showCustomToast(context, "Generando reporte PDF...");

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('Sales Ledger Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Paragraph(text: 'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
            pw.SizedBox(height: 16),
            pw.Paragraph(text: 'Total Revenue: \$${_totalRevenue.toStringAsFixed(2)}'),
            pw.Paragraph(text: 'Total Transactions: ${_filteredSales.length}'),
            pw.SizedBox(height: 24),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: pw.TextStyle(fontSize: 9),
              headers: ['Receipt ID', 'Date', 'Seller', 'Branch', 'Items', 'Total', 'Status'],
              data: _filteredSales.map((s) {
                final date = s['created_at'] != null
                    ? DateFormat('MMM dd, HH:mm').format(DateTime.parse(s['created_at']))
                    : 'N/A';
                final idStr = s['id'].toString();
                final receiptId = '#${idStr.substring(0, idStr.length.clamp(0, 8))}';
                return [
                  receiptId,
                  date,
                  _getSellerName(s['profiles']),
                  s['branches']?['name'] ?? 'N/A',
                  '${s['_itemsCount'] ?? 0}',
                  '\$${((s['total_amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                  (s['status']?.toString() ?? 'completed').toUpperCase(),
                ];
              }).toList(),
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'sales_ledger_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );

      if (mounted) ToastUtils.showSuccessToast(context, message: "PDF exportado exitosamente");
    } catch (e) {
      if (mounted) ToastUtils.showErrorToast(context, message: "Error al exportar PDF: $e");
    }
  }

  String _getSellerName(dynamic profile) {
    if (profile == null) return "N/A";
    String name = profile['full_name'] ?? '';
    if (name.isEmpty) {
      name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? "System" : name;
  }

  void _showSaleDetail(Map<String, dynamic> sale) {
    final items = List<Map<String, dynamic>>.from(sale['_items'] ?? []);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.receipt, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Detalle de Venta #${sale['id'].toString().substring(0, 8)}",
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Cajero", _getSellerName(sale['profiles'])),
              _detailRow("Sucursal", sale['branches']?['name'] ?? 'N/A'),
              _detailRow("Fecha", sale['created_at'] != null
                  ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(sale['created_at']))
                  : 'N/A'),
              _detailRow("Total", "\$${((sale['total_amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}"),
              _detailRow("Estado", sale['status']?.toString() ?? 'completed'),
              const SizedBox(height: 16),
              const Text("Artículos:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Text("No hay artículos registrados.", style: TextStyle(color: Colors.white38))
              else
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Item: ${item['id']?.toString().substring(0, 8) ?? 'N/A'}  x${item['quantity'] ?? item['qty'] ?? 1}  \$${((item['price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cerrar", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _voidSale(Map<String, dynamic> sale) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Anular Venta", style: TextStyle(color: Colors.white)),
        content: Text(
          "¿Estás seguro de anular la venta #${sale['id'].toString().substring(0, 8)}? Esta acción no se puede deshacer.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Anular", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('sales').update({'status': 'voided'}).eq('id', sale['id']);
      ToastUtils.showSuccessToast(context, message: "Venta anulada exitosamente");
      _fetchSales();
    } catch (e) {
      ToastUtils.showErrorToast(context, message: "Error al anular venta: $e");
    }
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
          const Text("TOTAL REVENUE", style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          Text("\$${NumberFormat("#,##0.00").format(_totalRevenue)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
        ],
      ),
    );
  }

  Widget _buildFilters(String Function(String) t) {
    return Row(
      children: [
        Expanded(
          flex: 3,
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
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(LucideIcons.calendar, size: 16),
          label: Text(
            _startDate != null && _endDate != null
                ? '${DateFormat('dd/MM').format(_startDate!)} - ${DateFormat('dd/MM').format(_endDate!)}'
                : 'Date range',
            style: const TextStyle(fontSize: 12),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white54,
            side: const BorderSide(color: Colors.white10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _statusFilter,
              dropdownColor: const Color(0xFF1A1A1A),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Status')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'voided', child: Text('Voided')),
                DropdownMenuItem(value: 'refunded', child: Text('Refunded')),
              ],
              onChanged: (val) {
                setState(() => _statusFilter = val ?? 'all');
                _filterSales();
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
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
                headingTextStyle: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1),
                columns: const [
                  DataColumn(label: Text("RECEIPT ID")),
                  DataColumn(label: Text("TIMESTAMP")),
                  DataColumn(label: Text("OPERATIVE")),
                  DataColumn(label: Text("BRANCH")),
                  DataColumn(label: Text("ITEMS")),
                  DataColumn(label: Text("VALUATION")),
                  DataColumn(label: Text("STATUS")),
                  DataColumn(label: Text("ACTIONS")),
                ],
                rows: _filteredSales.map((sale) {
                  final date = DateTime.parse(sale['created_at']);
                  final seller = _getSellerName(sale['profiles']);
                  final branchName = sale['branches']?['name'] ?? 'N/A';
                  final itemsCount = sale['_itemsCount'] ?? 0;
                  final saleStatus = sale['status']?.toString() ?? 'completed';
                  final isVoided = saleStatus == 'voided' || saleStatus == 'refunded';

                  return DataRow(
                    onSelectChanged: (_) => _showSaleDetail(sale),
                    cells: [
                      DataCell(Text("#${sale['id'].toString().substring(0, 8)}", style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70))),
                      DataCell(Text(DateFormat('MMM dd, HH:mm').format(date).toUpperCase(), style: const TextStyle(fontSize: 11))),
                      DataCell(Text(seller, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataCell(Text(branchName, style: const TextStyle(fontSize: 11, color: Colors.white70))),
                      DataCell(Text('$itemsCount', style: const TextStyle(fontSize: 11))),
                      DataCell(Text(
                        "\$${((sale['total_amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}",
                        style: TextStyle(fontWeight: FontWeight.w900, color: isVoided ? Colors.red : AppTheme.primaryColor),
                      )),
                      DataCell(_buildStatusChip(saleStatus)),
                      DataCell(Row(
                        children: [
                          IconButton(icon: const Icon(LucideIcons.receipt, size: 14, color: Colors.white38), onPressed: () => _showSaleDetail(sale)),
                          if (!isVoided)
                            IconButton(icon: const Icon(LucideIcons.xCircle, size: 14, color: Colors.white24), onPressed: () => _voidSale(sale)),
                        ],
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildStatusChip(String status) {
    Color chipColor;
    String label;
    switch (status) {
      case 'voided':
        chipColor = Colors.red;
        label = 'VOIDED';
        break;
      case 'refunded':
        chipColor = Colors.orange;
        label = 'REFUNDED';
        break;
      default:
        chipColor = Colors.green;
        label = 'COMPLETED';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: chipColor.withOpacity(0.2)),
      ),
      child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: chipColor)),
    );
  }
}
