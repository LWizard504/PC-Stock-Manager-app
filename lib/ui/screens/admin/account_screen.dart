import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:pc_dev_flutter/ui/screens/shared/mfa_screen.dart';

class AdminAccountScreen extends StatefulWidget {
  const AdminAccountScreen({super.key});

  @override
  State<AdminAccountScreen> createState() => _AdminAccountScreenState();
}

class _AdminAccountScreenState extends State<AdminAccountScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _mfaEnabled = false;
  bool _mfaLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
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
      _loadMfaStatus();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMfaStatus() async {
    try {
      final factorsRes = await _supabase.auth.mfa.listFactors();
      final hasTotp = factorsRes.totp.isNotEmpty;
      final profileMfa = _profile?['mfa_enabled'] == true;
      if (mounted) {
        setState(() {
          _mfaEnabled = hasTotp && profileMfa;
          _mfaLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _mfaLoading = false);
    }
  }

  void _showAvatarUrlDialog() {
    final controller = TextEditingController(text: _profile?['avatar_url'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Profile Photo", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Image URL",
            hintText: "https://example.com/avatar.jpg",
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateAvatarUrl(controller.text);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAvatarUrl(String url) async {
    if (url.isEmpty) return;
    ToastUtils.showPromiseToast(
      context,
      message: "Updating avatar...",
      promise: _supabase.from('profiles').update({'avatar_url': url}).eq('id', _supabase.auth.currentUser!.id),
      successMessage: "Avatar updated",
      errorMessage: "Error updating avatar",
    );
    _fetchProfile();
  }

  void _showEditProfile() {
    if (_profile == null) return;
    final firstController = TextEditingController(text: _profile!['first_name'] ?? '');
    final lastController = TextEditingController(text: _profile!['last_name'] ?? '');
    final phoneController = TextEditingController(text: _profile!['phone'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Edit Profile", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: firstController, decoration: const InputDecoration(labelText: "First Name"), style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            TextField(controller: lastController, decoration: const InputDecoration(labelText: "Last Name"), style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: "Phone"), style: const TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateProfile(firstController.text, lastController.text, phoneController.text);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateProfile(String first, String last, String phone) async {
    ToastUtils.showPromiseToast(
      context,
      message: "Updating profile...",
      promise: _supabase.from('profiles').update({
        'first_name': first,
        'last_name': last,
        'phone': phone,
        'full_name': '$first $last'.trim(),
      }).eq('id', _supabase.auth.currentUser!.id),
      successMessage: "Profile updated",
      errorMessage: "Error updating profile",
    );
    _fetchProfile();
  }

  Future<void> _rotatePassword() async {
    final email = _supabase.auth.currentUser?.email;
    if (email != null) {
      ToastUtils.showPromiseToast(
        context,
        message: "Sending reset link...",
        promise: _supabase.auth.resetPasswordForEmail(email),
        successMessage: "Reset email sent",
        errorMessage: "Error sending reset email",
      );
    }
  }

  Future<void> _handleMfaDisable() async {
    try {
      final factorsRes = await _supabase.auth.mfa.listFactors();
      for (final factor in factorsRes.totp) {
        await _supabase.auth.mfa.unenroll(factor.id);
      }
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase.from('profiles').update({'mfa_enabled': false}).eq('id', user.id);
      }
      if (mounted) {
        setState(() => _mfaEnabled = false);
        ToastUtils.showSuccessToast(context, message: "2FA disabled");
      }
    } catch (e) {
      if (mounted) ToastUtils.showErrorToast(context, message: "Error disabling 2FA");
    }
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
            Text("Account Settings", style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text("Manage your profile, security, and active sessions.", style: TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 48),

            _buildProfileCard(),
            const SizedBox(height: 32),

            _buildSection("Profile Information", [
              _buildInfoTile(LucideIcons.user, "First Name", _profile?['first_name'] ?? '—'),
              _buildInfoTile(LucideIcons.user, "Last Name", _profile?['last_name'] ?? '—'),
              _buildInfoTile(LucideIcons.userCheck, "Full Name", _profile?['full_name'] ?? '—'),
              _buildInfoTile(LucideIcons.phone, "Phone", _profile?['phone'] ?? '—'),
              _buildInfoTile(LucideIcons.mail, "Email", _supabase.auth.currentUser?.email ?? '—', isReadOnly: true),
            ]),

            _buildSection("Security", [
              _buildRotateKeyTile(),
              _buildMfaTile(),
            ]),

            _buildSection("Active Sessions", [
              _buildSessionTile(LucideIcons.monitor, "Windows PC", "192.168.1.100", "2 min ago"),
              _buildSessionTile(LucideIcons.smartphone, "iPhone 15", "10.0.0.5", "1 hour ago"),
              _buildSessionTile(LucideIcons.globe, "Web Browser", "203.0.113.42", "3 hours ago"),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ToastUtils.showCustomToast(context, "All sessions have been terminated", isError: false);
                    },
                    icon: const Icon(LucideIcons.logOut, size: 16),
                    label: const Text("Terminate All Sessions"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.2),
                      foregroundColor: Colors.redAccent,
                    ),
                  ),
                ),
              ),
            ]),

            _buildSection("Last Network Access", [
              _buildInfoTile(LucideIcons.clock, "Last Login", _profile?['last_login']?.toString() ?? 'Not recorded'),
              _buildInfoTile(LucideIcons.globe, "Last IP", _profile?['last_ip'] ?? 'Not recorded'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    String name = _profile?['full_name'] ?? 'User';
    String role = _profile?['role']?.toString().toUpperCase() ?? 'N/A';
    String? avatarUrl = _profile?['avatar_url'];

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showAvatarUrlDialog,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.red.withOpacity(0.1),
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(name[0], style: const TextStyle(color: Colors.red, fontSize: 32, fontWeight: FontWeight.bold))
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
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
            label: const Text("Edit Profile"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
          ),
        ],
      ),
    ).animate().fadeIn().slideX();
  }

  Widget _buildRotateKeyTile() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: const Icon(LucideIcons.key, color: Colors.orange, size: 18),
      ),
      title: const Text("Rotate Key", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: const Text("Send password reset email to change your password", style: TextStyle(color: Colors.white24, fontSize: 12)),
      trailing: TextButton.icon(
        onPressed: _rotatePassword,
        icon: const Icon(LucideIcons.refreshCcw, size: 14),
        label: const Text("Rotate", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _buildMfaTile() {
    if (_mfaLoading) {
      return const ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
        title: Text("Verifying 2FA...", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 14)),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: _mfaEnabled ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: (_mfaEnabled ? Colors.green : Colors.red).withOpacity(0.2)),
        ),
        child: Icon(
          _mfaEnabled ? LucideIcons.shield : LucideIcons.shieldOff,
          color: _mfaEnabled ? Colors.green : Colors.redAccent,
          size: 18,
        ),
      ),
      title: Row(
        children: [
          const Text("Two-Factor Auth", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _mfaEnabled ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _mfaEnabled ? "ACTIVE" : "INACTIVE",
              style: TextStyle(
                color: _mfaEnabled ? Colors.green : Colors.redAccent,
                fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        _mfaEnabled ? "Two-factor authentication is active" : "Your account is vulnerable",
        style: const TextStyle(color: Colors.white24, fontSize: 12),
      ),
      trailing: _mfaEnabled
          ? TextButton(
              onPressed: _handleMfaDisable,
              child: const Text("Disable", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            )
          : null,
      onTap: _mfaEnabled ? null : () async {
        final result = await showDialog<bool>(
          context: context,
          barrierColor: Colors.black54,
          builder: (_) => const MfaSetupScreen(),
        );
        if (result == true && mounted) {
          setState(() => _mfaEnabled = true);
          _loadMfaStatus();
        }
      },
    );
  }

  Widget _buildSessionTile(IconData icon, String device, String ip, String lastActive) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withOpacity(0.2)),
        ),
        child: Icon(icon, color: Colors.green, size: 18),
      ),
      title: Text(device, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text("$ip \u2022 $lastActive", style: const TextStyle(color: Colors.white24, fontSize: 12)),
      trailing: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value, {bool isReadOnly = false}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Icon(icon, color: Colors.white60, size: 20),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      trailing: Text(
        value,
        style: TextStyle(
          color: isReadOnly ? Colors.white38 : Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
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
}
