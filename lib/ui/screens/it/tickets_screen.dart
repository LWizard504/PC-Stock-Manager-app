import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pc_dev_flutter/ui/widgets/skeleton_loader.dart';

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _tickets = [];
  bool _isLoading = true;
  String _statusFilter = "all";
  Map<String, dynamic>? _selectedTicket;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      var query = _supabase
          .from('tickets')
          .select('*, creator:profiles!creator_id(full_name, email, tenants(name))');

      if (_statusFilter != "all") {
        query = query.eq('status', _statusFilter);
      }

      final data = await query.order('created_at', ascending: false);
      setState(() {
        _tickets = List<Map<String, dynamic>>.from(data);
        if (_selectedTicket != null) {
          final idToFind = _selectedTicket!['id'];
          final found = _tickets.where((t) => t['id'] == idToFind).toList();
          _selectedTicket = found.isNotEmpty ? found.first : null;
        }
      });
    } catch (e) {
      debugPrint("Error fetching tickets: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateTicketStatus(String id, String status) async {
    try {
      await _supabase.from('tickets').update({'status': status}).eq('id', id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ticket marcado como $status")),
      );
      _fetchTickets();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error actualizando ticket: $e")),
      );
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent': return Colors.redAccent;
      case 'high': return Colors.orangeAccent;
      case 'normal': return Colors.blueAccent;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open': return Colors.greenAccent;
      case 'in_progress': return Colors.yellowAccent;
      case 'resolved': return Colors.blueAccent;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
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
                    Text("Soporte y Tickets", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
                    const SizedBox(height: 8),
                    const Text("Gestión y resolución de incidencias en tiempo real.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                // Status Filter Segment
                Row(
                  children: ["all", "open", "in_progress", "resolved"].map((filter) {
                    final isSelected = _statusFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(filter.toUpperCase().replaceAll('_', ' ')),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _statusFilter = filter;
                            });
                            _fetchTickets();
                          }
                        },
                        selectedColor: AppTheme.primaryColor,
                        backgroundColor: const Color(0xFF1E1E1E),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ).animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 32),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tickets List
                  Expanded(
                    flex: 3,
                    child: _isLoading
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: SkeletonLoader.table(rows: 6, columns: 4),
                          )
                        : _tickets.isEmpty
                            ? Card(
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(LucideIcons.ticket, size: 64, color: AppTheme.secondaryColor),
                                      SizedBox(height: 16),
                                      Text("No hay tickets activos en este segmento", style: TextStyle(fontSize: 18, color: Colors.white70)),
                                    ],
                                  ),
                                ),
                              ).animate().fadeIn().slideY()
                            : ListView.builder(
                                itemCount: _tickets.length,
                                itemBuilder: (context, index) {
                                  final ticket = _tickets[index];
                                  final isSelected = _selectedTicket?['id'] == ticket['id'];
                                  final priority = ticket['priority'] ?? 'normal';
                                  final status = ticket['status'] ?? 'open';
                                  final creatorName = ticket['creator']?['full_name'] ?? 'Incógnito';
                                  final tenantName = ticket['creator']?['tenants']?['name'] ?? 'Principal';
                                  final dateStr = ticket['created_at'] != null 
                                      ? DateFormat('dd/MM/yyyy').format(DateTime.parse(ticket['created_at']))
                                      : 'N/A';

                                  return Card(
                                    color: isSelected ? AppTheme.primaryColor.withOpacity(0.05) : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: isSelected ? AppTheme.primaryColor.withOpacity(0.4) : const Color(0xFF1E1E1E),
                                        width: 1,
                                      ),
                                    ),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                      onTap: () {
                                        setState(() {
                                          _selectedTicket = ticket;
                                        });
                                      },
                                      title: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              _buildBadge(priority.toUpperCase(), _getPriorityColor(priority)),
                                              const SizedBox(width: 8),
                                              _buildBadge(status.toUpperCase().replaceAll('_', ' '), _getStatusColor(status)),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            ticket['title'] ?? 'Sin Título',
                                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Row(
                                          children: [
                                            const Icon(LucideIcons.user, size: 14, color: Colors.white38),
                                            const SizedBox(width: 6),
                                            Text(creatorName, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                            const SizedBox(width: 16),
                                            const Icon(LucideIcons.calendar, size: 14, color: Colors.white38),
                                            const SizedBox(width: 6),
                                            Text(dateStr, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                            const SizedBox(width: 16),
                                            const Icon(LucideIcons.home, size: 14, color: Colors.white38),
                                            const SizedBox(width: 6),
                                            Text(tenantName, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      trailing: const Icon(LucideIcons.chevronRight, color: Colors.white30),
                                    ),
                                  );
                                },
                              ).animate().fadeIn().slideY(),
                  ),
                  const SizedBox(width: 32),
                  // Sidebar Details
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: _selectedTicket == null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(LucideIcons.ticket, size: 48, color: Colors.white24),
                                    SizedBox(height: 16),
                                    Text("Selecciona un ticket para ver los detalles", style: TextStyle(color: Colors.white30)),
                                  ],
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "ANÁLISIS DE TICKET",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppTheme.primaryColor, letterSpacing: 2),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _selectedTicket!['title'] ?? 'Sin Título',
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                                  ),
                                  const SizedBox(height: 24),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F0F0F),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF1E1E1E)),
                                    ),
                                    child: Text(
                                      _selectedTicket!['description'] ?? 'Sin descripción',
                                      style: const TextStyle(color: Colors.white70, height: 1.5),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  const Text(
                                    "ACCIONES TÉCNICAS",
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1.5),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_selectedTicket!['status'] != 'resolved')
                                    ElevatedButton.icon(
                                      onPressed: () => _updateTicketStatus(_selectedTicket!['id'], 'resolved'),
                                      icon: const Icon(LucideIcons.checkCircle2),
                                      label: const Text("RESOLVER TICKET"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(double.infinity, 48),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  if (_selectedTicket!['status'] == 'open') ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () => _updateTicketStatus(_selectedTicket!['id'], 'in_progress'),
                                      icon: const Icon(LucideIcons.clock),
                                      label: const Text("MARCAR EN PROGRESO"),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.yellowAccent,
                                        side: const BorderSide(color: Colors.yellowAccent),
                                        minimumSize: const Size(double.infinity, 48),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
