import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filteredItems = [];
  List<Map<String, dynamic>> _branches = [];
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
  String? _categoryFilter;
  RealtimeChannel? _realtimeSubscription;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
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
    final cats = _items.map((e) => e['category'] as String?).where((c) => c != null && c!.isNotEmpty).map((c) => c!);
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
        ToastUtils.showErrorToast(context, message: 'Error cargando inventario');
      }
    }
  }

  Future<void> _setupRealtime(String tenantId) async {
    await _realtimeSubscription?.unsubscribe();
    _realtimeSubscription = _supabase
        .channel('inventory-changes')
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
          if (!name.contains(_searchQuery) && !sku.contains(_searchQuery)) return false;
        }
        if (_categoryFilter != null && item['category'] != _categoryFilter) return false;
        return true;
      }).toList();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _filteredItems.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_filteredItems.map((e) => e['id'] as String));
      }
    });
  }

  Future<void> _saveProduct({
    String? id,
    required String name,
    required String sku,
    required String category,
    required double price,
    required int stockLevel,
    required int minStock,
    String location = '',
    String imageUrl = '',
    String? branchId,
  }) async {
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

      final metadata = <String, dynamic>{};
      if (location.isNotEmpty) metadata['location'] = location;
      if (imageUrl.isNotEmpty) metadata['image_url'] = imageUrl;

      if (id == null) {
        await _supabase.from('inventory').insert({
          'tenant_id': tenantId,
          'branch_id': branchId ?? null,
          'name': name,
          'sku': sku,
          'category': category,
          'price': price,
          'stock_level': stockLevel,
          'min_stock': minStock,
          'is_active': true,
          'metadata': metadata,
        });
      } else {
        await _supabase.from('inventory').update({
          'branch_id': branchId ?? null,
          'name': name,
          'sku': sku,
          'category': category,
          'price': price,
          'stock_level': stockLevel,
          'min_stock': minStock,
          'metadata': metadata,
        }).eq('id', id);
      }

      await _loadData();
    } catch (e) {
      rethrow;
    }
  }

  void _showProductForm({Map<String, dynamic>? product}) {
    final isEdit = product != null;
    final nameCtl = TextEditingController(text: isEdit ? product['name'] as String : '');
    final skuCtl = TextEditingController(text: isEdit ? product['sku'] as String : '');
    final priceCtl = TextEditingController(text: isEdit ? product['price'].toString() : '');
    final categoryCtl = TextEditingController(text: isEdit ? product['category'] as String : '');
    final meta = isEdit ? (product['metadata'] as Map<String, dynamic>? ?? {}) : <String, dynamic>{};
    final locationCtl = TextEditingController(text: meta['location'] as String? ?? '');
    final imageUrlCtl = TextEditingController(text: meta['image_url'] as String? ?? '');
    final stockCtl = TextEditingController(text: isEdit ? '${product['stock_level'] ?? 0}' : '');
    final minStockCtl = TextEditingController(text: isEdit ? '${product['min_stock'] ?? 5}' : '5');

    String? selectedBranchId = isEdit ? product['branch_id'] as String? : _branches.isNotEmpty ? _branches[0]['id'] as String : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF121212),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white10),
          ),
          title: Row(
            children: [
              Icon(isEdit ? LucideIcons.edit3 : LucideIcons.plus, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text(
                isEdit ? 'Editar Producto' : 'Nuevo Producto',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(label: 'Nombre', icon: LucideIcons.box, controller: nameCtl),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _dialogField(label: 'SKU', icon: LucideIcons.qrCode, controller: skuCtl)),
                      const SizedBox(width: 12),
                      Expanded(child: _dialogField(label: 'Precio', icon: LucideIcons.dollarSign, controller: priceCtl, isNumber: true)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _dialogField(label: 'Stock', icon: LucideIcons.package, controller: stockCtl, isNumber: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _dialogField(label: 'Stock Mínimo', icon: LucideIcons.alertTriangle, controller: minStockCtl, isNumber: true)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _dialogField(label: 'Categoría', icon: LucideIcons.tag, controller: categoryCtl),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _dialogField(label: 'Ubicación', icon: LucideIcons.mapPin, controller: locationCtl)),
                      const SizedBox(width: 12),
                      Expanded(child: _dialogField(label: 'URL Imagen', icon: LucideIcons.image, controller: imageUrlCtl)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(LucideIcons.warehouse, size: 16, color: Colors.white54),
                      const SizedBox(width: 12),
                      const Text('Sucursal', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedBranchId,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        icon: const Icon(LucideIcons.chevronDown, color: Colors.white38, size: 18),
                        isExpanded: true,
                        hint: const Text('Sin sucursal', style: TextStyle(color: Colors.white38)),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Sin sucursal', style: TextStyle(color: Colors.white38))),
                          ..._branches.map((b) => DropdownMenuItem(
                            value: b['id'] as String,
                            child: Text(b['name'] as String, style: const TextStyle(color: Colors.white)),
                          )),
                        ],
                        onChanged: (v) => setDialogState(() => selectedBranchId = v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                ToastUtils.showPromiseToast(
                  context,
                  message: isEdit ? 'Actualizando producto...' : 'Registrando producto...',
                  promise: _saveProduct(
                    id: isEdit ? product['id'] as String : null,
                    name: nameCtl.text.trim(),
                    sku: skuCtl.text.trim(),
                    category: categoryCtl.text.trim(),
                    price: double.tryParse(priceCtl.text) ?? 0,
                    stockLevel: int.tryParse(stockCtl.text) ?? 0,
                    minStock: int.tryParse(minStockCtl.text) ?? 5,
                    location: locationCtl.text.trim(),
                    imageUrl: imageUrlCtl.text.trim(),
                    branchId: selectedBranchId,
                  ),
                  successMessage: isEdit ? 'Producto actualizado' : 'Producto registrado',
                  errorMessage: 'Error al guardar producto',
                );
              },
              child: Text(isEdit ? 'Guardar Cambios' : 'Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white38),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.red, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmDelete(String id) {
    final item = _items.firstWhere((e) => e['id'] == id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        title: Row(
          children: [
            Icon(LucideIcons.trash2, color: Colors.redAccent, size: 20),
            const SizedBox(width: 12),
            const Text('Eliminar Producto', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Icon(LucideIcons.alertTriangle, size: 48, color: Colors.redAccent.withOpacity(0.8)),
            ),
            const SizedBox(height: 20),
            Text(
              '¿Eliminar "${item['name']}" permanentemente?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text('Esta acción no se puede deshacer.', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ToastUtils.showPromiseToast(
                context,
                message: 'Eliminando producto...',
                promise: _supabase.from('inventory').delete().eq('id', id).then((_) => _loadData()),
                successMessage: 'Producto eliminado',
                errorMessage: 'Error al eliminar producto',
              );
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _confirmBatchDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        title: Row(
          children: [
            Icon(LucideIcons.trash2, color: Colors.redAccent, size: 20),
            const SizedBox(width: 12),
            Text('Eliminar ${_selectedIds.length} productos', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Icon(LucideIcons.package, size: 48, color: Colors.redAccent.withOpacity(0.8)),
            ),
            const SizedBox(height: 20),
            Text(
              '¿Eliminar ${_selectedIds.length} productos permanentemente?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              final ids = _selectedIds.toList();
              ToastUtils.showPromiseToast(
                context,
                message: 'Eliminando productos...',
                promise: Future.wait(ids.map((id) => _supabase.from('inventory').delete().eq('id', id))).then((_) {
                  _selectedIds.clear();
                  return _loadData();
                }),
                successMessage: '${ids.length} productos eliminados',
                errorMessage: 'Error al eliminar productos',
              );
            },
            child: const Text('Eliminar Todo'),
          ),
        ],
      ),
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
            if (_selectedIds.isNotEmpty)
              _buildBatchBar().animate().fadeIn().scale(),
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
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gestión centralizada de stock y catálogo.',
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ],
        ),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Sincronizar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceLight,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () => _showProductForm(),
              icon: const Icon(LucideIcons.plus),
              label: const Text('Nuevo Producto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBatchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_selectedIds.length} producto(s) seleccionado(s)',
            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _confirmBatchDelete,
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: const Text('Eliminar selección'),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _selectedIds.clear()),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        ],
      ),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(color: Colors.red)),
              )
            else if (_filteredItems.isEmpty)
              const EmptyStateWidget(message: 'No hay productos disponibles', icon: LucideIcons.package)
            else
              _buildTable(),
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
        const SizedBox(width: 16),
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
              hint: const Text('Todas las categorías', style: TextStyle(color: Colors.white38, fontSize: 13)),
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
      ],
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 11),
        dataTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        columns: const [
          DataColumn(label: Text('')),
          DataColumn(label: Text('Producto')),
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('Categoría')),
          DataColumn(label: Text('Precio')),
          DataColumn(label: Text('Stock')),
          DataColumn(label: Text('Stock Mín.')),
          DataColumn(label: Text('Acciones')),
        ],
        rows: _filteredItems.map((item) {
          final id = item['id'] as String;
          final name = item['name'] as String? ?? '';
          final sku = item['sku'] as String? ?? '';
          final category = item['category'] as String? ?? '';
          final price = (item['price'] as num?)?.toDouble() ?? 0;
          final stock = (item['stock_level'] as num?)?.toInt() ?? 0;
          final minStock = (item['min_stock'] as num?)?.toInt() ?? 5;
          final meta = item['metadata'] as Map<String, dynamic>?;
          final imageUrl = meta?['image_url'] as String?;
          final isSelected = _selectedIds.contains(id);
          final isLowStock = stock <= minStock;

          return DataRow(
            color: WidgetStateProperty.resolveWith<Color?>((_) => isSelected ? Colors.red.withOpacity(0.05) : null),
            cells: [
              DataCell(
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelect(id),
                    activeColor: Colors.red,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
              DataCell(
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              width: 34,
                              height: 34,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 34,
                                height: 34,
                                color: Colors.white10,
                                child: const Icon(LucideIcons.box, size: 16, color: Colors.white38),
                              ),
                            )
                          : Container(
                              width: 34,
                              height: 34,
                              color: Colors.white10,
                              child: const Icon(LucideIcons.box, size: 16, color: Colors.white38),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              DataCell(Text(sku, style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace'))),
              DataCell(Text(category, style: const TextStyle(color: Colors.white54))),
              DataCell(Text('\$${price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLowStock ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    stock.toString(),
                    style: TextStyle(
                      color: isLowStock ? Colors.redAccent : Colors.greenAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              DataCell(Text(minStock.toString(), style: const TextStyle(color: Colors.white38))),
              DataCell(Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.edit3, size: 16, color: Colors.blueAccent),
                    tooltip: 'Editar',
                    onPressed: () => _showProductForm(product: item),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent.withOpacity(0.7)),
                    tooltip: 'Eliminar',
                    onPressed: () => _confirmDelete(id),
                  ),
                ],
              )),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class EmptyStateWidget extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyStateWidget({
    super.key,
    this.message = 'No hay datos disponibles',
    this.icon = LucideIcons.inbox,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white.withOpacity(0.03)),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white24, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
