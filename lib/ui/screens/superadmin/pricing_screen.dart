import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';

class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _plans = [];
  String _activeCategory = 'monthly';

  final _bulkDiscountController = TextEditingController();
  final _newNameController = TextEditingController();
  final _newPaddleIdController = TextEditingController();
  final _newPriceController = TextEditingController();
  final _newDiscountController = TextEditingController();
  final _newCouponController = TextEditingController();
  final _newSortOrderController = TextEditingController();
  final _newFeaturesController = TextEditingController();
  final _newMaxUsersController = TextEditingController();
  String _newBillingInterval = 'monthly';
  bool _newHighlighted = false;

  final _editNameController = TextEditingController();
  final _editPaddleIdController = TextEditingController();
  final _editPriceController = TextEditingController();
  final _editDiscountController = TextEditingController();
  final _editCouponController = TextEditingController();
  final _editSortOrderController = TextEditingController();
  final _editFeaturesController = TextEditingController();
  final _editMaxUsersController = TextEditingController();
  String _editBillingInterval = 'monthly';
  bool _editHighlighted = false;
  bool _editActive = true;
  int? _editingPlanId;

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  @override
  void dispose() {
    _bulkDiscountController.dispose();
    _newNameController.dispose();
    _newPaddleIdController.dispose();
    _newPriceController.dispose();
    _newDiscountController.dispose();
    _newCouponController.dispose();
    _newSortOrderController.dispose();
    _newFeaturesController.dispose();
    _newMaxUsersController.dispose();
    _editNameController.dispose();
    _editPaddleIdController.dispose();
    _editPriceController.dispose();
    _editDiscountController.dispose();
    _editCouponController.dispose();
    _editSortOrderController.dispose();
    _editFeaturesController.dispose();
    _editMaxUsersController.dispose();
    super.dispose();
  }

  Future<void> _fetchPlans() async {
    try {
      final response = await Supabase.instance.client
          .from('subscription_plans')
          .select('*')
          .order('sort_order', ascending: true);

      if (mounted) {
        setState(() {
          _plans = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Error fetching plans: $e");
    }
  }

  void _resetNewPlanForm() {
    _newNameController.clear();
    _newPaddleIdController.clear();
    _newPriceController.clear();
    _newDiscountController.clear();
    _newCouponController.clear();
    _newSortOrderController.clear();
    _newFeaturesController.clear();
    _newMaxUsersController.clear();
    _newBillingInterval = 'monthly';
    _newHighlighted = false;
  }

  void _resetEditForm() {
    _editNameController.clear();
    _editPaddleIdController.clear();
    _editPriceController.clear();
    _editDiscountController.clear();
    _editCouponController.clear();
    _editSortOrderController.clear();
    _editFeaturesController.clear();
    _editMaxUsersController.clear();
    _editBillingInterval = 'monthly';
    _editHighlighted = false;
    _editActive = true;
    _editingPlanId = null;
  }

  void _populateEditForm(Map<String, dynamic> plan) {
    _editNameController.text = plan['name']?.toString() ?? '';
    _editPaddleIdController.text = plan['paddle_id']?.toString() ?? '';
    _editPriceController.text = (plan['price'] ?? 0).toString();
    _editDiscountController.text = (plan['discount_percentage'] ?? 0).toString();
    _editCouponController.text = plan['coupon_code']?.toString() ?? '';
    _editSortOrderController.text = (plan['sort_order'] ?? 0).toString();
    _editMaxUsersController.text = plan['max_users']?.toString() ?? '';
    _editBillingInterval = plan['billing_interval']?.toString() ?? 'monthly';
    _editHighlighted = plan['is_highlighted'] == true;
    _editActive = plan['is_active'] == true;
    _editingPlanId = plan['id'] as int?;

    final features = plan['features'];
    if (features is List) {
      _editFeaturesController.text = features.map((f) => f.toString()).join(', ');
    } else {
      _editFeaturesController.text = features?.toString() ?? '';
    }
  }

  void _showCreatePlanDialog() {
    _resetNewPlanForm();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        title: const Text(
          "Deploy New Subscription Tier",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: SingleChildScrollView(
          child: _buildPlanForm(
            nameController: _newNameController,
            paddleIdController: _newPaddleIdController,
            priceController: _newPriceController,
            discountController: _newDiscountController,
            couponController: _newCouponController,
            sortOrderController: _newSortOrderController,
            featuresController: _newFeaturesController,
            maxUsersController: _newMaxUsersController,
            billingInterval: _newBillingInterval,
            onBillingIntervalChanged: (v) => setState(() => _newBillingInterval = v ?? 'monthly'),
            highlighted: _newHighlighted,
            onHighlightedChanged: (v) => setState(() => _newHighlighted = v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleCreatePlan();
            },
            child: const Text(
              "Deploy Tier",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCreatePlan() async {
    final name = _newNameController.text.trim();
    final paddleId = _newPaddleIdController.text.trim();
    if (name.isEmpty || paddleId.isEmpty) {
      ToastUtils.showErrorToast(
        context,
        message: 'Name and Paddle ID are required',
      );
      return;
    }

    final features = _newFeaturesController.text
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();

    final maxUsersText = _newMaxUsersController.text.trim();

    ToastUtils.showPromiseToast(
      context,
      message: "Deploying tier...",
      promise: Supabase.instance.client.from('subscription_plans').insert({
        'name': name,
        'billing_interval': _newBillingInterval,
        'paddle_id': paddleId,
        'price': double.tryParse(_newPriceController.text) ?? 0,
        'discount_percentage': int.tryParse(_newDiscountController.text) ?? 0,
        'coupon_code': _newCouponController.text.trim().toUpperCase(),
        'sort_order': int.tryParse(_newSortOrderController.text) ?? 0,
        'is_highlighted': _newHighlighted,
        'features': features,
        'max_users': maxUsersText.isNotEmpty ? int.tryParse(maxUsersText) : null,
        'is_active': true,
      }),
      successMessage: "New subscription tier deployed to network.",
      errorMessage: "Deployment failed",
    );
    _fetchPlans();
  }

  void _showEditPlanDialog(Map<String, dynamic> plan) {
    _resetEditForm();
    _populateEditForm(plan);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        title: Text(
          "Edit ${plan['name']} Configuration",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: SingleChildScrollView(
          child: _buildPlanForm(
            nameController: _editNameController,
            paddleIdController: _editPaddleIdController,
            priceController: _editPriceController,
            discountController: _editDiscountController,
            couponController: _editCouponController,
            sortOrderController: _editSortOrderController,
            featuresController: _editFeaturesController,
            maxUsersController: _editMaxUsersController,
            billingInterval: _editBillingInterval,
            onBillingIntervalChanged: (v) => setState(() => _editBillingInterval = v ?? 'monthly'),
            highlighted: _editHighlighted,
            onHighlightedChanged: (v) => setState(() => _editHighlighted = v),
            showActiveToggle: true,
            active: _editActive,
            onActiveChanged: (v) => setState(() => _editActive = v),
            showDeleteButton: true,
            onDelete: () {
              Navigator.pop(ctx);
              _showDeletePlanDialog(plan['id'] as int);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleUpdatePlan();
            },
            child: const Text(
              "Save",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdatePlan() async {
    if (_editingPlanId == null) return;

    final features = _editFeaturesController.text
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();

    final maxUsersText = _editMaxUsersController.text.trim();

    ToastUtils.showPromiseToast(
      context,
      message: "Synchronizing...",
      promise: Supabase.instance.client.from('subscription_plans').update({
        'name': _editNameController.text.trim(),
        'billing_interval': _editBillingInterval,
        'paddle_id': _editPaddleIdController.text.trim(),
        'price': double.tryParse(_editPriceController.text) ?? 0,
        'discount_percentage': int.tryParse(_editDiscountController.text) ?? 0,
        'coupon_code': _editCouponController.text.trim().toUpperCase(),
        'sort_order': int.tryParse(_editSortOrderController.text) ?? 0,
        'is_highlighted': _editHighlighted,
        'is_active': _editActive,
        'features': features,
        'max_users': maxUsersText.isNotEmpty ? int.tryParse(maxUsersText) : null,
      }).eq('id', _editingPlanId!),
      successMessage: "Plan configuration synchronized.",
      errorMessage: "Update failed",
    );
    _fetchPlans();
  }

  void _showDeletePlanDialog(int planId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        title: const Text(
          "Security Alert: Irreversible Action",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.red, size: 48),
            SizedBox(height: 16),
            Text(
              "Authorize Decommission?",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "This subscription tier will be permanently purged from the network catalog.",
              style: TextStyle(color: Colors.white60, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Abort", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleDeletePlan(planId);
            },
            child: const Text(
              "Confirm Termination",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeletePlan(int planId) async {
    ToastUtils.showPromiseToast(
      context,
      message: "Terminating tier...",
      promise: Supabase.instance.client
          .from('subscription_plans')
          .delete()
          .eq('id', planId),
      successMessage: "Subscription tier has been purged from the system.",
      errorMessage: "Decommission failed",
    );
    _fetchPlans();
  }

  Future<void> _togglePlanStatus(int planId, bool currentStatus) async {
    await Supabase.instance.client
        .from('subscription_plans')
        .update({'is_active': !currentStatus})
        .eq('id', planId);
    _fetchPlans();
  }

  void _applyCategoryDiscount() {
    final val = int.tryParse(_bulkDiscountController.text);
    if (val == null) {
      ToastUtils.showErrorToast(context, message: "Enter a valid discount percentage");
      return;
    }

    ToastUtils.showPromiseToast(
      context,
      message: "Broadcasting discount to network...",
      promise: Supabase.instance.client
          .from('subscription_plans')
          .update({'discount_percentage': val})
          .eq('billing_interval', _activeCategory),
      successMessage: "Category wide discount of $val% applied.",
      errorMessage: "Broadcast failed",
    );
    _fetchPlans();
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocaleProvider>(context).t;
    final filteredPlans =
        _plans.where((p) => p['billing_interval'] == _activeCategory).toList();
    final activeCount = _plans.where((p) => p['is_active'] == true).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(t),
            const SizedBox(height: 32),
            _buildToolbar(),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(100),
                  child: CircularProgressIndicator(color: Colors.red),
                ),
              )
            else
              _buildContent(filteredPlans, activeCount),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('pricing_title'),
              style: Theme.of(context)
                  .textTheme
                  .displayLarge
                  ?.copyWith(fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              t('pricing_subtitle'),
              style: const TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ],
        ),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _fetchPlans,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: Text(t('refresh')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceLight,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _showCreatePlanDialog,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text(
                "DEPLOY NEW TIER",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn().slideY(begin: -0.2);
  }

  Widget _buildToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                _buildCategoryTab('monthly'),
                _buildCategoryTab('annually'),
                _buildCategoryTab('lifetime'),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _bulkDiscountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: "% Off",
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 24,
                  child: VerticalDivider(color: Colors.white10),
                ),
                TextButton(
                  onPressed: _applyCategoryDiscount,
                  child: const Text(
                    "Apply to Category",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab(String category) {
    final isActive = _activeCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _activeCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.red : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          category.toUpperCase(),
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white38,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<Map<String, dynamic>> filteredPlans, int activeCount) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              if (filteredPlans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(60),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDark.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Center(
                    child: Text(
                      "No pricing protocols deployed",
                      style: TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                )
              else
                ...filteredPlans.map((plan) => _buildPlanCard(plan)),
            ],
          ),
        ),
        const SizedBox(width: 24),
        _buildSidebar(activeCount),
      ],
    );
  }

  Widget _buildSidebar(int activeCount) {
    return SizedBox(
      width: 280,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  "OPERATIONAL STATUS",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "ACTIVE TIERS",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$activeCount",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "PADDLE GATEWAY",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Securely Connected",
                    style: TextStyle(
                      color: Colors.greenAccent.withOpacity(0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Subscription tiers are globally synced with the Paddle Billing API. Any modification here will update the checkout pricing immediately for new corporate nodes.",
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final isHighlighted = plan['is_highlighted'] == true;
    final isActive = plan['is_active'] == true;
    final features = plan['features'] as List? ?? [];
    final price = plan['price']?.toString() ?? '0';
    final discount = plan['discount_percentage'] as int? ?? 0;
    final hasDiscount = discount > 0;
    final billingInterval = plan['billing_interval']?.toString() ?? 'monthly';
    final planId = plan['id'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppTheme.primaryColor.withOpacity(0.05)
            : AppTheme.surfaceDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted
              ? AppTheme.primaryColor.withOpacity(0.5)
              : isActive
                  ? Colors.white.withOpacity(0.05)
                  : Colors.red.withOpacity(0.2),
          width: isHighlighted ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Opacity(
        opacity: isActive ? 1.0 : 0.5,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 60,
              decoration: BoxDecoration(
                color: isActive
                    ? (isHighlighted ? AppTheme.primaryColor : Colors.red)
                    : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: (isHighlighted
                                  ? AppTheme.primaryColor
                                  : Colors.red)
                              .withOpacity(0.4),
                          blurRadius: 15,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan['name']?.toString().toUpperCase() ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (isHighlighted) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "HIGHLIGHTED",
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                      if (hasDiscount) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Text(
                            "-$discount% OFF",
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                      if (!isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border:
                                Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: const Text(
                            "INACTIVE",
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          billingInterval.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white38,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "\$$price",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryColor,
                          letterSpacing: -1,
                        ),
                      ),
                      if (plan['paddle_id'] != null &&
                          plan['paddle_id'].toString().isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Text(
                          plan['paddle_id'].toString(),
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.redAccent.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (features.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: features.map((f) {
                        final label = f.toString();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.checkCircle2,
                                color: Colors.greenAccent, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                  if (plan['max_users'] != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(LucideIcons.users,
                            color: Colors.white38, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          "Max ${plan['max_users']} users",
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: IconButton(
                    icon: const Icon(LucideIcons.pencil, size: 16),
                    color: Colors.white54,
                    onPressed: () => _showEditPlanDialog(plan),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.surfaceDark
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isActive
                          ? Colors.white10
                          : Colors.red.withOpacity(0.2),
                    ),
                  ),
                  child: IconButton(
                    icon: Icon(
                      isActive ? LucideIcons.checkCircle : LucideIcons.xCircle,
                      size: 16,
                    ),
                    color:
                        isActive ? Colors.greenAccent : Colors.redAccent,
                    onPressed: () =>
                        _togglePlanStatus(planId, isActive),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: IconButton(
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    color: Colors.redAccent,
                    onPressed: () => _showDeletePlanDialog(planId),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildPlanForm({
    required TextEditingController nameController,
    required TextEditingController paddleIdController,
    required TextEditingController priceController,
    required TextEditingController discountController,
    required TextEditingController couponController,
    required TextEditingController sortOrderController,
    required TextEditingController featuresController,
    required TextEditingController maxUsersController,
    required String billingInterval,
    required ValueChanged<String?> onBillingIntervalChanged,
    required bool highlighted,
    required ValueChanged<bool> onHighlightedChanged,
    bool showActiveToggle = false,
    bool active = true,
    ValueChanged<bool>? onActiveChanged,
    bool showDeleteButton = false,
    VoidCallback? onDelete,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFormField("Tier Name", nameController, hint: "e.g. Starter"),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildFormField("Billing Interval", null,
                  dropdownValue: billingInterval,
                  dropdownItems: const ['monthly', 'annually', 'lifetime'],
                  onDropdownChanged: onBillingIntervalChanged),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField("Paddle Price ID", paddleIdController,
                  hint: "pri_...", mono: true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildFormField("Base Price (\$)", priceController,
                  isNumber: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField("Discount (%)", discountController,
                  isNumber: true, hint: "20, 50..."),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildFormField("Coupon Code (Optional)", couponController,
                  hint: "OFF50, WELCOME...", mono: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField("Display Order", sortOrderController,
                  isNumber: true, hint: "0, 1, 2..."),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildFormToggle(
          value: highlighted,
          onChanged: onHighlightedChanged,
          label: "Highlight this plan in the network",
        ),
        if (showActiveToggle && onActiveChanged != null) ...[
          const SizedBox(height: 12),
          _buildFormToggle(
            value: active,
            onChanged: onActiveChanged,
            label: "Plan is Active",
          ),
        ],
        const SizedBox(height: 16),
        _buildFormField("Features (Comma separated)", featuresController,
            hint: "1 Branch, 5 Users, Priority Support...", multiline: true),
        const SizedBox(height: 16),
        _buildFormField("Max Users (leave blank for unlimited)",
            maxUsersController,
            isNumber: true),
        if (showDeleteButton && onDelete != null) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 16),
              label: const Text(
                "Terminate Plan",
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFormField(
    String? label,
    TextEditingController? controller, {
    String? hint,
    bool isNumber = false,
    bool mono = false,
    bool multiline = false,
    String? dropdownValue,
    List<String>? dropdownItems,
    ValueChanged<String?>? onDropdownChanged,
  }) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontFamily: mono ? 'monospace' : null,
      fontSize: 13,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (dropdownItems != null && onDropdownChanged != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: dropdownValue,
                dropdownColor: AppTheme.surfaceDark,
                style: textStyle,
                items: dropdownItems
                    .map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.toUpperCase(), style: textStyle),
                        ))
                    .toList(),
                onChanged: onDropdownChanged,
                isExpanded: true,
              ),
            ),
          )
        else if (multiline && controller != null)
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: controller,
              maxLines: 4,
              style: textStyle,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white24),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          )
        else if (controller != null)
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: controller,
              keyboardType:
                  isNumber ? TextInputType.number : TextInputType.text,
              style: textStyle,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white24),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFormToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.red,
            activeTrackColor: Colors.red.withOpacity(0.4),
          ),
        ],
      ),
    );
  }
}
