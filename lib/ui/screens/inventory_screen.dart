import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/services/offline_sync_manager.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  List<Map<String, dynamic>> _branches = [];
  String _title = "Cargando...";
  Map<String, dynamic>? _myProfile;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterInventory);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    if (!mounted) return;
    setState(() => _isLoading = true);
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

      // Fetch branches deterministically
      final branchesRes = await supabase.from('branches').select('*').eq('tenant_id', tenantId).order('created_at', ascending: true);
      _branches = List<Map<String, dynamic>>.from(branchesRes);

      var query = supabase.from('products').select('*, inventory(*)');

      if (role == 'superadmin' || role == 'global_it') {
        if (mounted) setState(() => _title = "Stock Global de Red");
      } else {
        if (mounted) setState(() => _title = "Inventario de Sucursal");
        query = query.eq('tenant_id', tenantId);
      }

      final response = await query.order('name', ascending: true);

      if (mounted) {
        setState(() {
          _inventoryItems = List<Map<String, dynamic>>.from(response as List);
          _filteredItems = List.from(_inventoryItems);
          _isLoading = false;
        });
        _filterInventory();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      rethrow;
    }
  }

  void _filterInventory() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = List.from(_inventoryItems);
      } else {
        _filteredItems = _inventoryItems.where((item) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          final sku = (item['sku'] ?? '').toString().toLowerCase();
          return name.contains(query) || sku.contains(query);
        }).toList();
      }
    });
  }

  void _showProductForm({Map<String, dynamic>? product}) {
    final bool isEdit = product != null;
    
    final nameController = TextEditingController(text: isEdit ? product['name'] : '');
    final skuController = TextEditingController(text: isEdit ? product['sku'] : '');
    final priceController = TextEditingController(text: isEdit ? product['price'].toString() : '');
    final categoryController = TextEditingController(text: isEdit ? product['category'] : 'General');
    
    final meta = isEdit ? (product['metadata'] as Map<String, dynamic>? ?? {}) : {};
    final locationController = TextEditingController(text: meta['location'] ?? '');
    final expirationController = TextEditingController(text: meta['expiration_date'] ?? '');
    final imageUrlController = TextEditingController(text: meta['image_url'] ?? '');
    
    int initialStock = 0;
    if (isEdit && product['inventory'] != null && (product['inventory'] as List).isNotEmpty) {
      initialStock = (product['inventory'][0]['stock_level'] as num?)?.toInt() ?? 0;
    }
    final quantityController = TextEditingController(text: initialStock.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: Text(isEdit ? "Editar Producto" : "Registrar Nuevo Producto", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Nombre del Producto", labelStyle: TextStyle(color: Colors.white38)),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: skuController,
                        decoration: const InputDecoration(labelText: "SKU / Código", labelStyle: TextStyle(color: Colors.white38)),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Precio de Venta", labelStyle: TextStyle(color: Colors.white38), prefixText: "\$ "),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: categoryController,
                        decoration: const InputDecoration(labelText: "Categoría", labelStyle: TextStyle(color: Colors.white38)),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: quantityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Stock Inicial/Actual", labelStyle: TextStyle(color: Colors.white38)),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: locationController,
                        decoration: const InputDecoration(labelText: "Ubicación (Pasillo/Estante)", labelStyle: TextStyle(color: Colors.white38)),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: expirationController,
                        decoration: const InputDecoration(labelText: "Fecha Caducidad", labelStyle: TextStyle(color: Colors.white38)),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: imageUrlController,
                  decoration: const InputDecoration(labelText: "URL de la Imagen", labelStyle: TextStyle(color: Colors.white38)),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isEdit ? Colors.blueAccent : Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _submitProduct(
                id: isEdit ? product['id'] : null,
                name: nameController.text, 
                sku: skuController.text, 
                price: double.tryParse(priceController.text) ?? 0.0, 
                category: categoryController.text,
                quantity: int.tryParse(quantityController.text) ?? 0,
                location: locationController.text,
                expirationDate: expirationController.text,
                imageUrl: imageUrlController.text
              );
            },
            child: Text(isEdit ? "Guardar Cambios" : "Registrar"),
          ),
        ],
      ),
    );
  }

  Future<void> _submitProduct({
    String? id,
    required String name, 
    required String sku, 
    required double price, 
    required String category,
    required int quantity,
    required String location,
    required String expirationDate,
    required String imageUrl,
  }) async {
    ToastUtils.showPromiseToast(
      context, 
      message: id == null ? "Registrando producto..." : "Actualizando producto...", 
      promise: _executeProductSubmit(id, name, sku, price, category, quantity, location, expirationDate, imageUrl), 
      successMessage: id == null ? "Producto registrado exitosamente" : "Producto actualizado", 
      errorMessage: "Error en la operación"
    );
  }

  Future<void> _executeProductSubmit(String? id, String name, String sku, double price, String category, int quantity, String location, String expirationDate, String imageUrl) async {
    final tenantId = _myProfile?['tenant_id'];
    final branchId = _branches.isNotEmpty ? _branches[0]['id'] : null;

    final productData = {
      'name': name,
      'sku': sku,
      'price': price,
      'category': category,
      'metadata': {
        'location': location,
        'expiration_date': expirationDate,
        'image_url': imageUrl
      }
    };

    final type = id == null ? 'insert_product' : 'update_product';
    final payload = {
      'id': id,
      'product_data': productData,
      'quantity': quantity,
      'branch_id': branchId,
      'tenant_id': tenantId,
    };

    try {
      final wasOnline = await OfflineSyncManager.instance.executeWithSync(
        type: type,
        payload: payload,
        onlineAction: (supabase) async {
          if (id == null) {
            productData['tenant_id'] = tenantId;
            final productResponse = await supabase.from('products').insert(productData).select().single();
            if (branchId != null) {
              await supabase.from('inventory').insert({
                'tenant_id': tenantId,
                'product_id': productResponse['id'],
                'branch_id': branchId,
                'stock_level': quantity,
              });
            }
          } else {
            await supabase.from('products').update(productData).eq('id', id);
            if (branchId != null) {
              final existingInv = await supabase.from('inventory')
                  .select('id')
                  .eq('product_id', id)
                  .eq('branch_id', branchId)
                  .maybeSingle();

              if (existingInv != null) {
                await supabase.from('inventory').update({'stock_level': quantity}).eq('id', existingInv['id']);
              } else {
                await supabase.from('inventory').insert({
                  'tenant_id': tenantId,
                  'product_id': id,
                  'branch_id': branchId,
                  'stock_level': quantity,
                });
              }
            }
          }
        },
      );

      if (!wasOnline) {
        if (id == null) {
          final tempId = 'temp_' + DateTime.now().millisecondsSinceEpoch.toString();
          final mockProduct = {
            'id': tempId,
            'name': name,
            'sku': sku,
            'price': price,
            'category': category,
            'metadata': {'location': location, 'expiration_date': expirationDate},
            'is_active': true,
            'inventory': [
              {'stock_level': quantity, 'branch_id': branchId}
            ]
          };
          setState(() {
            _inventoryItems.insert(0, mockProduct);
            _filteredItems = List.from(_inventoryItems);
          });
        } else {
          setState(() {
            final idx = _inventoryItems.indexWhere((p) => p['id'] == id);
            if (idx != -1) {
              _inventoryItems[idx]['name'] = name;
              _inventoryItems[idx]['sku'] = sku;
              _inventoryItems[idx]['price'] = price;
              _inventoryItems[idx]['category'] = category;
              _inventoryItems[idx]['metadata'] = {'location': location, 'expiration_date': expirationDate};
              _inventoryItems[idx]['inventory'] = [
                {'stock_level': quantity, 'branch_id': branchId}
              ];
              _filteredItems = List.from(_inventoryItems);
            }
          });
        }
        if (mounted) {
          ToastUtils.showSuccessToast(context, message: "Cambio guardado localmente (Sin Conexión)");
        }
      } else {
        _fetchInventory();
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showErrorToast(context, message: "Error al guardar: $e");
      }
    }
  }

  void _deleteProduct(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: const Text("Eliminar Producto", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900)),
        content: Text("¿Estás seguro de que deseas eliminar permanentemente '${product['name']}'? Esta acción no se puede deshacer.", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _executeDeleteProduct(product['id']);
            },
            child: const Text("Eliminar", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeDeleteProduct(String id) async {
    try {
      final wasOnline = await OfflineSyncManager.instance.executeWithSync(
        type: 'delete_product',
        payload: {'id': id},
        onlineAction: (supabase) async {
          await supabase.from('products').delete().eq('id', id);
        },
      );

      if (!wasOnline) {
        setState(() {
          _inventoryItems.removeWhere((p) => p['id'] == id);
          _filteredItems = List.from(_inventoryItems);
        });
        if (mounted) {
          ToastUtils.showSuccessToast(context, message: "Producto eliminado localmente (Sin Conexión)");
        }
      } else {
        _fetchInventory();
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showErrorToast(context, message: "Error al eliminar: $e");
      }
    }
  }

  void _toggleProductStatus(Map<String, dynamic> product) {
    final bool currentStatus = product['is_active'] ?? true;
    ToastUtils.showPromiseToast(
      context, 
      message: currentStatus ? "Desactivando..." : "Activando...", 
      promise: Supabase.instance.client.from('products').update({'is_active': !currentStatus}).eq('id', product['id']).then((_) => _fetchInventory()), 
      successMessage: "Estado actualizado", 
      errorMessage: "Error al actualizar estado"
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
                      onPressed: () => _showProductForm(),
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
                      controller: _searchController,
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
                    else if (_filteredItems.isEmpty)
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
          DataColumn(label: Text("Estado")),
          DataColumn(label: Text("Producto")),
          DataColumn(label: Text("SKU")),
          DataColumn(label: Text("Categoría")),
          DataColumn(label: Text("Precio")),
          DataColumn(label: Text("Stock")),
          DataColumn(label: Text("Acciones")),
        ],
        rows: _filteredItems.map((item) {
          final String name = item['name'] ?? 'Desconocido';
          final String sku = item['sku'] ?? 'N/A';
          final String category = item['category'] ?? 'N/A';
          final double priceNum = (item['price'] as num?)?.toDouble() ?? 0.0;
          final bool isActive = item['is_active'] ?? true;
          
          int stock = 0;
          if (item['inventory'] != null && item['inventory'] is List) {
            for (var inv in item['inventory']) {
              stock += (inv['stock_level'] as num?)?.toInt() ?? 0;
            }
          }

          return DataRow(
            color: WidgetStateProperty.resolveWith<Color?>((states) => isActive ? null : Colors.red.withOpacity(0.05)),
            cells: [
              DataCell(
                Tooltip(
                  message: isActive ? "Activo" : "Inactivo",
                  child: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.greenAccent : Colors.redAccent,
                      shape: BoxShape.circle
                    ),
                  ),
                )
              ),
              DataCell(
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: (item['metadata'] != null && item['metadata']['image_url'] != null && (item['metadata']['image_url'] as String).isNotEmpty)
                        ? Image.network(
                            item['metadata']['image_url'],
                            width: 32, height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 32, height: 32,
                              color: Colors.white10,
                              child: const Icon(LucideIcons.box, size: 16, color: Colors.white38),
                            ),
                          )
                        : Container(
                            width: 32, height: 32,
                            color: Colors.white10,
                            child: const Icon(LucideIcons.box, size: 16, color: Colors.white38),
                          ),
                    ),
                    const SizedBox(width: 12),
                    Text(name, style: TextStyle(fontWeight: FontWeight.bold, decoration: isActive ? null : TextDecoration.lineThrough, color: isActive ? Colors.white : Colors.white54)),
                  ],
                ),
              ),
              DataCell(Text(sku, style: const TextStyle(color: Colors.white38, fontSize: 12))),
              DataCell(Text(category, style: const TextStyle(color: Colors.white54))),
              DataCell(Text("\$${priceNum.toStringAsFixed(2)}")),
              DataCell(Text(stock.toString(), style: TextStyle(color: stock < 5 ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold))),
              DataCell(Row(
                children: [
                  IconButton(
                    icon: Icon(isActive ? LucideIcons.eyeOff : LucideIcons.eye, size: 16, color: Colors.orangeAccent), 
                    tooltip: isActive ? "Desactivar" : "Activar",
                    onPressed: () => _toggleProductStatus(item)
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.edit, size: 16, color: Colors.blueAccent), 
                    tooltip: "Editar",
                    onPressed: () => _showProductForm(product: item)
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent.withOpacity(0.8)), 
                    tooltip: "Eliminar",
                    onPressed: () => _deleteProduct(item)
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
