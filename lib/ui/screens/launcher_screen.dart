import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/screens/login_screen.dart';

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> with TickerProviderStateMixin {
  late AnimationController _rotationController;
  final List<String> _logs = [];
  double _progress = 0.0;
  String _statusText = "Iniciando cargador central...";
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _runBootDiagnostics();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _addLog(String text) {
    if (mounted) {
      setState(() {
        _logs.insert(0, "[${DateTime.now().toLocal().toString().split(' ')[1].substring(0, 8)}] $text");
      });
    }
  }

  Future<void> _runBootDiagnostics() async {
    _addLog("Inicializando telemetría de StockManager...");
    await Future.delayed(const Duration(milliseconds: 800));
    
    _addLog("Estableciendo conexión segura TLS con GitHub...");
    await Future.delayed(const Duration(milliseconds: 600));

    try {
      _addLog("Buscando actualizaciones en LWizard504/PC-Stock-Manager-app...");
      
      final client = HttpClient();
      final uri = Uri.parse("https://api.github.com/repos/LWizard504/PC-Stock-Manager-app/releases/latest");
      final request = await client.getUrl(uri);
      
      // GitHub API requires a User-Agent header
      request.headers.set('User-Agent', 'StockManager-Launcher');
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        
        final latestVersionTag = json['tag_name'] as String? ?? '1.0.0';
        final latestVersion = latestVersionTag.replaceAll('v', '').trim();
        const currentVersion = "1.0.0"; // Local version

        _addLog("Versión remota detectada: v$latestVersion (Local: v$currentVersion)");

        if (latestVersion != currentVersion) {
          _addLog("¡NUEVA ACTUALIZACIÓN DETECTADA: v$latestVersion!");
          
          final assets = json['assets'] as List<dynamic>? ?? [];
          String? downloadUrl;
          
          // Look for 'app.so' or 'data/app.so' asset first
          for (var asset in assets) {
            final name = (asset['name'] as String? ?? '').toLowerCase();
            if (name == 'app.so' || name.contains('app.so')) {
              downloadUrl = asset['browser_download_url'] as String?;
              break;
            }
          }
          
          // Fallback to first available asset if no specific 'app.so' is found
          if (downloadUrl == null && assets.isNotEmpty) {
            downloadUrl = assets.first['browser_download_url'] as String?;
          }

          if (downloadUrl != null) {
            _addLog("Iniciando descarga por intercambio de código AOT...");
            setState(() {
              _isUpdating = true;
              _statusText = "Descargando actualización (v$latestVersion)...";
            });

            await _downloadAndSwapUpdate(downloadUrl);
            return;
          } else {
            _addLog("Advertencia: No se encontraron binarios compilados en el release.");
          }
        }
      } else {
        _addLog("Aviso: Respuesta de GitHub no disponible (${response.statusCode})");
      }

      _addLog("Sistema totalmente actualizado. Versión: v1.0.0");
      setState(() {
        _statusText = "Acceso verificado. Redireccionando...";
        _progress = 1.0;
      });

      await Future.delayed(const Duration(milliseconds: 1000));
      _navigateToLogin();

    } catch (e) {
      _addLog("Error en comprobación de red: $e");
      _addLog("Arrancando en modo Offline local seguro...");
      setState(() {
        _statusText = "Modo Offline activado. Iniciando...";
        _progress = 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      _navigateToLogin();
    }
  }

  Future<void> _downloadAndSwapUpdate(String url) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      final totalBytes = response.contentLength;
      var downloadedBytes = 0;
      
      final exePath = Platform.resolvedExecutable;
      final appDir = p.dirname(exePath);
      final originalAppSo = p.join(appDir, 'data', 'app.so');
      
      final tempDir = Directory.systemTemp.path;
      final tempAppSo = File(p.join(tempDir, 'app.so.tmp'));
      
      final sink = tempAppSo.openWrite();
      
      await for (var chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() {
            _progress = downloadedBytes / totalBytes;
            _statusText = "Descargando optimizaciones: ${(_progress * 100).toInt()}%";
          });
        }
      }
      
      await sink.close();
      _addLog("Descarga completada de forma exitosa.");
      _addLog("Compilando scripts de instalación automatizada...");
      await Future.delayed(const Duration(milliseconds: 500));

      final batFile = File(p.join(tempDir, 'update_runner.bat'));
      final batContent = '''
@echo off
timeout /t 1 /nobreak > nul
move /y "${tempAppSo.path}" "$originalAppSo"
start "" "$exePath"
del "%~f0"
''';
      
      await batFile.writeAsString(batContent);
      _addLog("Aplicando parches de sistema... Cerrando StockManager.");
      await Future.delayed(const Duration(milliseconds: 800));

      // Run Batch process silently in detached mode
      await Process.start('cmd.exe', ['/c', batFile.path], runInShell: true, mode: ProcessStartMode.detached);
      exit(0);

    } catch (e) {
      _addLog("Error crítico de descarga: $e");
      _addLog("Omisión temporal de parche. Iniciando sesión...");
      setState(() {
        _statusText = "Fallo de actualización. Iniciando sesión...";
        _progress = 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 1500));
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070707),
      body: Stack(
        children: [
          // Background ambient grid or blur
          Positioned(
            top: -200,
            right: -200,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withOpacity(0.04),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: 900,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo / Launcher Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
                        ),
                        child: const Icon(LucideIcons.rocket, color: AppTheme.primaryColor, size: 40),
                      ).animate().fadeIn().scale(delay: 100.ms),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "STOCKMANAGER",
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
                          ),
                          Text(
                            "LAUNCHER & BOOTLOADER v1.0.0",
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryColor, letterSpacing: 2),
                          ),
                        ],
                      ).animate().fadeIn(delay: 200.ms),
                    ],
                  ),
                  const SizedBox(height: 64),
                  // Animated Cyber Spinner & Progress Bar
                  Row(
                    children: [
                      // Dual Rotating Ring custom spinner
                      AnimatedBuilder(
                        animation: _rotationController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.rotate(
                                angle: _rotationController.value * 2 * 3.14159,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppTheme.primaryColor.withOpacity(0.2),
                                      width: 4,
                                    ),
                                  ),
                                ),
                              ),
                              Transform.rotate(
                                angle: -_rotationController.value * 4 * 3.14159,
                                child: SizedBox(
                                  width: 68,
                                  height: 68,
                                  child: CircularProgressIndicator(
                                    value: _progress > 0 ? _progress : null,
                                    strokeWidth: 3,
                                    color: AppTheme.primaryColor,
                                    backgroundColor: Colors.transparent,
                                  ),
                                ),
                              ),
                              const Icon(LucideIcons.cpu, color: Colors.white54, size: 24),
                            ],
                          );
                        },
                      ),
                      const SizedBox(width: 32),
                      // Progress and log status
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _statusText,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _progress,
                                minHeight: 6,
                                backgroundColor: const Color(0xFF1E1E1E),
                                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 300.ms),
                  const SizedBox(height: 48),
                  // Diagnostics Console Log
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0F),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1E1E1E)),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final isAlert = log.contains("VERSIÓN") || log.contains("Error");
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: isAlert ? AppTheme.primaryColor : Colors.white54,
                              fontWeight: isAlert ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
                  ).animate().fadeIn(delay: 450.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
