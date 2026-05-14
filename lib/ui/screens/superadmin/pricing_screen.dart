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

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  Future<void> _fetchPlans() async {
    try {
      final response = await Supabase.instance.client
          .from('subscription_plans')
          .select('*')
          .order('price_monthly', ascending: true);

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

  void _showEditPlanDialog(Map<String, dynamic> plan) {
    final t = Provider.of<LocaleProvider>(context, listen: false).t;
    final priceController = TextEditingController(text: plan['price_monthly'].toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: Text("Modify Plan: ${plan['name']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Monthly Price ($)", labelStyle: TextStyle(color: Colors.white38)),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'), style: const TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _updatePlan(plan['id'], double.tryParse(priceController.text) ?? 0.0);
            },
            child: Text(t('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePlan(int planId, double newPrice) async {
    ToastUtils.showPromiseToast(
      context, 
      message: "Updating Protocol...", 
      promise: Supabase.instance.client.from('subscription_plans').update({'price_monthly': newPrice}).eq('id', planId), 
      successMessage: "Plan Updated", 
      errorMessage: "Update Failure"
    );
    _fetchPlans();
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
                    Text(t('pricing_title'), style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(t('pricing_subtitle'), style: const TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _fetchPlans,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: Text(t('refresh')),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceLight, foregroundColor: Colors.white),
                ),
              ],
            ).animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 48),
            
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(100), child: CircularProgressIndicator(color: Colors.red)))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 350,
                  mainAxisExtent: 500,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                ),
                itemCount: _plans.length,
                itemBuilder: (context, index) => _buildPricingCard(_plans[index], context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingCard(Map<String, dynamic> plan, BuildContext context) {
    final t = Provider.of<LocaleProvider>(context).t;
    final bool isHighlighted = plan['is_highlighted'] == true;
    final List features = plan['features'] as List? ?? [];

    return Container(
      decoration: BoxDecoration(
        color: isHighlighted ? AppTheme.primaryColor.withOpacity(0.05) : AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isHighlighted ? AppTheme.primaryColor.withOpacity(0.5) : Colors.white.withOpacity(0.05),
          width: isHighlighted ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isHighlighted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(10)),
              child: const Text("RECOMMENDED", style: TextStyle(fontSize: 9, fontWeight: FontWeight.black, letterSpacing: 1)),
            ),
          const SizedBox(height: 16),
          Text(plan['name'].toString().toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("\$${plan['price_monthly']}", style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: AppTheme.primaryColor, letterSpacing: -2)),
              const Padding(padding: EdgeInsets.only(bottom: 8.0, left: 4), child: Text("/mo", style: TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: features.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(LucideIcons.checkCircle2, color: AppTheme.accentColor, size: 16),
                    const SizedBox(width: 12),
                    Expanded(child: Text(features[i].toString(), style: const TextStyle(color: Colors.white70, fontSize: 13))),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => _showEditPlanDialog(plan),
              style: ElevatedButton.styleFrom(
                backgroundColor: isHighlighted ? AppTheme.primaryColor : AppTheme.surfaceLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text("EDIT PROTOCOL", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }
}

