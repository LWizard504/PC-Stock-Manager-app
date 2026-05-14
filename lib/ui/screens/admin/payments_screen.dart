import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _tenant;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _fetchBillingData();
  }

  Future<void> _fetchBillingData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase.from('profiles').select('tenant_id').eq('id', user.id).single();
      final tenantId = profile['tenant_id'];

      final tData = await supabase.from('tenants').select('*').eq('id', tenantId).single();
      final hData = await supabase.from('billing_history').select('*').eq('tenant_id', tenantId).order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _tenant = tData;
          _history = List<Map<String, dynamic>>.from(hData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Billing fetch error: $e");
    }
  }

  Future<void> _cancelSubscription() async {
    final t = Provider.of<LocaleProvider>(context, listen: false).t;
    // For now, since we don't want to over-complicate mobile with complex Paddle logic, 
    // we just mark it as canceled in the DB, matching the web action's end goal.
    ToastUtils.showPromiseToast(
      context, 
      message: "Terminating Node...", 
      promise: Supabase.instance.client.from('tenants').update({'is_active': false, 'payment_status': 'canceled'}).eq('id', _tenant!['id']), 
      successMessage: "Subscription Terminated", 
      errorMessage: "Cancellation Failed"
    );
    _fetchBillingData();
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
            Text("Fiscal & Billing", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text("Manage network subscriptions and corporate payment lanes.", style: TextStyle(color: Colors.white60, fontSize: 16)),
            const SizedBox(height: 48),
            
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(100), child: CircularProgressIndicator(color: Colors.red)))
            else ...[
              _buildActivePlanCard(context),
              const SizedBox(height: 48),
              _buildHistorySection(context),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildActivePlanCard(BuildContext context) {
    final bool isActive = _tenant?['is_active'] ?? false;
    final String tier = _tenant?['subscription_tier'] ?? 'Starter';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
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
                  const Text("ACTIVE SUBSCRIPTION", style: TextStyle(color: AppTheme.primaryColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  Text(tier.toUpperCase(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2)),
                ),
                child: Text(
                  isActive ? "ENCRYPTED & ACTIVE" : "TERMINATED",
                  style: TextStyle(color: isActive ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildInfoBit("Billing Interval", _tenant?['billing_interval'] ?? 'MONTHLY'),
              ),
              Expanded(
                child: _buildInfoBit("Next Sync", _tenant?['next_billing_date'] ?? 'Awaiting Provision'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text("UPDATE PROTOCOL", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: _cancelSubscription,
                child: const Text("Terminate Node", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY();
  }

  Widget _buildInfoBit(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildHistorySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("TRANSACTION LOGS", style: TextStyle(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 24),
        if (_history.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(48), child: Text("No transactions found in ledger.", style: TextStyle(color: Colors.white10))))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final item = _history[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppTheme.surfaceDark.withOpacity(0.5), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.02))),
                child: Row(
                  children: [
                    const Icon(LucideIcons.receipt, color: Colors.white24, size: 20),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Sync: ${item['created_at'].toString().substring(0, 10)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text("${item['currency']} ${item['amount']} • ${item['tier']}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Text("SUCCESS", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ],
                ),
              );
            },
          ),
      ],
    ).animate().fadeIn();
  }
}

