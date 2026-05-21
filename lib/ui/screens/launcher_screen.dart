import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/screens/login_screen.dart';
import 'package:pc_dev_flutter/services/config.dart';

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

  bool _isVersionSuperior(String latest, String current) {
    try {
      List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      int maxLen = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
      for (int i = 0; i < maxLen; i++) {
        int l = i < latestParts.length ? latestParts[i] : 0;
        int c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _runBootDiagnostics() async {
    _addLog("Inicializando telemetría de StockManager...");
    await Future.delayed(const Duration(milliseconds: 800));
    
    _addLog("Estableciendo conexión segura TLS con GitHub...");
    await Future.delayed(const Duration(milliseconds: 600));

    try {
      _addLog("Buscando actualizaciones en LWizard504/PC-Stock-Manager-app (main)...");
      
      final client = HttpClient();
      final uri = Uri.parse("https://raw.githubusercontent.com/LWizard504/PC-Stock-Manager-app/main/lib/services/config.dart?t=${DateTime.now().millisecondsSinceEpoch}");
      final request = await client.getUrl(uri);
      
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        
        // Extraer la versión de config.dart remota con Regex
        final regExp = RegExp(r"static\s+const\s+String\s+appVersion\s*=\s*['\"']([^'\"']+)['\"']");
        final match = regExp.firstMatch(responseBody);
        
        if (match != null) {
          final latestVersion = match.group(1)!.trim();
          const currentVersion = AppConfig.appVersion; // Local version

          _addLog("Versión remota detectada: v$latestVersion (Local: v$currentVersion)");

          if (_isVersionSuperior(latestVersion, currentVersion)) {
            _addLog("¡NUEVA ACTUALIZACIÓN DETECTADA: v$latestVersion!");
            _addLog("Iniciando auto-compilación desde código fuente...");
            setState(() {
              _isUpdating = true;
              _statusText = "Compilando actualizaciones desde código fuente...";
            });

            await _compileAndInstallUpdate();
            return;
          }
        } else {
          _addLog("Error: No se pudo extraer la versión del archivo de configuración remoto.");
        }
      } else {
        _addLog("Aviso: Repositorio no accesible en este momento (HTTP ${response.statusCode})");
      }

      _addLog("Sistema totalmente actualizado. Versión: v${AppConfig.appVersion}");
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

  Future<void> _compileAndInstallUpdate() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final appDir = p.dirname(exePath);
      final updateDir = p.join(appDir, 'update');
      final buildPath = p.join(updateDir, 'stockmanager_compiler');
      final buildDir = Directory(buildPath);

      _addLog("Preparando entorno de compilación en local...");
      await Future.delayed(const Duration(milliseconds: 500));

      if (!Directory(updateDir).existsSync()) {
        Directory(updateDir).createSync(recursive: true);
      }

      if (!buildDir.existsSync()) {
        buildDir.createSync(recursive: true);
        _addLog("Clonando repositorio principal desde GitHub...");
        final cloneProcess = await Process.start(
          'git',
          ['clone', 'https://github.com/LWizard504/PC-Stock-Manager-app', '.'],
          workingDirectory: buildPath,
        );

        await _pipeProcessOutput(cloneProcess, "Git Clone");
      } else {
        _addLog("Repositorio detectado. Sincronizando últimas ramas...");
        final pullProcess = await Process.start(
          'git',
          ['pull'],
          workingDirectory: buildPath,
        );

        await _pipeProcessOutput(pullProcess, "Git Pull");
      }

      _addLog("Descargando dependencias de Flutter (flutter pub get)...");
      final pubProcess = await Process.start(
        'flutter',
        ['pub', 'get'],
        workingDirectory: buildPath,
        runInShell: true,
      );
      await _pipeProcessOutput(pubProcess, "Flutter Pub");

      _addLog("Compilando binarios optimizados (flutter build windows)...");
      setState(() {
        _statusText = "Compilando aplicación (AOT)...";
        _progress = 0.5;
      });

      final buildProcess = await Process.start(
        'flutter',
        ['build', 'windows', '--release'],
        workingDirectory: buildPath,
        runInShell: true,
      );
      await _pipeProcessOutput(buildProcess, "Flutter Build");

      final newAppSoPath = p.join(buildPath, 'build', 'windows', 'x64', 'runner', 'Release', 'data', 'app.so');
      final newAppSo = File(newAppSoPath);

      if (newAppSo.existsSync()) {
        _addLog("Compilación exitosa. Generando intercambio de binarios...");
        setState(() {
          _statusText = "Instalando actualización...";
          _progress = 0.9;
        });
        await Future.delayed(const Duration(milliseconds: 500));

        final originalAppSo = p.join(appDir, 'data', 'app.so');

        final batFile = File(p.join(updateDir, 'update_runner.bat'));
        final batContent = '''
@echo off
timeout /t 1 /nobreak > nul
move /y "${newAppSo.path}" "$originalAppSo"
rd /s /q "${buildDir.path}"
start "" "$exePath"
del "%~f0"
''';
        
        await batFile.writeAsString(batContent);

        final vbsFile = File(p.join(updateDir, 'silent_runner.vbs'));
        final vbsContent = 'CreateObject("WScript.Shell").Run "cmd.exe /c " & Chr(34) & "${batFile.path}" & Chr(34), 0, False';
        await vbsFile.writeAsString(vbsContent);

        _addLog("Aplicando parche y reiniciando StockManager...");
        await Future.delayed(const Duration(milliseconds: 800));

        // Start VBScript silently in background without flashing any CMD prompt
        await Process.start('wscript.exe', [vbsFile.path], runInShell: false, mode: ProcessStartMode.detached);
        exit(0);
      } else {
        throw Exception("No se generó el binario app.so. Revisa la consola de build.");
      }

    } catch (e) {
      _addLog("Error crítico de compilación: $e");
      _addLog("Omisión temporal de parche. Iniciando sesión...");
      setState(() {
        _statusText = "Fallo de actualización. Iniciando sesión...";
        _progress = 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 2500));
      _navigateToLogin();
    }
  }

  Future<void> _pipeProcessOutput(Process process, String prefix) async {
    process.stdout.transform(utf8.decoder).listen((data) {
      final lines = data.split('\n');
      for (var line in lines) {
        if (line.trim().isNotEmpty) {
          _addLog("$prefix: ${line.trim()}");
        }
      }
    });

    process.stderr.transform(utf8.decoder).listen((data) {
      final lines = data.split('\n');
      for (var line in lines) {
        if (line.trim().isNotEmpty) {
          _addLog("$prefix [ERROR]: ${line.trim()}");
        }
      }
    });

    final exitCode = await process.exitCode;
    _addLog("$prefix finalizado con código de salida: $exitCode");
    if (exitCode != 0) {
      throw Exception("$prefix falló con código $exitCode");
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
                            "LAUNCHER & BOOTLOADER v${AppConfig.appVersion}",
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
