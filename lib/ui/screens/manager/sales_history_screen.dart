import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pc_dev_flutter/ui/widgets/skeleton_loader.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 20;
  String _searchQuery = "";

  DateTime? _startDate;
  DateTime? _endDate;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  String? _cachedTenantId;

  Future<void> _fetchSales() async {
    setState(() {
      _isLoading = true;
      _page = 0;
      _hasMore = true;
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
        _cachedTenantId = tenantId;
        if (tenantId != null) {
          await _loadPage(tenantId, 0, true);
        }
      }
    } catch (e) {
      debugPrint("Error fetching sales: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPage(String tenantId, int page, bool replace) async {
    try {
      var query = _supabase
          .from('sales')
          .select('id, total_amount, created_at, seller_id, branch_id, status, profiles!seller_id(full_name), branches!branch_id(name)')
          .eq('tenant_id', tenantId);

      if (_startDate != null) {
        query = query.gte('created_at', _startDate!.toIso8601String());
      }
      if (_endDate != null) {
        query = query.lte('created_at', _endDate!.add(const Duration(days: 1)).toIso8601String());
      }
      if (_statusFilter != 'all') {
        query = query.eq('status', _statusFilter);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(page * _pageSize, (page + 1) * _pageSize - 1);

      if (mounted) {
        final fetched = List<Map<String, dynamic>>.from(data);

        for (var sale in fetched) {
          try {
            final itemsResult = await _supabase
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

        setState(() {
          if (replace) {
            _sales = fetched;
          } else {
            _sales.addAll(fetched);
          }
          _page = page;
          _hasMore = fetched.length >= _pageSize;
          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint("Error loading page: $e");
    }
  }

  void _applyFilters() {
    _filteredSales = _sales.where((sale) {
      final idStr = sale['id'].toString();
      final len = idStr.length;
      final receiptId = "RCPT-${idStr.substring(0, len.clamp(0, 8))}".toLowerCase();
      final sellerName = (sale['profiles']?['full_name'] ?? 'Unknown').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return receiptId.contains(query) || sellerName.contains(query);
    }).toList();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _cachedTenantId == null) return;
    setState(() => _isLoadingMore = true);
    await _loadPage(_cachedTenantId!, _page + 1, false);
    if (mounted) setState(() => _isLoadingMore = false);
  }

  double get _totalRevenue {
    return _filteredSales.fold(0.0, (sum, s) => sum + (double.tryParse(s['total_amount'].toString()) ?? 0.0));
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
      _fetchSales();
    }
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
              _detailRow("Cajero", sale['profiles']?['full_name'] ?? 'Unknown'),
              _detailRow("Sucursal", sale['branches']?['name'] ?? 'N/A'),
              _detailRow("Fecha", sale['created_at'] != null
                  ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(sale['created_at']))
                  : 'N/A'),
              _detailRow("Total", "\$${(double.tryParse(sale['total_amount'].toString()) ?? 0.0).toStringAsFixed(2)}"),
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

  Future<void> _exportPDF() async {
    try {
      ToastUtils.showCustomToast(context, "Generando PDF...");

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('Sales History Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Paragraph(text: 'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
            pw.SizedBox(height: 8),
            pw.Paragraph(text: 'Total Revenue: \$${_totalRevenue.toStringAsFixed(2)}'),
            pw.Paragraph(text: 'Total Transactions: ${_filteredSales.length}'),
            pw.SizedBox(height: 24),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: pw.TextStyle(fontSize: 9),
              headers: ['Receipt', 'Cashier', 'Branch', 'Amount', 'Date', 'Status'],
              data: _filteredSales.map((s) {
                final rawId = s['id'].toString();
                final receiptId = "RCPT-${rawId.substring(0, rawId.length.clamp(0, 8))}".toUpperCase();
                final dateStr = s['created_at'] != null
                    ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(s['created_at']))
                    : 'N/A';
                return [
                  receiptId,
                  s['profiles']?['full_name'] ?? 'Unknown',
                  s['branches']?['name'] ?? 'Primary Node',
                  '\$${(double.tryParse(s['total_amount'].toString()) ?? 0.0).toStringAsFixed(2)}',
                  dateStr,
                  (s['status']?.toString() ?? 'completed').toUpperCase(),
                ];
              }).toList(),
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'sales_history_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );

      if (mounted) ToastUtils.showSuccessToast(context, message: "PDF exportado exitosamente");
    } catch (e) {
      if (mounted) ToastUtils.showErrorToast(context, message: "Error al exportar PDF: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredSales = _filteredSales;

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
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _exportPDF,
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: const Text("Exportar PDF"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(LucideIcons.refreshCw, color: AppTheme.primaryColor),
                      onPressed: _fetchSales,
                      tooltip: "Actualizar",
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildRevenueSummary(),
            const SizedBox(height: 20),
            _buildFilters(),
            const SizedBox(height: 20),
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
                      : Column(
                          children: [
                            Expanded(
                              child: Card(
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
                                          DataColumn(label: Text("Estado", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                          DataColumn(label: Text("Fecha", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                        ],
                                        rows: filteredSales.map((sale) {
                                          final rawId = sale['id'].toString();
                                          final receiptId = "RCPT-${rawId.substring(0, rawId.length.clamp(0, 8))}".toUpperCase();
                                          final sellerName = sale['profiles']?['full_name'] ?? 'Unknown Operative';
                                          final branchName = sale['branches']?['name'] ?? 'Primary Node';
                                          final total = double.tryParse(sale['total_amount'].toString()) ?? 0.0;
                                          final saleStatus = sale['status']?.toString() ?? 'completed';

                                          final dateString = sale['created_at'] != null
                                              ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(sale['created_at']))
                                              : 'N/A';

                                          return DataRow(
                                            onSelectChanged: (_) => _showSaleDetail(sale),
                                            cells: [
                                              DataCell(Text(receiptId, style: const TextStyle(color: AppTheme.primaryColor, fontFamily: 'monospace'))),
                                              DataCell(Text(sellerName, style: const TextStyle(color: Colors.white))),
                                              DataCell(Text(branchName, style: const TextStyle(color: Colors.white70))),
                                              DataCell(
                                                Text(
                                                  "\$${total.toStringAsFixed(2)}",
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w900,
                                                    color: total >= 0 ? Colors.greenAccent : Colors.redAccent,
                                                  ),
                                                ),
                                              ),
                                              DataCell(_buildStatusChip(saleStatus)),
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
                            if (_hasMore)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _isLoadingMore ? null : _loadMore,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white54,
                                      side: const BorderSide(color: Colors.white10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    child: _isLoadingMore
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(LucideIcons.chevronDown, size: 18),
                                              SizedBox(width: 8),
                                              Text("Cargar más registros"),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(LucideIcons.dollarSign, color: Colors.greenAccent, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Ingresos Totales", style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  "\$${_totalRevenue.toStringAsFixed(2)}",
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text("Transacciones", style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  "${filteredSales.length}",
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }

  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (val) {
              setState(() => _searchQuery = val);
              _applyFilters();
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
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(LucideIcons.calendar, size: 16),
          label: Text(
            _startDate != null && _endDate != null
                ? '${DateFormat('dd/MM').format(_startDate!)} - ${DateFormat('dd/MM').format(_endDate!)}'
                : 'Fechas',
            style: const TextStyle(fontSize: 12),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white54,
            side: const BorderSide(color: Colors.white10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _statusFilter,
              dropdownColor: const Color(0xFF1A1A1A),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'completed', child: Text('Completadas')),
                DropdownMenuItem(value: 'voided', child: Text('Anuladas')),
                DropdownMenuItem(value: 'refunded', child: Text('Reembolsadas')),
              ],
              onChanged: (val) {
                setState(() => _statusFilter = val ?? 'all');
                _fetchSales();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    Color chipColor;
    String label;
    switch (status) {
      case 'voided':
        chipColor = Colors.red;
        label = 'ANULADA';
        break;
      case 'refunded':
        chipColor = Colors.orange;
        label = 'REEMBOLSADA';
        break;
      default:
        chipColor = Colors.green;
        label = 'COMPLETADA';
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

  List<Map<String, dynamic>> get filteredSales => _filteredSales;
}
