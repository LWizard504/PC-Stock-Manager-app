import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pc_dev_flutter/ui/screens/launcher_screen.dart';
import 'package:pc_dev_flutter/services/signaling_service.dart';
import 'package:pc_dev_flutter/ui/screens/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _showTouchNumpad = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _loadPreferences();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showTouchNumpad = prefs.getBool('show_touch_numpad') ?? true;
      });
    }
  }

  void _savePreference(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_touch_numpad', val);
    if (mounted) {
      setState(() {
        _showTouchNumpad = val;
      });
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase.from('profiles').select('*').eq('id', user.id).single();
      if (mounted) {
        setState(() {
          _profile = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    SignalingService().disconnect();
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _showEditProfile() {
    if (_profile == null) return;
    final firstController = TextEditingController(text: _profile!['first_name']);
    final lastController = TextEditingController(text: _profile!['last_name']);
    final phoneController = TextEditingController(text: _profile!['phone']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Editar Perfil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: firstController, decoration: const InputDecoration(labelText: "Nombre"), style: const TextStyle(color: Colors.white)),
            TextField(controller: lastController, decoration: const InputDecoration(labelText: "Apellido"), style: const TextStyle(color: Colors.white)),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: "Teléfono"), style: const TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateProfile(firstController.text, lastController.text, phoneController.text);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateProfile(String first, String last, String phone) async {
    ToastUtils.showPromiseToast(
      context, 
      message: "Actualizando perfil...", 
      promise: _supabase.from('profiles').update({
        'first_name': first,
        'last_name': last,
        'phone': phone,
        'full_name': '$first $last'.trim(),
      }).eq('id', _supabase.auth.currentUser!.id), 
      successMessage: "Perfil actualizado", 
      errorMessage: "Error al actualizar"
    );
    _fetchProfile();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Colors.red));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Configuración de Sistema", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text("Gestione su identidad y preferencias de nodo.", style: TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 48),
            
            _buildProfileCard(),
            const SizedBox(height: 32),
            
            _buildSection("Seguridad y Acceso", [
              _buildTile(LucideIcons.lock, "Cambiar Contraseña", "Actualizar llaves de acceso", () async {
                final email = _supabase.auth.currentUser?.email;
                if (email != null) {
                  ToastUtils.showPromiseToast(
                    context, 
                    message: "Enviando enlace...", 
                    promise: _supabase.auth.resetPasswordForEmail(email), 
                    successMessage: "Correo enviado", 
                    errorMessage: "Error al enviar"
                  );
                }
              }),
              _buildTile(LucideIcons.shieldCheck, "Doble Factor", "Seguridad biométrica o código", () {}),
            ]),
            
            _buildSection("Preferencias", [
              _buildTile(LucideIcons.moon, "Tema Visual", "Alternar entre modo industrial y luz", () {}),
              _buildTile(LucideIcons.languages, "Idioma", "Español (Latinoamérica)", () {}),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                leading: const Icon(LucideIcons.keyboard, color: Colors.white60, size: 20),
                title: const Text("Teclado Táctil POS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text("Mostrar pad numérico táctil en el punto de venta", style: TextStyle(color: Colors.white24, fontSize: 12)),
                trailing: Switch(
                  value: _showTouchNumpad,
                  activeColor: Colors.red,
                  onChanged: (val) {
                    _savePreference(val);
                  },
                ),
              ),
            ]),
            
             _buildSection("Sistema y Actualizaciones", [
              _buildTile(LucideIcons.download, "Buscar Actualizaciones", "Verificar optimizaciones y reiniciar launcher", () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LauncherScreen()),
                  (route) => false,
                );
              }),
            ]),

            _buildSection("Sesión", [
              _buildTile(LucideIcons.logOut, "Cerrar Sesión", "Finalizar acceso en este dispositivo", _logout, isDestructive: true),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    String name = _profile?['full_name'] ?? 'Usuario';
    String role = _profile?['role']?.toString().toUpperCase() ?? 'N/A';

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.red.withOpacity(0.1),
            child: Text(name[0], style: const TextStyle(color: Colors.red, fontSize: 32, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(role, style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _showEditProfile,
            icon: const Icon(LucideIcons.edit2, size: 16),
            label: const Text("Editar Perfil"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
          ),
        ],
      ),
    ).animate().fadeIn().slideX();
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 16),
          child: Text(title, style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildTile(IconData icon, String title, String subtitle, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Icon(icon, color: isDestructive ? Colors.redAccent : Colors.white60, size: 20),
      title: Text(title, style: TextStyle(color: isDestructive ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white24, fontSize: 12)),
      trailing: const Icon(LucideIcons.chevronRight, color: Colors.white10, size: 16),
      onTap: onTap,
    );
  }
}
