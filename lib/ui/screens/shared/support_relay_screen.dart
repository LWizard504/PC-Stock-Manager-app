import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';

class SupportTicket {
  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final String createdBy;
  final DateTime createdAt;
  final String? assignedTo;

  SupportTicket({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.createdBy,
    required this.createdAt,
    this.assignedTo,
  });

  factory SupportTicket.fromMap(Map<String, dynamic> map) {
    return SupportTicket(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'open',
      priority: map['priority'] as String? ?? 'normal',
      createdBy: map['created_by'] as String? ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
      assignedTo: map['assigned_to'] as String?,
    );
  }
}

const _statusConfig = {
  'open':       {'label': 'Open',        'color': Color(0xFFEAB308)},
  'in_progress':{'label': 'In Progress', 'color': Color(0xFF3B82F6)},
  'resolved':   {'label': 'Resolved',    'color': Color(0xFF10B981)},
  'closed':     {'label': 'Closed',      'color': Color(0xFF6B7280)},
};

const _priorityColors = {
  'low':    Color(0xFF6B7280),
  'normal': Color(0xFFEAB308),
  'high':   Color(0xFFF97316),
  'urgent': Color(0xFFEF4444),
};

class SupportRelayScreen extends StatefulWidget {
  const SupportRelayScreen({super.key});

  @override
  State<SupportRelayScreen> createState() => _SupportRelayScreenState();
}

