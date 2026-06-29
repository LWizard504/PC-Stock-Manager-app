import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:provider/provider.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  List<Map<String, dynamic>> _branches = [];
  final Set<String> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  Map<String, int?>? _userLimit;

  // Provision form
  bool _isProvisioning = false;
  final _formFirstNameController = TextEditingController();
  final _formLastNameController = TextEditingController();
  final _formEmailController = TextEditingController();
  final _formPasswordController = TextEditingController();
  final _formEmployeeCodeController = TextEditingController();
  String _formRole = 'employee';
  String? _formBranchId;

  // Audit log state
  Map<String, dynamic>? _selectedEmployee;
  List<Map<String, dynamic>> _employeeLogs = [];
  bool _fetchingLogs = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterEmployees);
    _fetchAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _formFirstNameController.dispose();
    _formLastNameController.dispose();
    _formEmailController.dispose();
    _formPasswordController.dispose();
    _formEmployeeCodeController.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _supabase
        .channel('employee-updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _fetchEmployees(),
        )
        .subscribe();
  }

  Future<void> _fetchAll() async {
    await Future.wait([_fetchEmployees(), _fetchBranches()]);
  }

  Future<void> _fetchEmployees() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .single();
      final tenantId = profile['tenant_id'];

      if (tenantId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final response = await _supabase
          .from('profiles')
          .select('*, branch:branches(name)')
          .eq('tenant_id', tenantId)
          .inFilter('role', ['employee', 'manager', 'it']);

      // Fetch user limit
      final tenant = await _supabase
          .from('tenants')
          .select('subscription_tier')
          .eq('id', tenantId)
          .single();
      Map<String, int?>? limit;
      if (tenant['subscription_tier'] != null) {
        final plan = await _supabase
            .from('subscription_plans')
            .select('max_users')
            .eq('name', tenant['subscription_tier'])
            .eq('is_active', true)
            .maybeSingle();
        final max = plan?['max_users'] as int?;
        final data = response as List;
        limit = {'current': data.length, 'max': max};
      }

      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(response);
          _filteredEmployees = List<Map<String, dynamic>>.from(_employees);
          _userLimit = limit;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchBranches() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .single();
      final tenantId = profile['tenant_id'];

      if (tenantId == null) return;

      final response = await _supabase
          .from('branches')
          .select('id, name')
          .eq('tenant_id', tenantId);

      if (mounted) {
        setState(() => _branches = List<Map<String, dynamic>>.from(response));
      }
    } catch (_) {}
  }

  void _filterEmployees() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredEmployees = _employees.where((e) {
        final firstName = (e['first_name'] ?? '').toString().toLowerCase();
        final lastName = (e['last_name'] ?? '').toString().toLowerCase();
        final email = (e['email'] ?? '').toString().toLowerCase();
        final code = (e['employee_code'] ?? '').toString().toLowerCase();
        return firstName.contains(query) ||
            lastName.contains(query) ||
            email.contains(query) ||
            code.contains(query);
      }).toList();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exportCSV() {
    final rows = _filteredEmployees.map((e) {
      final name =
          '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim();
      final email = e['email'] ?? '';
      final role = e['role'] ?? '';
      final code = e['employee_code'] ?? '';
      final branch = e['branch'] is Map ? e['branch']['name'] ?? '' : '';
      return '$name,$email,$role,$code,$branch';
    }).toList();

    final csv =
        'Name,Email,Role,Code,Branch\n${rows.join('\n')}';
    ToastUtils.showCustomToast(context, 'CSV exported ($csv.length chars)');
  }

  Future<void> _handleProvision() async {
    if (_formFirstNameController.text.trim().isEmpty ||
        _formLastNameController.text.trim().isEmpty ||
        _formEmailController.text.trim().isEmpty ||
        _formPasswordController.text.trim().isEmpty ||
        _formEmployeeCodeController.text.trim().isEmpty ||
        _formBranchId == null) {
      ToastUtils.showCustomToast(context, 'All fields are required',
          isError: true);
      return;
    }

    setState(() => _isProvisioning = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .single();
      final tenantId = profile['tenant_id'];

      final response = await _supabase.auth.signUp(
        email: _formEmailController.text.trim(),
        password: _formPasswordController.text,
        data: {
          'first_name': _formFirstNameController.text.trim(),
          'last_name': _formLastNameController.text.trim(),
          'role': _formRole,
          'employee_code': _formEmployeeCodeController.text.trim(),
          'branch_id': _formBranchId,
          'tenant_id': tenantId,
        },
      );

      if (response.user != null) {
        ToastUtils.showSuccessToast(context, message: 'Employee provisioned successfully');
        Navigator.of(context).pop();
        _resetForm();
        _fetchEmployees();
      } else {
        ToastUtils.showErrorToast(context, message: 'Provision failed');
      }
    } catch (e) {
      ToastUtils.showErrorToast(
          context, message: 'Provision failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isProvisioning = false);
    }
  }

  Future<void> _handleRevoke(Map<String, dynamic> employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RevokeConfirmDialog(employee: employee),
    );

    if (confirmed != true) return;

    ToastUtils.showPromiseToast(
      context,
      message: 'Revoking access...',
      promise: _supabase
          .from('profiles')
          .delete()
          .eq('id', employee['id']),
      successMessage: 'Access Revoked Successfully',
      errorMessage: 'Error revoking access',
    );

    _fetchEmployees();
  }

  Future<void> _handleViewLogs(Map<String, dynamic> employee) async {
    setState(() {
      _selectedEmployee = employee;
      _fetchingLogs = true;
      _employeeLogs = [];
    });

    try {
      final response = await _supabase
          .from('audit_logs')
          .select('*')
          .eq('user_id', employee['id'])
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _employeeLogs = List<Map<String, dynamic>>.from(response);
          _fetchingLogs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _fetchingLogs = false);
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => _AuditLogDialog(
          employee: employee,
          logs: _employeeLogs,
          fetchingLogs: _fetchingLogs,
        ),
      );
    }
  }

  void _openProvisionModal() {
    _resetForm();
    showDialog(
      context: context,
      builder: (ctx) => _ProvisionDialog(
        branches: _branches,
        firstNameController: _formFirstNameController,
        lastNameController: _formLastNameController,
        emailController: _formEmailController,
        passwordController: _formPasswordController,
        employeeCodeController: _formEmployeeCodeController,
        selectedRole: _formRole,
        selectedBranchId: _formBranchId,
        isProvisioning: _isProvisioning,
        onRoleChanged: (v) => setState(() => _formRole = v),
        onBranchChanged: (v) => setState(() => _formBranchId = v),
        onProvision: _handleProvision,
      ),
    );
  }

  void _resetForm() {
    _formFirstNameController.clear();
    _formLastNameController.clear();
    _formEmailController.clear();
    _formPasswordController.clear();
    _formEmployeeCodeController.clear();
    _formRole = 'employee';
    _formBranchId = null;
  }

  bool get _limitReached =>
      _userLimit != null &&
      _userLimit!['max'] != null &&
      _userLimit!['current']! >= _userLimit!['max']!;

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
            _buildHeader(t),
            const SizedBox(height: 48),
            _buildUserLimitBar(),
            const SizedBox(height: 24),
            _buildBatchBar(),
            const SizedBox(height: 32),
            _buildBody(t),
          ],
        ),
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
            Text(
              t('employees_title').toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .displayLarge
                  ?.copyWith(fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Identity and access control.',
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search operatives...',
                  prefixIcon: const Icon(LucideIcons.search,
                      color: Colors.white24, size: 18),
                  filled: true,
                  fillColor: AppTheme.surfaceDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: _exportCSV,
              icon: const Icon(LucideIcons.download,
                  color: Colors.white38, size: 18),
              tooltip: 'Export CSV',
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _limitReached ? null : _openProvisionModal,
              icon: const Icon(LucideIcons.userPlus, size: 16),
              label: Text(
                _limitReached ? 'LIMIT REACHED' : 'Provision',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _limitReached ? Colors.grey : AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn().slideY(begin: -0.2);
  }

  Widget _buildUserLimitBar() {
    if (_userLimit == null) return const SizedBox.shrink();

    final current = _userLimit!['current'] ?? 0;
    final max = _userLimit!['max'];
    final ratio = max != null ? (current / max).clamp(0.0, 1.0) : 0.0;
    final isFull = max != null && current >= max;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.users, size: 16, color: Colors.white38),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                backgroundColor: Colors.white10,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$current${max != null ? ' / $max' : ''} operatives',
            style: TextStyle(
              color: isFull ? Colors.redAccent : Colors.white54,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }

  Widget _buildBatchBar() {
    if (_selectedIds.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_selectedIds.length} entities selected',
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            child: const Text(
              'Clear',
              style: TextStyle(
                color: Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }

  Widget _buildBody(String Function(String) t) {
    if (_isLoading) return _buildSkeleton();

    if (_filteredEmployees.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(80),
          child: Column(
            children: [
              const Icon(LucideIcons.users, size: 48, color: Colors.white10),
              const SizedBox(height: 16),
              Text(
                _employees.isEmpty ? 'No operatives found' : 'No results match your search',
                style: const TextStyle(color: Colors.white24),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EMPLOYEE ROSTER',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white54,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  color: Colors.white38,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
                columns: const [
                  DataColumn(label: Text('')),
                  DataColumn(label: Text('NAME')),
                  DataColumn(label: Text('EMAIL')),
                  DataColumn(label: Text('ROLE')),
                  DataColumn(label: Text('BRANCH')),
                  DataColumn(label: Text('EMP CODE')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: _filteredEmployees.map((emp) {
                  final name =
                      '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'
                          .trim();
                  final email = emp['email'] ?? '';
                  final role = (emp['role'] ?? '').toString().toUpperCase();
                  final branch = emp['branch'] is Map
                      ? emp['branch']['name'] ?? '—'
                      : '—';
                  final code = emp['employee_code'] ?? '—';
                  final status = emp['status'] ?? 'Active';
                  final isActive = status != 'Inactive';
                  final empId = emp['id'].toString();
                  final isSelected = _selectedIds.contains(empId);

                  return DataRow(
                    selected: isSelected,
                    onSelectChanged: (_) => _toggleSelect(empId),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 20,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelect(empId),
                            fillColor: WidgetStateProperty.resolveWith(
                              (_) => AppTheme.primaryColor,
                            ),
                            checkColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      DataCell(
                        Text(email,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white54)),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            role,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(branch,
                            style: const TextStyle(fontSize: 11)),
                      ),
                      DataCell(
                        Text(code,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: AppTheme.primaryColor)),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isActive
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isActive)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (isActive) const SizedBox(width: 4),
                              Text(
                                status.toString().toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color:
                                      isActive ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.activity,
                                  size: 14, color: Colors.white38),
                              onPressed: () => _handleViewLogs(emp),
                              tooltip: 'View Logs',
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.xCircle,
                                  size: 14, color: Colors.redAccent),
                              onPressed: () => _handleRevoke(emp),
                              tooltip: 'Revoke Access',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildSkeleton() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 180,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 24),
            ...List.generate(6, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 80,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).shimmer(
          color: Colors.white12,
          duration: 1200.ms,
        );
  }
}

class _ProvisionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> branches;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController employeeCodeController;
  final String selectedRole;
  final String? selectedBranchId;
  final bool isProvisioning;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String?> onBranchChanged;
  final VoidCallback onProvision;

  const _ProvisionDialog({
    required this.branches,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.passwordController,
    required this.employeeCodeController,
    required this.selectedRole,
    required this.selectedBranchId,
    required this.isProvisioning,
    required this.onRoleChanged,
    required this.onBranchChanged,
    required this.onProvision,
  });

  @override
  State<_ProvisionDialog> createState() => _ProvisionDialogState();
}

class _ProvisionDialogState extends State<_ProvisionDialog> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white10),
      ),
      title: Row(
        children: [
          const Icon(LucideIcons.userPlus, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 12),
          const Text(
            'PROVISION OPERATIVE',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: widget.firstNameController,
                        decoration: _inputDecoration('First Name'),
                        validator: (v) =>
                            v?.trim().isEmpty == true ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: widget.lastNameController,
                        decoration: _inputDecoration('Last Name'),
                        validator: (v) =>
                            v?.trim().isEmpty == true ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: widget.emailController,
                  decoration: _inputDecoration('Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v?.trim().isEmpty == true) return 'Required';
                    if (!v!.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: widget.passwordController,
                  decoration: _inputDecoration('Password'),
                  obscureText: true,
                  validator: (v) {
                    if (v?.trim().isEmpty == true) return 'Required';
                    if (v!.length < 6) return 'Min 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: widget.selectedRole,
                        decoration: _inputDecoration('Role'),
                        items: const [
                          DropdownMenuItem(
                              value: 'employee', child: Text('Employee')),
                          DropdownMenuItem(
                              value: 'manager', child: Text('Manager')),
                          DropdownMenuItem(value: 'it', child: Text('IT')),
                        ],
                        onChanged: (v) {
                          if (v != null) widget.onRoleChanged(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: widget.employeeCodeController,
                        decoration: _inputDecoration('Employee Code'),
                        validator: (v) =>
                            v?.trim().isEmpty == true ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: widget.selectedBranchId,
                  decoration: _inputDecoration('Branch'),
                  items: widget.branches.map((b) {
                    return DropdownMenuItem(
                      value: b['id'].toString(),
                      child: Text(b['name'] ?? ''),
                    );
                  }).toList(),
                  onChanged: (v) => widget.onBranchChanged(v),
                  validator: (v) => v == null ? 'Select a branch' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: widget.isProvisioning
              ? null
              : () {
                  if (_formKey.currentState?.validate() ?? false) {
                    widget.onProvision();
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: widget.isProvisioning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'PROVISION',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Colors.white38,
        fontWeight: FontWeight.w900,
        fontSize: 10,
        letterSpacing: 0.5,
      ),
      filled: true,
      fillColor: AppTheme.backgroundDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

class _RevokeConfirmDialog extends StatelessWidget {
  final Map<String, dynamic> employee;

  const _RevokeConfirmDialog({required this.employee});

  @override
  Widget build(BuildContext context) {
    final name =
        '${employee['first_name'] ?? ''} ${employee['last_name'] ?? ''}'.trim();
    return AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white10),
      ),
      title: Row(
        children: [
          Icon(LucideIcons.shieldAlert,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          const Text(
            'REVOKE ACCESS',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
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
              child: Column(
                children: [
                  const Icon(LucideIcons.shieldAlert,
                      color: Colors.redAccent, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'Are you sure you want to revoke access for $name?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This will permanently remove their access.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'ABORT',
            style: TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'PURGE',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditLogDialog extends StatelessWidget {
  final Map<String, dynamic> employee;
  final List<Map<String, dynamic>> logs;
  final bool fetchingLogs;

  const _AuditLogDialog({
    required this.employee,
    required this.logs,
    required this.fetchingLogs,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        '${employee['first_name'] ?? ''} ${employee['last_name'] ?? ''}'.trim();
    return AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white10),
      ),
      title: Row(
        children: [
          const Icon(LucideIcons.activity,
              color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ACTIVITY LOG — $name',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 400,
        child: fetchingLogs
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primaryColor),
                    SizedBox(height: 16),
                    Text(
                      'FETCHING TELEMETRY...',
                      style: TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              )
            : logs.isEmpty
                ? const Center(
                    child: Text(
                      'No activity logs found for this entity.',
                      style: TextStyle(color: Colors.white24),
                    ),
                  )
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final isCritical =
                          log['severity'] == 'CRITICAL';
                      final action = log['action'] ?? '';
                      final details = log['details'];
                      final createdAt = log['created_at'] ?? '';
                      String timeStr = '';
                      if (createdAt is String) {
                        try {
                          timeStr = DateTime.parse(createdAt)
                              .toLocal()
                              .toString()
                              .substring(0, 19);
                        } catch (_) {
                          timeStr = createdAt;
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 4,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isCritical
                                    ? AppTheme.primaryColor
                                    : Colors.green,
                                borderRadius:
                                    BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          action.toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        timeStr,
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 9,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    details != null
                                        ? details.toString()
                                        : '—',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'CLOSE',
            style: TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
