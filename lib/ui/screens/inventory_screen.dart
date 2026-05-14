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
  bool _isLoading = true;
  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _branches = [];
  String _title = "Cargando...";
  Map<String, dynamic>? _myProfile;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    ToastUtils.showPromiseToast(
      context, 
      message: "Consultando inventario...", 
      promise: _fetchInventory(), 
      successMessage: "Inventario actualizado", 
      errorMessage: "Error al sincronizar inventario"
    );
  }

  Future<void> _fetchInventory() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("No autenticado");

      _myProfile = await supabase
          .from('profiles')
          .select('role, tenant_id')
          .eq('id', user.id)
          .single();

      final role = _myProfile!['role'] as String;
      final tenantId = _myProfile!['tenant_id'];

      // Fetch branches for inventory initialization
      final branchesRes = await supabase.from('branches').select('*').eq('tenant_id', tenantId!);
      _branches = List<Map<String, dynamic>>.from(branchesRes);

      var query = supabase.from('products').select('*, inventory(*)');

      if (role == 'superadmin' || role == 'global_it') {
        setState(() => _title = "Stock Global de Red");
      } else {
        setState(() => _title = "Inventario de Sucursal");
        query = query.eq('tenant_id', tenantId);
      }

      final response = await query.order('name', ascending: true);

      if (mounted) {
        setState(() {
          _inventoryItems = List<Map<String, dynamic>>.from(response as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      rethrow;
    }
  }

  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final skuController = TextEditingController();
    final priceController = TextEditingController();
    final categoryController = TextEditingController(text: "General");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: const Text("Registrar Nuevo Producto", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Nombre del Producto", labelStyle: TextStyle(color: Colors.white38)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: skuController,
                decoration: const InputDecoration(labelText: "SKU / Código", labelStyle: TextStyle(color: Colors.white38)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Precio de Venta", labelStyle: TextStyle(color: Colors.white38), prefixText: "\$ "),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: "Categoría", labelStyle: TextStyle(color: Colors.white38)),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _createProduct(nameController.text, skuController.text, double.tryParse(priceController.text) ?? 0.0, categoryController.text);
            },
            child: const Text("Registrar"),
          ),
        ],
      ),
    );
  }

  Future<void> _createProduct(String name, String sku, double price, String category) async {
    ToastUtils.showPromiseToast(
      context, 
      message: "Registrando producto...", 
      promise: _executeProductCreation(name, sku, price, category), 
      successMessage: "Producto registrado exitosamente", 
      errorMessage: "Error al registrar producto"
    );
  }

  Future<void> _executeProductCreation(String name, String sku, double price, String category) async {
    try {
      final supabase = Supabase.instance.client;
      final tenantId = _myProfile?['tenant_id'];

      // 1. Insert product
      final productResponse = await supabase.from('products').insert({
        'name': name,
        'sku': sku,
        'price': price,
        'tenant_id': tenantId,
        'category': category,
      }).select().single();

      // 2. Initialize inventory record for the first branch (if any)
      if (_branches.isNotEmpty) {
        await supabase.from('inventory').insert({
          'tenant_id': tenantId,
          'product_id': productResponse['id'],
          'branch_id': _branches[0]['id'],
          'stock_level': 0,
        });
      }

      _fetchInventory();
    } catch (e) {
      rethrow;
    }
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
                    Text(_title, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text("Gestión centralizada de stock y catálogo.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _loadData(),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text("Sincronizar"),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceLight, foregroundColor: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _showAddProductDialog,
                      icon: const Icon(LucideIcons.plus),
                      label: const Text("Nuevo Producto"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ).animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 48),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: "Buscar por SKU o nombre...",
                        prefixIcon: const Icon(LucideIcons.search, color: Colors.white24, size: 18),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.2),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(64), child: CircularProgressIndicator(color: Colors.red)))
                    else if (_inventoryItems.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(64), child: Text("No hay productos disponibles", style: TextStyle(color: Colors.white24))))
                    else
                      _buildInventoryTable(context),
                  ],
                ),
              ),
            ).animate().fadeIn().slideY(begin: 0.1),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryTable(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
        columns: const [
          DataColumn(label: Text("Producto")),
          DataColumn(label: Text("SKU")),
          DataColumn(label: Text("Precio")),
          DataColumn(label: Text("Stock")),
          DataColumn(label: Text("Acciones")),
        ],
        rows: _inventoryItems.map((item) {
          final String name = item['name'] ?? 'Desconocido';
          final String sku = item['sku'] ?? 'N/A';
          final double priceNum = (item['price'] as num?)?.toDouble() ?? 0.0;
          
          int stock = 0;
          if (item['inventory'] != null && item['inventory'] is List) {
            for (var inv in item['inventory']) {
              stock += (inv['stock_level'] as num?)?.toInt() ?? 0;
            }
          }

          return DataRow(
            cells: [
              DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(sku, style: const TextStyle(color: Colors.white38, fontSize: 12))),
              DataCell(Text("\$${priceNum.toStringAsFixed(2)}")),
              DataCell(Text(stock.toString(), style: TextStyle(color: stock < 5 ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold))),
              DataCell(Row(
                children: [
                  IconButton(icon: const Icon(LucideIcons.packagePlus, size: 16, color: Colors.blueAccent), onPressed: () {}),
                  IconButton(icon: const Icon(LucideIcons.edit, size: 16, color: Colors.white24), onPressed: () {}),
                  IconButton(icon: Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent.withOpacity(0.5)), onPressed: () {}),
                ],
              )),
            ],
          );
        }).toList(),
      ),
    );
  }
}
