import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  String _title = "Cargando...";
  Map<String, dynamic>? _myProfile;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    ToastUtils.showPromiseToast(
      context, 
      message: "Sincronizando personal...", 
      promise: _fetchUsers(), 
      successMessage: "Personal sincronizado", 
      errorMessage: "Error en sincronización"
    );
  }

  Future<void> _fetchUsers() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("No autenticado");

      _myProfile = await supabase
          .from('profiles')
          .select('role, tenant_id')
          .eq('id', user.id)
          .single();

      final role = _myProfile!['role'] as String;
      final tenantId = _myProfile!['tenant_id'];

      var query = supabase.from('profiles').select('*, branches(name)');

      if (role == 'superadmin' || role == 'global_it') {
        setState(() => _title = "Infraestructura Global");
      } else {
        setState(() => _title = "Gestión de Personal");
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
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final passwordController = TextEditingController(text: "StakiaNode2026!");
    String selectedRole = "employee";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white10)),
        title: const Text("Provisionar Nuevo Usuario", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Nombre Completo", labelStyle: TextStyle(color: Colors.white38)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: "Correo Electrónico", labelStyle: TextStyle(color: Colors.white38)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Contraseña Temporal", labelStyle: TextStyle(color: Colors.white38)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                dropdownColor: const Color(0xFF1A1A1A),
                decoration: const InputDecoration(labelText: "Nivel de Acceso", labelStyle: TextStyle(color: Colors.white38)),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: "admin", child: Text("Administrador")),
                  DropdownMenuItem(value: "manager", child: Text("Gerente")),
                  DropdownMenuItem(value: "employee", child: Text("Empleado")),
                  DropdownMenuItem(value: "it", child: Text("Soporte IT")),
                ],
                onChanged: (val) => selectedRole = val!,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _createUser(nameController.text, emailController.text, passwordController.text, selectedRole);
            },
            child: const Text("Crear Usuario"),
          ),
        ],
      ),
    );
  }

  Future<void> _createUser(String name, String email, String password, String role) async {
    ToastUtils.showPromiseToast(
      context, 
      message: "Provisionando usuario...", 
      promise: _executeCreation(name, email, password, role), 
      successMessage: "Usuario creado exitosamente", 
      errorMessage: "Error al crear usuario"
    );
  }

  Future<void> _executeCreation(String name, String email, String password, String role) async {
    try {
      final supabase = Supabase.instance.client;
      final myProfile = await supabase.from('profiles').select('tenant_id').eq('id', supabase.auth.currentUser!.id).single();
      final tenantId = myProfile['tenant_id'];

      // Note: This will create a user and link them to the tenant via the database trigger handle_new_user()
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': name,
          'tenant_id': tenantId,
          'role': role,
        },
      );
      
      _loadData();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _updateUserRole(String userId, String newRole) async {
    ToastUtils.showPromiseToast(
      context, 
      message: "Actualizando rol...", 
      promise: Supabase.instance.client.from('profiles').update({'role': newRole}).eq('id', userId), 
      successMessage: "Rol actualizado", 
      errorMessage: "Error al actualizar"
    );
    _loadData();
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
                    Text(_title, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text("Control de identidades y accesos del sistema.", style: TextStyle(color: Colors.white60, fontSize: 16)),
                  ],
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _loadData(),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text("Refrescar"),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceLight, foregroundColor: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _showAddUserDialog,
                      icon: const Icon(LucideIcons.userPlus, size: 16),
                      label: const Text("Añadir Usuario"),
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
                    const Text("Directorio de Usuarios", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    if (_isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(64), child: CircularProgressIndicator(color: Colors.red)))
                    else if (_users.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(64), child: Text("No se encontraron usuarios en este nodo", style: TextStyle(color: Colors.white24))))
                    else
                      _buildUsersTable(),
                  ],
                ),
              ),
            ).animate().fadeIn().slideY(),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
        columns: const [
          DataColumn(label: Text("Identidad")),
          DataColumn(label: Text("Rol")),
          DataColumn(label: Text("Sucursal")),
          DataColumn(label: Text("Contacto")),
          DataColumn(label: Text("Acciones")),
        ],
        rows: _users.map((user) {
          String name = user['full_name'] ?? '';
          if (name.isEmpty) {
            final first = user['first_name'] ?? '';
            final last = user['last_name'] ?? '';
            name = '$first $last'.trim();
          }
          if (name.isEmpty) name = 'Identidad Desconocida';

          final role = user['role']?.toString().toUpperCase() ?? 'USER';
          final phone = user['phone'] ?? 'N/A';
          final branch = user['branches'] != null ? user['branches']['name'] : 'Global';

          final avatarUrl = user['avatar_url'];

          return DataRow(cells: [
            DataCell(Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    image: avatarUrl != null ? DecorationImage(image: NetworkImage(avatarUrl), fit: BoxFit.cover) : null,
                  ),
                  child: avatarUrl == null 
                    ? Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
                    : null,
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(user['id'].toString().substring(0, 8), style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
                  ],
                ),
              ],
            )),
            DataCell(Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(role, style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
            )),
            DataCell(Text(branch, style: const TextStyle(color: Colors.white70))),
            DataCell(Text(phone, style: const TextStyle(color: Colors.white38))),
            DataCell(Row(
              children: [
                IconButton(icon: const Icon(LucideIcons.key, size: 16, color: Colors.white24), onPressed: () {}),
                IconButton(icon: const Icon(LucideIcons.edit, size: 16, color: Colors.white24), onPressed: () {}),
                IconButton(icon: Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent.withOpacity(0.5)), onPressed: () {}),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }
}
