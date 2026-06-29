import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/skeleton_loader.dart';
import 'package:intl/intl.dart';

class InventoryViewScreen extends StatefulWidget {
  const InventoryViewScreen({super.key});

  @override
  State<InventoryViewScreen> createState() => _InventoryViewScreenState();
}

class _InventoryViewScreenState extends State<InventoryViewScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filteredItems = [];
  List<Map<String, dynamic>> _branches = [];
  String _searchQuery = '';
  String? _categoryFilter;
  String? _branchFilter;
  RealtimeChannel? _realtimeSubscription;

  final TextEditingController _searchController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _applyFilters();
    });
  }

  @override
  void dispose() {
    _realtimeSubscription?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final cats = _items
        .map((e) => e['category'] as String?)
        .where((c) => c != null && c!.isNotEmpty)
        .map((c) => c!);
    return cats.toSet().toList()..sort();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No session');

      final profile = await _supabase
          .from('profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .single();
      final tenantId = profile['tenant_id'];
      if (tenantId == null) throw Exception('No tenant');

      final itemsRes = await _supabase
          .from('inventory')
          .select('*, branches(name)')
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .order('name');
      final branchRes = await _supabase
          .from('branches')
          .select('id, name')
          .eq('tenant_id', tenantId)
          .order('created_at');

      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(itemsRes);
          _branches = List<Map<String, dynamic>>.from(branchRes);
          _isLoading = false;
        });
        _applyFilters();
      }

      await _setupRealtime(tenantId);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _setupRealtime(String tenantId) async {
    await _realtimeSubscription?.unsubscribe();
    _realtimeSubscription = _supabase
        .channel('employee-inventory-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory',
          callback: (_) => _loadData(),
        )
        .subscribe();
  }

  void _applyFilters() {
    setState(() {
      _filteredItems = _items.where((item) {
        if (_searchQuery.isNotEmpty) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          final sku = (item['sku'] ?? '').toString().toLowerCase();
          if (!name.contains(_searchQuery) && !sku.contains(_searchQuery)) {
            return false;
          }
        }
        if (_categoryFilter != null && item['category'] != _categoryFilter) {
          return false;
        }
        if (_branchFilter != null && item['branch_id'] != _branchFilter) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  Color _stockColor(int stock, int minStock) {
    if (stock < minStock) return Colors.redAccent;
    if (stock == minStock) return Colors.amberAccent;
    return Colors.greenAccent;
  }

  Color _stockBgColor(int stock, int minStock) {
    if (stock < minStock) return Colors.red.withOpacity(0.15);
    if (stock == minStock) return Colors.amber.withOpacity(0.12);
    return Colors.green.withOpacity(0.1);
  }

  String _stockLabel(int stock, int minStock) {
    if (stock < minStock) return 'Bajo Stock';
    if (stock == minStock) return 'Stock Mínimo';
    return 'En Stock';
  }

  void _showDetailModal(Map<String, dynamic> item) {
    final meta = item['metadata'] as Map<String, dynamic>? ?? {};
    final branch = item['branches'] as Map<String, dynamic>?;
    final stock = (item['stock_level'] as num?)?.toInt() ?? 0;
    final minStock = (item['min_stock'] as num?)?.toInt() ?? 5;
    final price = (item['price'] as num?)?.toDouble() ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.box, color: Colors.white38, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] as String? ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['sku'] as String? ?? '',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _detailRow(LucideIcons.tag, 'Categoría', item['category'] as String? ?? '-'),
                const SizedBox(height: 16),
                _detailRow(LucideIcons.dollarSign, 'Precio', _currencyFormat.format(price)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _detailRow(
                        LucideIcons.package,
                        'Stock',
                        stock.toString(),
                        valueColor: _stockColor(stock, minStock),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _detailRow(LucideIcons.alertTriangle, 'Stock Mínimo', minStock.toString()),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _detailRow(LucideIcons.mapPin, 'Ubicación', meta['location'] as String? ?? '-'),
                const SizedBox(height: 16),
                _detailRow(
                  LucideIcons.warehouse,
                  'Sucursal',
                  branch != null ? branch['name'] as String? ?? '-' : '-',
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _stockBgColor(stock, minStock),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _stockColor(stock, minStock).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        stock < minStock
                            ? LucideIcons.alertTriangle
                            : stock == minStock
                                ? LucideIcons.info
                                : LucideIcons.checkCircle2,
                        color: _stockColor(stock, minStock),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _stockLabel(stock, minStock),
                        style: TextStyle(
                          color: _stockColor(stock, minStock),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
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
            _buildHeader().animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 24),
            _buildMainCard().animate().fadeIn().slideY(begin: 0.1),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inventario',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Consulta de stock y productos.',
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _loadData,
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: const Text('Sincronizar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.surfaceLight,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildMainCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildToolbar(),
            const SizedBox(height: 24),
            if (_isLoading)
              _buildSkeletonGrid()
            else if (_filteredItems.isEmpty)
              _buildEmptyState()
            else
              _buildGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o SKU...',
              prefixIcon: const Icon(LucideIcons.search, size: 18, color: Colors.white24),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _categoryFilter,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              hint: const Text('Categoría', style: TextStyle(color: Colors.white38, fontSize: 13)),
              icon: const Icon(LucideIcons.chevronDown, color: Colors.white38, size: 16),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas las categorías')),
                ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (v) {
                setState(() => _categoryFilter = v);
                _applyFilters();
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _branchFilter,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              hint: const Text('Sucursal', style: TextStyle(color: Colors.white38, fontSize: 13)),
              icon: const Icon(LucideIcons.chevronDown, color: Colors.white38, size: 16),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas las sucursales')),
                ..._branches.map((b) => DropdownMenuItem(
                  value: b['id'] as String,
                  child: Text(b['name'] as String),
                )),
              ],
              onChanged: (v) {
                setState(() => _branchFilter = v);
                _applyFilters();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        childAspectRatio: 0.85,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: 8,
      itemBuilder: (context, index) {
        return const SkeletonLoader(width: double.infinity, height: double.infinity, borderRadius: 20);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.package, size: 64, color: Colors.white.withOpacity(0.03)),
            const SizedBox(height: 16),
            const Text(
              'No hay productos disponibles',
              style: TextStyle(color: Colors.white24, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        childAspectRatio: 0.85,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) => _buildProductCard(_filteredItems[index]),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item) {
    final stock = (item['stock_level'] as num?)?.toInt() ?? 0;
    final minStock = (item['min_stock'] as num?)?.toInt() ?? 5;
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final meta = item['metadata'] as Map<String, dynamic>?;

    return InkWell(
      onTap: () => _showDetailModal(item),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(14),
                  image: meta?['image_url'] != null
                      ? DecorationImage(
                          image: NetworkImage(meta!['image_url'] as String),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: meta?['image_url'] == null
                    ? const Icon(LucideIcons.package, color: Colors.white12, size: 36)
                    : null,
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] as String? ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item['sku'] as String? ?? '',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (item['category'] != null && (item['category'] as String).isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item['category'] as String,
                          style: TextStyle(
                            color: AppTheme.primaryColor.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currencyFormat.format(price),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _stockBgColor(stock, minStock),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _stockColor(stock, minStock),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                stock.toString(),
                                style: TextStyle(
                                  color: _stockColor(stock, minStock),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scale(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1, 1),
          duration: 300.ms,
        );
  }
}