class _SupportRelayScreenState extends State<SupportRelayScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  List<SupportTicket> _tickets = [];
  SupportTicket? _selectedTicket;
  String _statusFilter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchTickets();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTickets() async {
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

      final data = await _supabase
          .from('tickets')
          .select('id, title, description, status, priority, created_by, created_at, assigned_to')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _tickets = (data as List).map((e) => SupportTicket.fromMap(e as Map<String, dynamic>)).toList();
          _isLoading = false;
          if (_selectedTicket != null) {
            _selectedTicket = _tickets.where((t) => t.id == _selectedTicket!.id).firstOrNull;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastUtils.showErrorToast(context, message: 'Failed to load tickets');
      }
    }
  }

  List<SupportTicket> get _filteredTickets {
    var list = _tickets;
    if (_statusFilter != 'all') {
      list = list.where((t) => t.status == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((t) =>
        t.title.toLowerCase().contains(_searchQuery) ||
        t.description.toLowerCase().contains(_searchQuery)
      ).toList();
    }
    return list;
  }

  Future<void> _updateTicketStatus(SupportTicket ticket, String newStatus) async {
    try {
      await _supabase.from('tickets').update({'status': newStatus}).eq('id', ticket.id);
      ToastUtils.showSuccessToast(context, message: 'Ticket ${newStatus == 'in_progress' ? 'moved to in progress' : newStatus}');
      _fetchTickets();
    } catch (e) {
      ToastUtils.showErrorToast(context, message: 'Failed to update ticket');
    }
  }

  void _showCreateTicketDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String priority = 'normal';
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.all(32),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(LucideIcons.ticket, color: AppTheme.accentColor, size: 20),
                        ),
                        const SizedBox(width: 16),
                        const Text("Create Support Ticket",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text("Issue Headline",
                      style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "e.g. Database Sync Failure",
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.03),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.accentColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text("Technical Description",
                      style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      maxLines: 5,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "Provide as much detail as possible...",
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.03),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.accentColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text("Priority Level",
                      style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    Row(
                      children: ['low', 'normal', 'high', 'urgent'].map((p) {
                        final selected = priority == p;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: p == 'urgent' ? 0 : 8),
                            child: GestureDetector(
                              onTap: submitting ? null : () => setDialogState(() => priority = p),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: selected ? _priorityColors[p]!.withOpacity(0.2) : Colors.white.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected ? _priorityColors[p]! : Colors.white.withOpacity(0.08),
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Text(p.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: selected ? _priorityColors[p] : Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  )),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                          child: const Text("Cancel",
                            style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1)),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: AppTheme.accentColor.withOpacity(0.3), blurRadius: 12)],
                          ),
                          child: ElevatedButton(
                            onPressed: submitting ? null : () async {
                              if (titleController.text.trim().isEmpty || descController.text.trim().isEmpty) {
                                ToastUtils.showErrorToast(context, message: 'Please fill all fields');
                                return;
                              }
                              setDialogState(() => submitting = true);
                              try {
                                final user = _supabase.auth.currentUser;
                                if (user == null) throw Exception('Authentication failed');

                                final profile = await _supabase
                                    .from('profiles')
                                    .select('tenant_id')
                                    .eq('id', user.id)
                                    .single();
                                if (profile['tenant_id'] == null) throw Exception('No tenant associated');

                                await _supabase.from('tickets').insert({
                                  'title': titleController.text.trim(),
                                  'description': descController.text.trim(),
                                  'priority': priority,
                                  'status': 'open',
                                  'tenant_id': profile['tenant_id'],
                                  'created_by': user.id,
                                });

                                if (ctx.mounted) Navigator.of(ctx).pop();
                                ToastUtils.showSuccessToast(context, message: 'Support ticket created successfully');
                                _fetchTickets();
                              } catch (e) {
                                ToastUtils.showErrorToast(context, message: 'Failed to create ticket');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: submitting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text("SUBMIT TICKET",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
                  SizedBox(height: 16),
                  Text("ESTABLISHING RELAY CONNECTION...",
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                ],
              ),
            )
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildLeftPanel(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: _buildRightPanel(),
                ),
              ],
            ),
    );
  }

  Widget _buildLeftPanel() {
    final filtered = _filteredTickets;
    final activeCount = _tickets.where((t) => t.status == 'open' || t.status == 'in_progress').length;
    final resolvedCount = _tickets.where((t) => t.status == 'resolved' || t.status == 'closed').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      const Text("Support Relay",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(LucideIcons.messageSquare, size: 14, color: Colors.white38),
                      SizedBox(width: 8),
                      Text("Direct encrypted link to IT technician nodes",
                        style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: AppTheme.accentColor.withOpacity(0.3), blurRadius: 16)],
              ),
              child: ElevatedButton.icon(
                onPressed: _showCreateTicketDialog,
                icon: const Icon(LucideIcons.ticket, size: 18),
                label: const Text("OPEN NEW TICKET",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ).animate().fadeIn(),

        const SizedBox(height: 24),

        Row(
          children: [
            _buildStatCard("Active Tickets", activeCount.toString(), null),
            const SizedBox(width: 12),
            _buildStatCard("Resolved", resolvedCount.toString(), AppTheme.accentColor),
            const SizedBox(width: 12),
            _buildStatCard("Total Requests", _tickets.length.toString(), null),
          ],
        ).animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 20),

        TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: "Search tickets...",
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            prefixIcon: const Icon(LucideIcons.search, color: Colors.white24, size: 18),
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
          ),
        ).animate().fadeIn(delay: 150.ms),

        const SizedBox(height: 16),

        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['all', 'open', 'in_progress', 'resolved', 'closed'].map((status) {
              final active = _statusFilter == status;
              final label = status == 'all' ? 'All' : (_statusConfig[status]?['label'] as String? ?? status);
              final color = status == 'all' ? Colors.white : _statusConfig[status]?['color'] as Color? ?? Colors.white;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _statusFilter = status),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? color.withOpacity(0.15) : Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active ? color.withOpacity(0.4) : Colors.white.withOpacity(0.06),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: color.withOpacity(0.6), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(label,
                          style: TextStyle(
                            color: active ? color : Colors.white38,
                            fontSize: 11, fontWeight: FontWeight.w800,
                          )),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ).animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 16),

        Expanded(
          child: filtered.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.inbox, color: Colors.white12, size: 48),
                    const SizedBox(height: 16),
                    const Text("No tickets found",
                      style: TextStyle(color: Colors.white38, fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final ticket = filtered[i];
                  final statusColor = _statusConfig[ticket.status]?['color'] as Color? ?? Colors.white;
                  final priorityColor = _priorityColors[ticket.priority] ?? Colors.white;
                  final isSelected = _selectedTicket?.id == ticket.id;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedTicket = ticket),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withOpacity(0.05) : AppTheme.surfaceDark.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(ticket.title,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                                        overflow: TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: statusColor.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        (_statusConfig[ticket.status]?['label'] as String? ?? ticket.status).toUpperCase(),
                                        style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(ticket.description,
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(LucideIcons.clock, size: 12, color: Colors.white24),
                                    const SizedBox(width: 6),
                                    Text(_formatDate(ticket.createdAt),
                                      style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 16),
                                    Container(
                                      width: 6, height: 6,
                                      decoration: BoxDecoration(color: priorityColor, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(ticket.priority.toUpperCase(),
                                      style: TextStyle(color: priorityColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: (50 * i).ms);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color? color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
              style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Text(value,
              style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900,
                color: color ?? Colors.white,
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    if (_selectedTicket == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark.withOpacity(0.3),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.messageSquare, color: Colors.white12, size: 56),
              const SizedBox(height: 16),
              const Text("Select a ticket",
                style: TextStyle(color: Colors.white38, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text("Choose a ticket from the list to view details",
                style: TextStyle(color: Colors.white24, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    final ticket = _selectedTicket!;
    final statusColor = _statusConfig[ticket.status]?['color'] as Color? ?? Colors.white;
    final statusLabel = _statusConfig[ticket.status]?['label'] as String? ?? ticket.status;
    final priorityColor = _priorityColors[ticket.priority] ?? Colors.white;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Icon(LucideIcons.ticket, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ticket.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(LucideIcons.clock, size: 12, color: Colors.white24),
                        const SizedBox(width: 6),
                        Text("Created ${_formatDate(ticket.createdAt)}",
                          style: const TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              _buildMetaChip("Status", statusLabel.toUpperCase(), statusColor, Icons.circle),
              const SizedBox(width: 12),
              _buildMetaChip("Priority", ticket.priority.toUpperCase(), priorityColor, Icons.flag),
            ],
          ),
          const SizedBox(height: 28),
          const Text("DESCRIPTION",
            style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(ticket.description,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6)),
            ),
          ),
          const SizedBox(height: 24),
          if (ticket.status == 'open' || ticket.status == 'in_progress')
            Row(
              children: [
                if (ticket.status == 'open')
                  Expanded(
                    child: _buildActionButton(
                      "MARK IN PROGRESS",
                      LucideIcons.play,
                      AppTheme.accentColor,
                      () => _updateTicketStatus(ticket, 'in_progress'),
                    ),
                  ),
                if (ticket.status == 'in_progress')
                  Expanded(
                    child: _buildActionButton(
                      "RESOLVE",
                      LucideIcons.checkCircle2,
                      AppTheme.accentColor,
                      () => _updateTicketStatus(ticket, 'resolved'),
                    ),
                  ),
                if (ticket.status != 'closed')
                  Padding(
                    padding: EdgeInsets.only(left: ticket.status == 'open' ? 12 : 0),
                    child: _buildActionButton(
                      "CLOSE",
                      LucideIcons.xCircle,
                      Colors.white38,
                      () => _updateTicketStatus(ticket, 'closed'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildMetaChip(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(value,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: color == AppTheme.accentColor
            ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 12)]
            : null,
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color == AppTheme.accentColor ? color : Colors.white.withOpacity(0.06),
          foregroundColor: color == AppTheme.accentColor ? Colors.white : Colors.white54,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: color != AppTheme.accentColor
              ? BorderSide(color: Colors.white.withOpacity(0.08))
              : BorderSide.none,
          elevation: 0,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
