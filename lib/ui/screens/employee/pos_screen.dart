import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  String _selectedCategory = 'All';
  List<Map<String, dynamic>> _cart = [];
  bool _isLoadingProducts = true;
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _myProfile;
  List<String> _categories = ['All'];

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      _myProfile = await supabase.from('profiles').select('*').eq('id', user.id).single();
      await _fetchProducts();
    } catch (e) {
      debugPrint("POS Data Error: $e");
    }
  }

  Future<void> _fetchProducts() async {
    try {
      final supabase = Supabase.instance.client;
      final tenantId = _myProfile?['tenant_id'];

      var query = supabase.from('products').select().eq('is_active', true);
      if (tenantId != null) query = query.eq('tenant_id', tenantId);

      final response = await query;
      if (mounted) {
        final products = List<Map<String, dynamic>>.from(response);
        final cats = {'All'};
        for (var p in products) {
          final meta = p['metadata'] as Map<String, dynamic>? ?? {};
          if (meta.containsKey('category')) cats.add(meta['category']);
        }

        setState(() {
          _products = products;
          _categories = cats.toList()..sort();
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  void _addToCart(Map<String, dynamic> product) {
    setState(() {
      final existingIndex = _cart.indexWhere((item) => item['id'] == product['id']);
      if (existingIndex >= 0) {
        _cart[existingIndex]['qty']++;
      } else {
        _cart.add({...product, 'qty': 1});
      }
    });
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      _cart[index]['qty'] += delta;
      if (_cart[index]['qty'] <= 0) _cart.removeAt(index);
    });
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
  double get _tax => _subtotal * 0.15;
  double get _total => _subtotal + _tax;

  Future<void> _processCheckout() async {
    if (_cart.isEmpty) return;
    final t = Provider.of<LocaleProvider>(context, listen: false).t;

    ToastUtils.showPromiseToast(
      context, 
      message: "Authorizing Payment...", 
      promise: _executeCheckout(), 
      successMessage: "Transaction Complete", 
      errorMessage: "Payment Protocol Error"
    );
  }

  Future<void> _executeCheckout() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("No auth");

      final tenantId = _myProfile?['tenant_id'];
      final branchId = _myProfile?['branch_id'];

      if (tenantId == null || branchId == null) throw Exception("Identity Mismatch");

      final itemsJson = _cart.map((item) => {
        'id': item['id'],
        'qty': item['qty'],
        'price': item['price']
      }).toList();

      await Supabase.instance.client.rpc('process_complete_sale', params: {
        'p_tenant_id': tenantId,
        'p_branch_id': branchId,
        'p_employee_id': user.id,
        'p_total': _total,
        'p_items': itemsJson
      });

      if (mounted) setState(() => _cart.clear());
    } catch (e) { rethrow; }
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('pos_title'), style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
            const SizedBox(height: 8),
            Text(_myProfile?['full_name']?.toString().toUpperCase() ?? "OPERATIVE UNIT", style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ],
        ),
        SizedBox(
          width: 300,
          child: TextField(
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
                  Text("\$${product['price'].toStringAsFixed(2)}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -1)),
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
          _buildCartTotals(t),
        ],
      ),
    ).animate().slideX(begin: 1, end: 0);
  }

  Widget _buildCartHeader(String Function(String) t) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Row(
        children: [
          const Icon(LucideIcons.shoppingCart, color: Colors.red, size: 20),
          const SizedBox(width: 16),
          const Text("TRANSACTION BUFFER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const Spacer(),
          Text("${_cart.length} UNIT(S)", style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildCartItems() {
    if (_cart.isEmpty) {
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
      itemCount: _cart.length,
      itemBuilder: (context, index) {
        final item = _cart[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.01), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                    Text("\$${item['price']}", style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(icon: const Icon(LucideIcons.minus, size: 14), onPressed: () => _updateQuantity(index, -1)),
                  Text("${item['qty']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  IconButton(icon: const Icon(LucideIcons.plus, size: 14, color: Colors.red), onPressed: () => _updateQuantity(index, 1)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCartTotals(String Function(String) t) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(color: Colors.black, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: Column(
        children: [
          _buildTotalRow("SUBTOTAL", "\$${_subtotal.toStringAsFixed(2)}"),
          const SizedBox(height: 8),
          _buildTotalRow("NETWORK TAX (15%)", "\$${_tax.toStringAsFixed(2)}"),
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(color: Colors.white10)),
          _buildTotalRow("VALUATION TOTAL", "\$${_total.toStringAsFixed(2)}", isTotal: true),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: _cart.isEmpty ? null : _processCheckout,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: Text(t('pos_checkout'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
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

