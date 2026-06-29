import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';

class ITDashboardScreen extends StatefulWidget {
  const ITDashboardScreen({super.key});

  @override
  State<ITDashboardScreen> createState() => _ITDashboardScreenState();
}

class _ITDashboardScreenState extends State<ITDashboardScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _showTutorial = false;

  double _uptime = 0;
  double _latency = 0;
  int _nodeCount = 0;
  String _secIndex = 'N/A';
  double _protocolIntegrity = 0;
  List<double> _signalData = [];
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _checkTutorial();
    await _fetchData();
    _subscribe();
  }

  Future<void> _checkTutorial() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final data = await _supabase
        .from('profiles')
        .select('tutorial_completed')
        .eq('id', user.id)
        .maybeSingle();
    if (data?['tutorial_completed'] != true) {
      if (mounted) setState(() => _showTutorial = true);
    }
  }

  Future<void> _finishTutorial() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      await _supabase
          .from('profiles')
          .update({'tutorial_completed': true})
          .eq('id', user.id);
    }
    if (mounted) setState(() => _showTutorial = false);
  }

  void _subscribe() {
    _supabase
        .channel('it-audit-logs')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'audit_logs',
          callback: (_) => _fetchData(),
        )
        .subscribe();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final latencyStart = DateTime.now();
      await _supabase.from('app_config').select('key').limit(1);
      final latencyMs = DateTime.now().difference(latencyStart).inMilliseconds.toDouble();

      final tenantsData = await _supabase
          .from('tenants')
          .select('id')
          .eq('is_active', true);
      final nodeCount = (tenantsData as List).length;

      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final recentLogs = await _supabase
          .from('audit_logs')
          .select('severity, created_at')
          .gte('created_at', sevenDaysAgo);

      final logsList = recentLogs as List;
      final totalLogs = logsList.length > 0 ? logsList.length : 1;
      final criticalCount = logsList.where((l) => l['severity'] == 'CRITICAL').length;
      final warningCount = logsList.where((l) => l['severity'] == 'WARNING').length;
      final infoCount = logsList.where((l) => l['severity'] == 'INFO').length;

      double uptimeDays = 0;
      if (logsList.isNotEmpty) {
        final dates = logsList.map((l) => DateTime.parse(l['created_at'] as String)).toList();
        dates.sort();
        uptimeDays = dates.last.difference(dates.first).inDays.toDouble();
        if (uptimeDays < 1) uptimeDays = 1;
      }

      final severityScore = (infoCount * 1 + warningCount * 0.5 + criticalCount * 0) / totalLogs * 100;
      final secIndex = severityScore >= 90 ? 'A+' : severityScore >= 75 ? 'A' : severityScore >= 50 ? 'B' : 'C';

      final integrity = ((totalLogs - criticalCount) / totalLogs) * 100;

      final signalData = <double>[];
      for (int h = 9; h >= 0; h--) {
        final hourStart = DateTime.now().subtract(Duration(hours: h));
        final hourEnd = hourStart.add(const Duration(hours: 1));
        final count = logsList.where((l) {
          final t = DateTime.parse(l['created_at'] as String);
          return t.isAfter(hourStart) && t.isBefore(hourEnd);
        }).length;
        signalData.add(count.toDouble());
      }

      final logData = await _supabase
          .from('audit_logs')
          .select('*')
          .eq('severity', 'CRITICAL')
          .order('created_at', ascending: false)
          .limit(20);

      if (mounted) {
        setState(() {
          _uptime = uptimeDays;
          _latency = latencyMs;
          _nodeCount = nodeCount;
          _secIndex = secIndex;
          _protocolIntegrity = integrity;
          _signalData = signalData;
          _logs = List<Map<String, dynamic>>.from(logData);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("IT Dashboard error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _signalBarsForMetric(String metric) {
    switch (metric) {
      case 'uptime':
        if (_uptime >= 30) return 4;
        if (_uptime >= 14) return 3;
        if (_uptime >= 7) return 2;
        if (_uptime >= 1) return 1;
        return 0;
      case 'latency':
        if (_latency <= 20) return 4;
        if (_latency <= 50) return 3;
        if (_latency <= 100) return 2;
        if (_latency <= 200) return 1;
        return 0;
      case 'nodeCount':
        if (_nodeCount >= 50) return 4;
        if (_nodeCount >= 20) return 3;
        if (_nodeCount >= 5) return 2;
        if (_nodeCount >= 1) return 1;
        return 0;
      case 'secIndex':
        if (_secIndex == 'A+') return 4;
        if (_secIndex == 'A') return 3;
        if (_secIndex == 'B') return 2;
        if (_secIndex == 'C') return 1;
        return 0;
      case 'protocolIntegrity':
        if (_protocolIntegrity >= 95) return 4;
        if (_protocolIntegrity >= 85) return 3;
        if (_protocolIntegrity >= 70) return 2;
        if (_protocolIntegrity >= 50) return 1;
        return 0;
      default:
        return 0;
    }
  }

  String _getTrend(String metric) {
    switch (metric) {
      case 'uptime':
        return _uptime >= 30 ? '+Stable' : '+Growing';
      case 'latency':
        return _latency <= 50 ? '-Optimal' : '+Elevated';
      case 'nodeCount':
        return _nodeCount > 0 ? 'Online' : 'Offline';
      case 'secIndex':
        return _secIndex == 'A+' ? 'Highest' : _secIndex == 'A' ? 'Strong' : 'Elevated';
      case 'protocolIntegrity':
        return _protocolIntegrity >= 95 ? 'Secure' : 'Warning';
      default:
        return '--';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.red))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader().animate().fadeIn().slideY(begin: -0.2),
                      const SizedBox(height: 40),
                      _buildMetricCards(),
                      const SizedBox(height: 48),
                      _buildCriticalLogs(),
                    ],
                  ),
                ),
        ),
        if (_showTutorial) _buildTutorialOverlay(),
      ],
    );
  }

  Widget _buildTutorialOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(LucideIcons.terminal, size: 40, color: Colors.red),
                ),
                const SizedBox(height: 24),
                const Text(
                  "IT Telemetry Dashboard",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  "Monitor system metrics, signal strength, and critical audit events in real-time. "
                  "Use the refresh button to pull the latest telemetry from the network.",
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _finishTutorial,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text("ACKNOWLEDGE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn().scale()
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Network Logistics",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
            ),
            const SizedBox(height: 8),
            Text(
              "System Telemetry • Global Event Stream",
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ],
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.greenAccent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Protocol: Online",
                    style: TextStyle(color: Colors.greenAccent.withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: _fetchData,
              icon: Icon(_isLoading ? LucideIcons.loader : LucideIcons.refreshCw, color: Colors.red, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCards() {
    final metrics = [
      {'label': 'Uptime', 'value': '${_uptime.toStringAsFixed(0)}d', 'icon': LucideIcons.cpu, 'key': 'uptime'},
      {'label': 'Latency', 'value': '${_latency.toStringAsFixed(0)}ms', 'icon': LucideIcons.activity, 'key': 'latency'},
      {'label': 'Node Count', 'value': '$_nodeCount', 'icon': LucideIcons.server, 'key': 'nodeCount'},
      {'label': 'Security Index', 'value': _secIndex, 'icon': LucideIcons.shieldCheck, 'key': 'secIndex'},
      {'label': 'Protocol Integrity', 'value': '${_protocolIntegrity.toStringAsFixed(1)}%', 'icon': LucideIcons.shield, 'key': 'protocolIntegrity'},
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: metrics.asMap().entries.map((entry) {
        final i = entry.key;
        final m = entry.value;
        final key = m['key'] as String;
        final bars = _signalBarsForMetric(key);
        return SizedBox(
          width: 280,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Icon(m['icon'] as IconData, size: 18, color: Colors.red),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _getTrend(key),
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.red, letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  m['label'] as String,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      m['value'] as String,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const Spacer(),
                    _buildSignalBars(bars),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(delay: (100 + i * 80).ms).slideY(begin: 0.1)
        );
      }).toList(),
    );
  }

  Widget _buildSignalBars(int filled) {
    return Row(
      children: List.generate(4, (i) {
        final isFilled = i < filled;
        return Container(
          width: 6,
          height: 8 + i * 4,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: isFilled ? Colors.red : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildCriticalLogs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.terminal, size: 18, color: Colors.red),
              ),
              const SizedBox(width: 12),
              const Text(
                "Critical Audit Events",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
              ),
              const Spacer(),
              Text(
                "${_logs.length} events",
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_logs.isEmpty)
            SizedBox(
              height: 100,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.checkCircle2, size: 20, color: Colors.greenAccent.withOpacity(0.5)),
                    const SizedBox(width: 12),
                    Text(
                      "No critical events in recent window",
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  return _buildLogItem(log);
                },
              ),
            ),
        ],
      ),
    ).animate().fadeIn(delay: 500.ms);
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final action = log['action'] ?? 'Unknown Action';
    final details = log['details'] is Map ? log['details'] : <String, dynamic>{};
    final createdAt = log['created_at'] != null
        ? DateFormat('HH:mm:ss').format(DateTime.parse(log['created_at']))
        : '--:--:--';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.zap, size: 12, color: Colors.red),
          ),
          const SizedBox(width: 12),
          Text(
            createdAt,
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      details.toString(),
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
            ),
            child: const Text(
              "CRITICAL",
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.red, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }
}
