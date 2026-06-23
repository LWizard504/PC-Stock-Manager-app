import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/main_layout.dart';
import 'package:pc_dev_flutter/ui/screens/auth_assistant_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';
import 'package:pc_dev_flutter/services/offline_sync_manager.dart';
import 'package:pc_dev_flutter/ui/widgets/custom_window_bar.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  int _attempts = 0;
  DateTime? _lockoutUntil;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  void _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('remembered_email');
    if (savedEmail != null) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isRateLimited() {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isAfter(_lockoutUntil!)) {
      _lockoutUntil = null;
      _attempts = 0;
      return false;
    }
    return true;
  }

  void _recordFailedAttempt() {
    _attempts++;
    if (_attempts >= 5) {
      _lockoutUntil = DateTime.now().add(const Duration(minutes: 1));
    }
  }

  void _handleLogin() async {
    if (_isRateLimited()) {
      final remaining = _lockoutUntil!.difference(DateTime.now()).inSeconds + 1;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Demasiados intentos. Espera $remaining segundos.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor llena todos los campos')));
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 8));
      
      if (mounted && response.user != null) {
        _attempts = 0;
        _lockoutUntil = null;
        
        if (_rememberMe) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('remembered_email', email);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('remembered_email');
        }

        try {
          final profile = await Supabase.instance.client.from('profiles').select().eq('id', response.user!.id).single();
          await OfflineSyncManager.instance.cacheUserCredentials(email, password, profile);
        } catch (e) {
          debugPrint("Failed to fetch/cache profile during login: $e");
        }
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainLayout()),
          );
        }
      }
    } on AuthException catch (e) {
      _recordFailedAttempt();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      }
    } catch (e) {
      debugPrint("Login network error, attempting offline login: $e");
      
      final offlineProfile = await OfflineSyncManager.instance.authenticateOffline(email, password);
      if (offlineProfile != null) {
        _attempts = 0;
        _lockoutUntil = null;
        
        if (_rememberMe) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('remembered_email', email);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Iniciando sesión en Modo Sin Conexión'), backgroundColor: Colors.amber),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainLayout()),
          );
        }
      } else {
        _recordFailedAttempt();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error de conexión y no hay credenciales locales para este usuario'), backgroundColor: Colors.red),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A), // Near black background
      body: Column(
        children: [
          const CustomWindowBar(showLogo: true),
          Expanded(
            child: Stack(
              children: [
                // Top right language selector
                Positioned(
                  top: 24,
                  right: 24,
                  child: GestureDetector(
                    onTap: () {
                      final localeProvider = context.read<LocaleProvider>();
                      final current = localeProvider.locale.languageCode;
                      localeProvider.setLocale(Locale(current == 'en' ? 'es' : 'en'));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.languages, size: 16, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(
                            context.watch<LocaleProvider>().locale.languageCode == 'en' ? "English" : "Español",
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const Icon(LucideIcons.chevronDown, size: 16, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ),
                
                Center(
                  child: SingleChildScrollView(
                    child: Container(
                      width: 440,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212), // Dark grey surface
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top red border accent
                          Container(
                            height: 4,
                            width: 440,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                          ).animate().fadeIn().scaleX(),
                          
                          const SizedBox(height: 32),
                          
                          // Stakia Solutions Logo
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "STAKIA",
                                style: TextStyle(
                                  fontSize: 32, 
                                  fontWeight: FontWeight.w900, 
                                  color: Colors.white,
                                  letterSpacing: -1.5,
                                ),
                              ),
                              Text(
                                "SOLUTIONS",
                                style: TextStyle(
                                  fontSize: 32, 
                                  fontWeight: FontWeight.w900, 
                                  color: Colors.red.shade700,
                                  letterSpacing: -1.5,
                                ),
                              ),
                            ],
                          ).animate().fadeIn().slideY(begin: 0.1),
                          
                          const SizedBox(height: 8),
                          const Text(
                            "WELCOME BACK",
                            style: TextStyle(
                              color: Colors.white38, 
                              fontSize: 12, 
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ).animate().fadeIn(delay: 200.ms),
                          
                          const SizedBox(height: 48),
                          
                          // Email Field
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Email Address",
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _emailController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'name@company.com',
                                  hintStyle: const TextStyle(color: Colors.white24),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.03),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Colors.red),
                                  ),
                                ),
                              ),
                            ],
                          ).animate().fadeIn(delay: 300.ms),
                          
                          const SizedBox(height: 24),
                          
                          // Password Field
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Password",
                                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => const AuthAssistantScreen(initialMode: AuthMode.forgotPassword)),
                                      );
                                    },
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                                    child: const Text("Forgot password?", style: TextStyle(color: Colors.red, fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: '••••••••',
                                  hintStyle: const TextStyle(color: Colors.white24),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff, color: Colors.white24, size: 20),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.03),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Colors.red),
                                  ),
                                ),
                              ),
                            ],
                          ).animate().fadeIn(delay: 400.ms),
                          
                          const SizedBox(height: 24),
                          
                          // Remember me
                          Row(
                            children: [
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Checkbox(
                                  value: _rememberMe,
                                  onChanged: (val) => setState(() => _rememberMe = val ?? false),
                                  activeColor: Colors.red,
                                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text("Remember me", style: TextStyle(color: Colors.white60, fontSize: 14)),
                            ],
                          ).animate().fadeIn(delay: 500.ms),
                          
                          const SizedBox(height: 32),
                          
                          // Sign In Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: (_isLoading || _isRateLimited()) ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                              child: _isLoading 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text("Sign In", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ).animate().fadeIn(delay: 600.ms).scale(),
                          
                          const SizedBox(height: 48),
                          
                          // Footer
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Don't have an account? ", style: TextStyle(color: Colors.white38, fontSize: 14)),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const AuthAssistantScreen(initialMode: AuthMode.register)),
                                  );
                                },
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                                child: const Text("Request Access", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                            ],
                          ).animate().fadeIn(delay: 700.ms),
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
    );
  }
}
