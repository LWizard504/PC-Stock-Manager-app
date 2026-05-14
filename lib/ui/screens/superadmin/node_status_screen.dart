import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class NodeStatusScreen extends StatefulWidget {
  const NodeStatusScreen({super.key});

  @override
  State<NodeStatusScreen> createState() => _NodeStatusScreenState();
}

class _NodeStatusScreenState extends State<NodeStatusScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _nodes = [];

  @override
  void initState() {
    super.initState();
    _fetchNodes();
  }

  Future<void> _fetchNodes() async {
    try {
      final supabase = Supabase.instance.client;
      // Fetch tenants as nodes
      final response = await supabase.from('tenants').select('*, branches(count)');
      
      if (mounted) {
        setState(() {
          _nodes = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
                    Text("Telemetría de Nodos", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text("Estado operacional de los clústeres en la red global.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _fetchNodes,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text("Refrescar Red"),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceLight),
                ),
              ],
            ).animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 48),
            
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(64), child: CircularProgressIndicator(color: Colors.red)))
            else if (_nodes.isEmpty)
              const Center(child: Text("No se detectan nodos activos"))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                  childAspectRatio: 1.5,
                ),
                itemCount: _nodes.length,
                itemBuilder: (context, index) => _buildNodeCard(_nodes[index]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeCard(Map<String, dynamic> node) {
    final bool isOnline = true; // Placeholder for health check
    final int branches = (node['branches'] as List).isEmpty ? 0 : (node['branches'][0]['count'] ?? 0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isOnline ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.server, color: Colors.white70, size: 20),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.greenAccent : Colors.redAccent,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: isOnline ? Colors.greenAccent : Colors.redAccent, blurRadius: 10)],
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(node['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("ID: ${node['id'].toString().substring(0, 8)}", style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStat("SUCURSALES", branches.toString()),
              const SizedBox(width: 24),
              _buildStat("LATENCIA", "24ms"),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildStat(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
        Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
