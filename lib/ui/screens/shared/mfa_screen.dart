import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MfaSetupScreen extends StatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  State<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends State<MfaSetupScreen> {
  final _supabase = Supabase.instance.client;
  late final PageController _pageController;
  int _currentStep = 0;
  String _factorId = '';
  String _secret = '';
  String _qrUri = '';
  final _codeController = TextEditingController();
  bool _verifying = false;
  String _error = '';
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startEnroll();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startEnroll() async {
    try {
      final res = await _supabase.auth.mfa.enroll(factorType: FactorType.totp);
      _factorId = res.id;
      _secret = res.totp?.secret ?? '';
      _qrUri = res.totp?.uri ?? res.totp?.qrCode ?? '';
      if (mounted) {
        setState(() => _currentStep = 1);
        _pageController.animateToPage(1, duration: 300.ms, curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al iniciar enrolamiento: $e');
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;
    setState(() { _verifying = true; _error = ''; });
    try {
      final challengeRes = await _supabase.auth.mfa.challenge(factorId: _factorId);
      await _supabase.auth.mfa.verify(
        factorId: _factorId,
        challengeId: challengeRes.id,
        code: code,
      );
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase.from('profiles').update({'mfa_enabled': true}).eq('id', user.id);
      }
      if (mounted) {
        setState(() => _currentStep = 2);
        _pageController.animateToPage(2, duration: 300.ms, curve: Curves.easeOut);
        Future.delayed(2.seconds, () {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Verificación falló'; _verifying = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          width: 460,
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildLoadingStep(),
                _buildQrStep(),
                _buildDoneStep(),
              ],
            ),
          ),
        ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
      ),
    );
  }

  Widget _buildLoadingStep() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.red, strokeWidth: 3)),
          const SizedBox(height: 24),
          const Text("Initializing Shield Protocol...",
            style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildQrStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.shield, color: Colors.red, size: 40),
          const SizedBox(height: 16),
          const Text("Enable 2FA", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          const Text("Scan with your authenticator app",
            style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 24),
          if (_qrUri.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: QrImageView(data: _qrUri, version: QrVersions.auto, size: 200),
            ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("MANUAL SETUP KEY",
                      style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 1.5)),
                    GestureDetector(
                      onTap: () {
                        _copied = true;
                        Future.delayed(2.seconds, () { if (mounted) setState(() => _copied = false); });
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_copied ? LucideIcons.check : LucideIcons.copy,
                            color: _copied ? Colors.green : Colors.red, size: 12),
                          const SizedBox(width: 4),
                          Text(_copied ? "Copied" : "Copy",
                            style: TextStyle(
                              color: _copied ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: SelectableText(_secret,
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _codeController,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 28, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.1), fontFamily: 'monospace', fontSize: 28, letterSpacing: 8),
              filled: true,
              fillColor: Colors.white.withOpacity(0.03),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red),
              ),
            ),
            onChanged: (v) {
              if (v.length == 6) setState(() {});
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_codeController.text.length != 6 || _verifying) ? null : _verify,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _verifying
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.key, size: 16),
                      SizedBox(width: 8),
                      Text("VERIFY & ACTIVATE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child: const Icon(LucideIcons.check, color: Colors.green, size: 32),
          ),
          const SizedBox(height: 24),
          const Text("Shield Activated",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 8),
          const Text("Two-factor authentication is now enabled.",
            style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack);
  }
}

class MfaVerifyDialog extends StatefulWidget {
  const MfaVerifyDialog({super.key});

  @override
  State<MfaVerifyDialog> createState() => _MfaVerifyDialogState();
}

class _MfaVerifyDialogState extends State<MfaVerifyDialog> {
  final _supabase = Supabase.instance.client;
  final _codeController = TextEditingController();
  bool _verifying = false;
  String _error = '';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;
    setState(() { _verifying = true; _error = ''; });
    try {
      final factorsRes = await _supabase.auth.mfa.listFactors();
      if (factorsRes.totp.isEmpty) {
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final factor = factorsRes.totp.first;
      final challengeRes = await _supabase.auth.mfa.challenge(factorId: factor.id);
      await _supabase.auth.mfa.verify(
        factorId: factor.id,
        challengeId: challengeRes.id,
        code: code,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _error = 'Error de verificación'; _verifying = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF121212),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(LucideIcons.shield, color: Colors.red, size: 20),
          SizedBox(width: 12),
          Text("Two-Factor Auth", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Enter the 6-digit code from your authenticator app",
            style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 28, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.1), fontFamily: 'monospace', fontSize: 28, letterSpacing: 8),
              filled: true,
              fillColor: Colors.white.withOpacity(0.03),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red),
              ),
            ),
            onChanged: (v) {
              if (v.length == 6) setState(() {});
            },
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton(
          onPressed: (_codeController.text.length != 6 || _verifying) ? null : _verify,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: _verifying
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text("Verify", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
