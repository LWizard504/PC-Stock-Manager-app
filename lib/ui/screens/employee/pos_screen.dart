import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pc_dev_flutter/services/offline_sync_manager.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  String _selectedCategory = 'All';
  List<Map<String, dynamic>> _cart = [];
  bool _isLoadingProducts = true;
  bool _isProcessing = false;
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _myProfile;
  List<String> _categories = ['All'];
  bool _showTouchNumpad = true;
  
  String? _selectedItemId;
  RealtimeChannel? _channel;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _loadPreferences();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showTouchNumpad = prefs.getBool('show_touch_numpad') ?? true;
      });
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      
      if (user != null) {
        try {
          _myProfile = await supabase.from('profiles').select('*').eq('id', user.id).single();
          await OfflineSyncManager.instance.cacheUserProfile(_myProfile!);
        } catch (e) {
          debugPrint("POS load profile online failed, falling back to cache: $e");
          _myProfile = await OfflineSyncManager.instance.getCachedUserProfile();
        }
      } else {
        _myProfile = await OfflineSyncManager.instance.getCachedUserProfile();
      }

      _setupRealtime();
      await _fetchProducts();
    } catch (e) {
      debugPrint("POS Data Error: $e");
    }
  }

  void _setupRealtime() {
    final supabase = Supabase.instance.client;
    final tenantId = _myProfile?['tenant_id'];
    _channel = supabase.channel('employee-pos-products');
    _channel!
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'products', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'tenant_id', value: tenantId), callback: (payload) => _fetchProducts())
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'inventory', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'tenant_id', value: tenantId), callback: (payload) => _fetchProducts())
      .subscribe();
  }

  Future<void> _fetchProducts() async {
    if (!mounted) return;
    setState(() => _isLoadingProducts = true);
    
    try {
      final supabase = Supabase.instance.client;
      final tenantId = _myProfile?['tenant_id'];
      String? currentBranchId = _myProfile?['branch_id'];

      List<Map<String, dynamic>> products;

      try {
        if (currentBranchId == null && tenantId != null) {
          final fallbackBranch = await supabase.from('branches').select('id').eq('tenant_id', tenantId).order('created_at', ascending: true).limit(1).maybeSingle();
          currentBranchId = fallbackBranch?['id'] as String?;
        }

        var query = supabase.from('products').select('*, inventory(*)').eq('is_active', true);
        if (tenantId != null) query = query.eq('tenant_id', tenantId);

        final response = await query;
        products = List<Map<String, dynamic>>.from(response);

        // Cache the list of products for offline usage
        await OfflineSyncManager.instance.cacheProducts(products);
      } catch (e) {
        debugPrint("Failed to fetch products online, loading offline cache: $e");
        final cached = await OfflineSyncManager.instance.getCachedProducts();
        if (cached != null) {
          products = cached;
        } else {
          products = [];
        }
      }

      if (mounted) {
        final cats = {'All'};

        // If currentBranchId is still null, look through products' inventory list to dynamically fallback to the branch with stock!
        if (currentBranchId == null) {
          for (var p in products) {
            if (p['inventory'] != null && p['inventory'] is List && (p['inventory'] as List).isNotEmpty) {
              for (var inv in p['inventory']) {
                if ((inv['stock_level'] as num?)?.toInt() != 0) {
                  currentBranchId = inv['branch_id'] as String?;
                  break;
                }
              }
              if (currentBranchId != null) break;
            }
          }
          // If still null, just take the first branch_id found
          if (currentBranchId == null) {
            for (var p in products) {
              if (p['inventory'] != null && p['inventory'] is List && (p['inventory'] as List).isNotEmpty) {
                currentBranchId = p['inventory'][0]['branch_id'] as String?;
                if (currentBranchId != null) break;
              }
            }
          }
        }
        
        for (var p in products) {
          final meta = p['metadata'] as Map<String, dynamic>? ?? {};
          p['image_url'] = meta['image_url'];
          if (meta.containsKey('category')) cats.add(meta['category']);
          
          int stock = 0;
          if (p['inventory'] != null && p['inventory'] is List) {
            for (var inv in p['inventory']) {
              if (inv['branch_id'] == currentBranchId) {
                stock = (inv['stock_level'] as num?)?.toInt() ?? 0;
                break;
              }
            }
            if (stock == 0) {
              for (var inv in p['inventory']) {
                stock += (inv['stock_level'] as num?)?.toInt() ?? 0;
              }
            }
          }
          p['stock'] = stock;
        }

        setState(() {
          _products = products;
          _categories = cats.toList()..sort();
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  void _addToCart(Map<String, dynamic> product) {
    final stock = product['stock'] as int? ?? 0;
    setState(() {
      final existingIndex = _cart.indexWhere((item) => item['id'] == product['id']);
      if (existingIndex >= 0) {
        if (_cart[existingIndex]['qty'] < stock) {
          _cart[existingIndex]['qty']++;
        } else {
          ToastUtils.showCustomToast(context, "Stock insuficiente ($stock disponibles)", isError: true);
        }
      } else {
        if (stock > 0) {
          _cart.add({...product, 'qty': 1});
        } else {
          ToastUtils.showCustomToast(context, "Stock insuficiente (0 disponibles)", isError: true);
        }
      }
      _selectedItemId = product['id'];
    });
  }

  void _updateQuantity(String id, int newQty) {
    setState(() {
      final index = _cart.indexWhere((c) => c['id'] == id);
      if (index < 0) return;
      
      final product = _products.firstWhere((p) => p['id'] == id, orElse: () => {});
      final stock = product['stock'] as int? ?? 0;
      
      if (newQty > stock) {
        ToastUtils.showCustomToast(context, "Stock insuficiente ($stock disponibles)", isError: true);
        return;
      }
      
      if (newQty <= 0) {
         _cart.removeAt(index);
         if (_selectedItemId == id) _selectedItemId = null;
      } else {
         _cart[index]['qty'] = newQty;
      }
    });
  }

  void _handleNumpad(String val) {
    if (_selectedItemId == null) return;
    
    setState(() {
      final index = _cart.indexWhere((c) => c['id'] == _selectedItemId);
      if (index < 0) return;
      
      int currentQty = _cart[index]['qty'];
      
      if (val == '⌫') {
        String currentQtyStr = currentQty.toString();
        if (currentQtyStr.length > 1 && currentQty != 0) {
          _updateQuantity(_selectedItemId!, int.parse(currentQtyStr.substring(0, currentQtyStr.length - 1)));
        } else if (currentQty > 0) {
          _updateQuantity(_selectedItemId!, 0);
        } else {
          _cart.removeAt(index);
          _selectedItemId = null;
        }
      } else {
        String currentQtyStr = currentQty == 0 ? "" : currentQty.toString();
        int newQty = int.parse(currentQtyStr + val);
        _updateQuantity(_selectedItemId!, newQty);
      }
    });
  }
  
  void _handleSearchSubmit(String val) {
    if (val.trim().isEmpty) return;
    final matchIndex = _products.indexWhere((p) => 
       (p['sku']?.toString().toLowerCase() == val.toLowerCase()) || 
       (p['name']?.toString().toLowerCase() == val.toLowerCase())
    );
    
    if (matchIndex >= 0) {
       _addToCart(_products[matchIndex]);
       ToastUtils.showCustomToast(context, "Agregado: ${_products[matchIndex]['name']}");
       _searchController.clear();
    } else {
       ToastUtils.showCustomToast(context, "Producto no encontrado", isError: true);
    }
  }

  double get _subtotal {
    return _cart.where((c) => c['qty'] > 0).fold(0, (sum, item) => sum + (item['price'] * item['qty']));
  }
  double get _tax => _subtotal * 0.15;
  double get _total => _subtotal + _tax;

  Future<void> _processCheckout() async {
    final activeCart = _cart.where((c) => c['qty'] > 0).toList();
    if (activeCart.isEmpty || _total <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: const Text("Confirmar Venta", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${activeCart.length} artículo(s) en el carrito", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text("Total: \$${_total.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar", style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Confirmar Venta", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    setState(() => _isProcessing = true);
    
    ToastUtils.showPromiseToast(
      context, 
      message: "Procesando Venta...", 
      promise: _executeCheckout(activeCart), 
      successMessage: "Transacción Completada", 
      errorMessage: "Error en el proceso"
    );
  }

  Future<void> _executeCheckout(List<Map<String, dynamic>> activeCart) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("No auth");

      final tenantId = _myProfile?['tenant_id'];
      String? branchId = _myProfile?['branch_id'];

      if (branchId == null && tenantId != null) {
        final fallbackBranch = await Supabase.instance.client.from('branches').select('id').eq('tenant_id', tenantId).order('created_at', ascending: true).limit(1).maybeSingle();
        branchId = fallbackBranch?['id'] as String?;
      }

      if (tenantId == null || branchId == null) throw Exception("Identity Mismatch");

      final itemsJson = activeCart.map((item) => {
        'id': item['id'],
        'qty': item['qty'],
        'price': item['price']
      }).toList();

      final payload = {
        'p_tenant_id': tenantId,
        'p_branch_id': branchId,
        'p_employee_id': user.id,
        'p_total': _total,
        'p_items': itemsJson,
      };

      final wasOnline = await OfflineSyncManager.instance.executeWithSync(
        type: 'process_complete_sale',
        payload: payload,
        onlineAction: (supabase) async {
          await supabase.rpc('process_complete_sale', params: payload);
        },
      );

      if (!wasOnline) {
        setState(() {
          for (var item in activeCart) {
            final idx = _products.indexWhere((p) => p['id'] == item['id']);
            if (idx != -1) {
              final currentStock = _products[idx]['stock'] as int? ?? 0;
              _products[idx]['stock'] = (currentStock - (item['qty'] as int)).clamp(0, 999999);
            }
          }
          _cart.clear();
          _selectedItemId = null;
          _isProcessing = false;
        });
        if (mounted) {
          ToastUtils.showSuccessToast(context, message: "Venta guardada localmente (Sin Conexión)");
        }
      } else {
        if (mounted) {
          setState(() {
            _cart.clear();
            _selectedItemId = null;
            _isProcessing = false;
          });
        }
        await _fetchProducts();
      }
    } catch (e) { 
      if (mounted) setState(() => _isProcessing = false);
      rethrow; 
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocaleProvider>(context).t;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(t),
                  const SizedBox(height: 32),
                  _buildCategoryFilter(),
                  const SizedBox(height: 32),
                  Expanded(child: _buildProductGrid(t)),
                ],
              ),
            ),
          ),
          _buildCartSidebar(t),
        ],
      ),
    );
  }

  Widget _buildHeader(String Function(String) t) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('pos_title'), style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
            const SizedBox(height: 8),
            Text(_myProfile?['full_name']?.toString().toUpperCase() ?? "OPERATIVE UNIT", style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 250,
              child: TextField(
                controller: _searchController,
                onSubmitted: _handleSearchSubmit,
                decoration: InputDecoration(
                  hintText: "SCAN SKU / SEARCH...",
                  hintStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white10),
                  prefixIcon: const Icon(LucideIcons.search, color: Colors.white24, size: 18),
                  filled: true,
                  fillColor: AppTheme.surfaceDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {}, // Handled by search field focus usually
              icon: const Icon(LucideIcons.scan, size: 14),
              label: const Text("SCANNER"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _fetchProducts,
              icon: _isLoadingProducts ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2)) : const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text("ACTUALIZAR"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.1),
                foregroundColor: Colors.red,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)
              ),
            ),
          ],
        )
      ],
    ).animate().fadeIn().slideY(begin: -0.2);
  }

  Widget _buildCategoryFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              label: Text(cat.toUpperCase()),
              selected: isSelected,
              onSelected: (val) => setState(() => _selectedCategory = cat),
              selectedColor: Colors.red,
              backgroundColor: AppTheme.surfaceDark,
              labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSelected ? Colors.red : Colors.white.withOpacity(0.05))),
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn();
  }

  Widget _buildProductGrid(String Function(String) t) {
    if (_isLoadingProducts) return const Center(child: CircularProgressIndicator(color: Colors.red));
    
    final filteredProducts = _products.where((p) {
      if (_selectedCategory == 'All') return true;
      final meta = p['metadata'] as Map<String, dynamic>? ?? {};
      return meta['category'] == _selectedCategory;
    }).toList();

    if (filteredProducts.isEmpty) return const Center(child: Text("NO ASSETS FOUND", style: TextStyle(color: Colors.white10, fontWeight: FontWeight.w900, fontSize: 10)));

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.72,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: filteredProducts.length,
      itemBuilder: (context, index) => _buildProductCard(filteredProducts[index]),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    return InkWell(
      onTap: () => _addToCart(product),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26, 
                  borderRadius: BorderRadius.circular(16),
                  image: product['image_url'] != null 
                    ? DecorationImage(image: NetworkImage(product['image_url']), fit: BoxFit.cover)
                    : null,
                ),
                child: product['image_url'] == null 
                  ? const Icon(LucideIcons.package, color: Colors.white12, size: 40)
                  : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("\$${product['price'].toStringAsFixed(2)}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -1)),
                      Text("${product['stock']}x", style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.w900, fontSize: 10)),
                    ]
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().scale(delay: 50.ms);
  }

  Widget _buildCartSidebar(String Function(String) t) {
    return Container(
      width: 400,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(left: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          _buildCartHeader(t),
          Expanded(child: _buildCartItems()),
          if (_selectedItemId != null && _showTouchNumpad) _buildNumpad(),
          _buildCartTotals(t),
        ],
      ),
    ).animate().slideX(begin: 1, end: 0);
  }

  Widget _buildCartHeader(String Function(String) t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          const Icon(LucideIcons.shoppingCart, color: Colors.red, size: 20),
          const SizedBox(width: 16),
          const Text("TRANSACTION BUFFER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.white38),
            onPressed: () => setState(() { _cart.clear(); _selectedItemId = null; }),
          )
        ],
      ),
    );
  }

  Widget _buildCartItems() {
    final activeCart = _cart.where((c) => c['qty'] > 0).toList();
    if (activeCart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.box, size: 48, color: Colors.white.withOpacity(0.03)),
            const SizedBox(height: 16),
            const Text("BUFFER EMPTY", style: TextStyle(color: Colors.white10, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: activeCart.length,
      itemBuilder: (context, index) {
        final item = activeCart[index];
        final isSelected = _selectedItemId == item['id'];
        
        return InkWell(
          onTap: () => setState(() => _selectedItemId = item['id']),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.01), 
              borderRadius: BorderRadius.circular(16), 
              border: Border.all(color: isSelected ? Colors.red.withOpacity(0.5) : Colors.white10)
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['name'].toString().toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: isSelected ? Colors.red : Colors.white)),
                      Text("\$${item['price']}", style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.minusCircle, size: 20, color: Colors.white38),
                      onPressed: () => _updateQuantity(item['id'], item['qty'] - 1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    Text("${item['qty']}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isSelected ? Colors.red : Colors.white)),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(LucideIcons.plusCircle, size: 20, color: Colors.white38),
                      onPressed: () => _updateQuantity(item['id'], item['qty'] + 1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNumpad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(top: BorderSide(color: Colors.white10))
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("EDIT QUANTITY", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1)),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 14, color: Colors.white54),
                onPressed: () => setState(() => _selectedItemId = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            childAspectRatio: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ...['1','2','3','4','5','6','7','8','9','0','⌫'].map((num) => 
                ElevatedButton(
                  onPressed: () => _handleNumpad(num),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.05),
                    foregroundColor: num == '⌫' ? Colors.red : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: Text(num, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                )
              ),
            ],
          ),
        ],
      )
    ).animate().slideY(begin: 1, end: 0, duration: 200.ms);
  }

  Widget _buildCartTotals(String Function(String) t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(color: Colors.black, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: Column(
        children: [
          _buildTotalRow("SUBTOTAL", "\$${_subtotal.toStringAsFixed(2)}"),
          const SizedBox(height: 8),
          _buildTotalRow("NETWORK TAX (15%)", "\$${_tax.toStringAsFixed(2)}"),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white10)),
          _buildTotalRow("VALUATION TOTAL", "\$${_total.toStringAsFixed(2)}", isTotal: true),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: (_cart.where((c) => c['qty'] > 0).isEmpty || _isProcessing) ? null : _processCheckout,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: _isProcessing 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : Text(t('pos_checkout'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String val, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: isTotal ? Colors.white : Colors.white24, fontWeight: FontWeight.w900, fontSize: isTotal ? 14 : 10, letterSpacing: 1)),
        Text(val, style: TextStyle(color: isTotal ? Colors.red : Colors.white, fontWeight: FontWeight.w900, fontSize: isTotal ? 22 : 12)),
      ],
    );
  }
}
