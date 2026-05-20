import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';
import 'package:pc_dev_flutter/services/signaling_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _myProfile;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final t = Provider.of<LocaleProvider>(context, listen: false).t;
    ToastUtils.showPromiseToast(
      context, 
      message: t('sync'), 
      promise: _fetchUsers(), 
      successMessage: t('sync'), 
      errorMessage: "Sync Failure"
    );
  }

  Future<void> _fetchUsers() async {
    try {
      if (mounted) setState(() => _isLoading = true);
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("No auth");

      _myProfile = await supabase
          .from('profiles')
          .select('role, tenant_id')
          .eq('id', user.id)
          .maybeSingle();

      if (_myProfile == null) {
        throw Exception("No se encontró tu perfil de usuario en la base de datos.");
      }

      final role = _myProfile?['role'] as String? ?? 'employee';
      final tenantId = _myProfile?['tenant_id'];

      var query = supabase.from('profiles').select('*, branches(name)');

      if (!(role == 'superadmin' || role == 'global_it')) {
        if (tenantId != null) {
          query = query.eq('tenant_id', tenantId);
        } else {
          query = query.eq('id', user.id);
        }
      }

      final response = await query.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(response as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      rethrow;
    }
  }

  void _showAddUserDialog() {
    final t = Provider.of<LocaleProvider>(context, listen: false).t;
    final emailController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final passwordController = TextEditingController(text: "StakiaNode2026!");
    String selectedRole = "employee";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: Text(t('users_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstNameController,
                  decoration: const InputDecoration(labelText: "First Name", labelStyle: TextStyle(color: Colors.white38)),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(labelText: "Last Name", labelStyle: TextStyle(color: Colors.white38)),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(labelText: t('email'), labelStyle: const TextStyle(color: Colors.white38)),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t('password'), labelStyle: const TextStyle(color: Colors.white38)),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: const Color(0xFF1A1A1A),
                  decoration: const InputDecoration(labelText: "Access Level", labelStyle: TextStyle(color: Colors.white38)),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: "admin", child: Text("Administrator")),
                    DropdownMenuItem(value: "manager", child: Text("Manager")),
                    DropdownMenuItem(value: "employee", child: Text("Employee")),
                    DropdownMenuItem(value: "it", child: Text("IT Support")),
                  ],
                  onChanged: (val) => selectedRole = val!,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'), style: const TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _createUser(firstNameController.text, lastNameController.text, emailController.text, passwordController.text, selectedRole);
            },
            child: Text(t('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _createUser(String firstName, String lastName, String email, String password, String role) async {
    ToastUtils.showPromiseToast(
      context, 
      message: "Provisioning...", 
      promise: _executeCreation(firstName, lastName, email, password, role), 
      successMessage: "Identity Created", 
      errorMessage: "Provisioning Error"
    );
  }

  Future<void> _executeCreation(String firstName, String lastName, String email, String password, String role) async {
    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception("Tu sesión de usuario no es válida o ha expirado. Por favor, inicia sesión nuevamente.");
      }
      
      String? tenantId;
      if (_myProfile != null) {
        tenantId = _myProfile?['tenant_id'];
      } else {
        final myProfileResponse = await supabase.from('profiles').select('tenant_id').eq('id', currentUser.id).maybeSingle();
        tenantId = myProfileResponse?['tenant_id'];
      }

      // Call SignalingService REST proxy
      await SignalingService().adminCreateUser(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
        role: role,
        tenantId: tenantId,
      );
      
      _loadData();
    } catch (e) {
      rethrow;
    }
  }

  void _showResetPasswordDialog(Map<String, dynamic> userMap) {
    final t = Provider.of<LocaleProvider>(context, listen: false).t;
    final passwordController = TextEditingController();
    String name = userMap['full_name'] ?? '';
    if (name.isEmpty) {
      final first = userMap['first_name'] ?? '';
      final last = userMap['last_name'] ?? '';
      name = '$first $last'.trim();
    }
    if (name.isEmpty) name = 'Unknown Identity';
    final email = userMap['email'] ?? 'No Email';
    final userId = userMap['id'];
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF121212),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
          title: const Text("Reset Password", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Target: $name ($email)",
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: "New Password",
                    labelStyle: const TextStyle(color: Colors.white38),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                        color: Colors.white38,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('cancel'), style: const TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                if (passwordController.text.trim().length < 6) {
                  ToastUtils.showCustomToast(context, "Password must be at least 6 characters", isError: true);
                  return;
                }
                Navigator.pop(context);
                _resetUserPassword(userId, email, passwordController.text.trim());
              },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetUserPassword(String userId, String email, String newPassword) async {
    ToastUtils.showPromiseToast(
      context, 
      message: "Resetting...", 
      promise: _executePasswordReset(userId, email, newPassword), 
      successMessage: "Password updated successfully", 
      errorMessage: "Reset Failure"
    );
  }

  Future<void> _executePasswordReset(String userId, String email, String newPassword) async {
    try {
      await SignalingService().adminResetPassword(userId, email, newPassword);
      _loadData();
    } catch (e) {
      rethrow;
    }
  }

  void _showPurgeConfirmDialog(Map<String, dynamic> userMap) {
    final t = Provider.of<LocaleProvider>(context, listen: false).t;
    String name = userMap['full_name'] ?? '';
    if (name.isEmpty) {
      final first = userMap['first_name'] ?? '';
      final last = userMap['last_name'] ?? '';
      name = '$first $last'.trim();
    }
    if (name.isEmpty) name = 'Unknown Identity';
    final email = userMap['email'] ?? 'No Email';
    final userId = userMap['id'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: const Text("Confirm Purge", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Are you sure you want to permanently delete this identity?",
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              "Target: $name ($email)",
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "All associated telemetry and access credentials will be purged from the network. This action cannot be undone.",
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel'), style: const TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _purgeUser(userId, name, email);
            },
            child: const Text("PURGE IDENTITY"),
          ),
        ],
      ),
    );
  }

  Future<void> _purgeUser(String userId, String name, String email) async {
    ToastUtils.showPromiseToast(
      context, 
      message: "Purging...", 
      promise: _executePurge(userId, name, email), 
      successMessage: "Identity purged from network", 
      errorMessage: "Purge Error"
    );
  }

  Future<void> _executePurge(String userId, String name, String email) async {
    try {
      await SignalingService().adminPurgeUser(userId, name, email);
      _loadData();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tProvider = Provider.of<LocaleProvider>(context);
    final t = tProvider.t;

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
                    Text(t('users_title'), style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(t('users_subtitle'), style: const TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                Row(
                  children: [
                    // Language Toggle (Parity with Web)
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          _buildLangBtn("EN", tProvider.locale.languageCode == 'en', () => tProvider.setLocale(const Locale('en'))),
                          _buildLangBtn("ES", tProvider.locale.languageCode == 'es', () => tProvider.setLocale(const Locale('es'))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    ElevatedButton.icon(
                      onPressed: () => _loadData(),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: Text(t('refresh')),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceLight, foregroundColor: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _showAddUserDialog,
                      icon: const Icon(LucideIcons.userPlus, size: 16),
                      label: const Text("New Identity"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ).animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 48),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('users_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    if (_isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(64), child: CircularProgressIndicator(color: Colors.red)))
                    else if (_users.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(64), child: Text("Empty Ledger", style: TextStyle(color: Colors.white24))))
                    else
                      _buildUsersTable(t),
                  ],
                ),
              ),
            ).animate().fadeIn().slideY(),
          ],
        ),
      ),
    );
  }

  Widget _buildLangBtn(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.red.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.red : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildUsersTable(String Function(String) t) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
        columns: [
          DataColumn(label: Text(t('actions').toUpperCase())),
          const DataColumn(label: Text("IDENTITY")),
          const DataColumn(label: Text("EMAIL")),
          const DataColumn(label: Text("ROLE")),
          const DataColumn(label: Text("NODE")),
        ],
        rows: _users.map((user) {
          String name = user['full_name'] ?? '';
          if (name.isEmpty) {
            final first = user['first_name'] ?? '';
            final last = user['last_name'] ?? '';
            name = '$first $last'.trim();
          }
          if (name.isEmpty) name = 'Unknown Identity';

          final role = user['role']?.toString().toUpperCase() ?? 'USER';
          final email = user['email'] ?? 'No Email';
          final branch = user['branches'] != null ? user['branches']['name'] : 'Global';
          final avatarUrl = user['avatar_url'];

          return DataRow(cells: [
            DataCell(
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 16, color: Colors.white38),
                color: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white10)),
                onSelected: (val) {
                  if (val == 'reset') _showResetPasswordDialog(user);
                  if (val == 'delete') _showPurgeConfirmDialog(user);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'reset', child: Text("Reset Password", style: TextStyle(color: Colors.white, fontSize: 12))),
                  const PopupMenuItem(value: 'delete', child: Text("Purge Identity", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            DataCell(Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    image: avatarUrl != null ? DecorationImage(image: NetworkImage(avatarUrl), fit: BoxFit.cover) : null,
                  ),
                  child: avatarUrl == null 
                    ? Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)))
                    : null,
                ),
                const SizedBox(width: 12),
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            )),
            DataCell(Text(email, style: const TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic))),
            DataCell(Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(role, style: const TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
            )),
            DataCell(Text(branch, style: const TextStyle(color: Colors.white60, fontSize: 11))),
          ]);
        }).toList(),
      ),
    );
  }
}

