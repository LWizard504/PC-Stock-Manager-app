import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:intl/intl.dart';

class ITUsersScreen extends StatefulWidget {
  const ITUsersScreen({super.key});

  @override
  State<ITUsersScreen> createState() => _ITUsersScreenState();
}

class _ITUsersScreenState extends State<ITUsersScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  bool _isLoading = true;
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  Map<String, dynamic>? _selectedUser;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('profiles')
          .select('*, tenants(name)')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allUsers = List<Map<String, dynamic>>.from(data);
          _applySearch();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("IT Users fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredUsers = List.from(_allUsers);
    } else {
      _filteredUsers = _allUsers.where((u) {
        final name = _getDisplayName(u).toLowerCase();
        final email = (u['email'] as String? ?? '').toLowerCase();
        return name.contains(query) || email.contains(query);
      }).toList();
    }
  }

  String _getDisplayName(Map<String, dynamic> user) {
    String name = user['full_name'] ?? '';
    if (name.isEmpty) {
      final first = user['first_name'] ?? '';
      final last = user['last_name'] ?? '';
      name = '$first $last'.trim();
    }
    return name.isEmpty ? 'Unknown Identity' : name;
  }

  String _getTenantName(Map<String, dynamic> user) {
    final tenants = user['tenants'];
    if (tenants is Map && tenants['name'] != null) {
      return tenants['name'] as String;
    }
    return '--';
  }

  void _showResetDialog(Map<String, dynamic> user) {
    setState(() => _selectedUser = user);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        contentPadding: const EdgeInsets.all(32),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: const Icon(LucideIcons.lock, size: 32, color: Colors.red),
              ),
              const SizedBox(height: 24),
              const Text(
                "Security Dispatch Authorized",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                "We will send a cryptographically secure recovery link to",
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                user['email'] ?? 'No Email',
                style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "This will invalidate current persistent sessions globally for this user node.",
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                        side: const BorderSide(color: Colors.white10),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("ABORT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isResetting ? null : _confirmReset,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isResetting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text("CONFIRM & SEND", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedUser = null);
    });
  }

  Future<void> _confirmReset() async {
    if (_selectedUser == null) return;
    setState(() => _isResetting = true);
    try {
      final email = _selectedUser!['email'] as String? ?? '';
      if (email.isEmpty) {
        ToastUtils.showErrorToast(context, message: "User has no email address registered");
        setState(() => _isResetting = false);
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }
      await _supabase.auth.resetPasswordForEmail(email);
      ToastUtils.showSuccessToast(
        context,
        message: "A professional recovery link has been dispatched to $email",
      );
      setState(() => _isResetting = false);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      ToastUtils.showErrorToast(context, message: "Security auth dispatch failed: $e");
      setState(() => _isResetting = false);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
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
            _buildHeader().animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 40),
            _buildUsersTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Security & Credentials",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
                ),
                const SizedBox(height: 8),
                Text(
                  "Reset passwords locally and manage technical staff accesses.",
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(_applySearch),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Search by name or email...",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
                      prefixIcon: Icon(LucideIcons.search, size: 16, color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: AppTheme.surfaceDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red, width: 0.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _fetchUsers,
                  icon: Icon(_isLoading ? LucideIcons.loader : LucideIcons.refreshCw, color: Colors.red, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUsersTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: _isLoading
          ? const Padding(
              padding: EdgeInsets.all(64),
              child: Center(child: CircularProgressIndicator(color: Colors.red)),
            )
          : _filteredUsers.isEmpty
              ? SizedBox(
                  height: 300,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.users, size: 48, color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isNotEmpty ? "No matching users found" : "No users registered",
                          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.white.withOpacity(0.03)),
                    headingTextStyle: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                    dataTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
                    columns: const [
                      DataColumn(label: Text("NAME")),
                      DataColumn(label: Text("EMAIL")),
                      DataColumn(label: Text("ROLE")),
                      DataColumn(label: Text("TENANT")),
                      DataColumn(label: Text("CREATED")),
                      DataColumn(label: Text("ACTIONS")),
                    ],
                    rows: _filteredUsers.map((user) {
                      final name = _getDisplayName(user);
                      final email = user['email'] as String? ?? 'No Email';
                      final role = (user['role'] as String? ?? 'unknown').toUpperCase();
                      final tenant = _getTenantName(user);
                      final date = user['created_at'] != null
                          ? DateFormat('dd/MM/yyyy').format(DateTime.parse(user['created_at']))
                          : '--';

                      return DataRow(
                        color: WidgetStateProperty.resolveWith((states) {
                          if (_selectedUser?['id'] == user['id']) {
                            return Colors.red.withOpacity(0.05);
                          }
                          return null;
                        }),
                        cells: [
                          DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(email, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontStyle: FontStyle.italic))),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.withOpacity(0.15)),
                            ),
                            child: Text(role, style: const TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.w900)),
                          )),
                          DataCell(Text(tenant, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11))),
                          DataCell(Text(date, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11))),
                          DataCell(
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                onPressed: () => _showResetDialog(user),
                                icon: const Icon(LucideIcons.key, size: 12),
                                label: const Text("RESET", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.withOpacity(0.15),
                                  foregroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05);
  }
}
