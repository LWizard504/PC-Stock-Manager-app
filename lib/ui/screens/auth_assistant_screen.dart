import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

enum AuthMode { register, forgotPassword }

class AuthAssistantScreen extends StatefulWidget {
  final AuthMode initialMode;
  const AuthAssistantScreen({super.key, this.initialMode = AuthMode.register});

  @override
  State<AuthAssistantScreen> createState() => _AuthAssistantScreenState();
}

class Message {
  final String text;
  final bool isAi;
  final DateTime time;

  Message(this.text, {this.isAi = true}) : time = DateTime.now();
}

class _AuthAssistantScreenState extends State<AuthAssistantScreen> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  late AuthMode _currentMode;
  bool _isTyping = false;
  int _step = 0;
  
  // Data
  String? _email;
  String? _licenseKey;
  String? _password;
  String? _tenantId;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    _startConversation();
  }

  void _startConversation() {
    if (_currentMode == AuthMode.register) {
      _addAiMessage("Hola, soy el Agente de Activación de Stakia. Veo que intentas acceder a la red industrial.");
      _addAiMessage("Para comenzar el registro, ¿podrías proporcionarme tu dirección de correo electrónico corporativo?");
    } else {
      _addAiMessage("Hola. Has solicitado restablecer tu acceso. Por seguridad, necesito verificar tu identidad en la red.");
      _addAiMessage("Por favor, ingresa el correo electrónico asociado a tu cuenta.");
    }
  }

  void _addAiMessage(String text) async {
    setState(() => _isTyping = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add(Message(text, isAi: true));
      });
      _scrollToBottom();
    }
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(Message(text, isAi: false));
    });
    _scrollToBottom();
    _processInput(text);
  }

  void _processInput(String input) async {
    if (_currentMode == AuthMode.register) {
      _processRegister(input);
    } else {
      _processForgotPassword(input);
    }
  }

  // --- LOGICA DE REGISTRO ---
  void _processRegister(String input) async {
    switch (_step) {
      case 0:
        _email = input.toLowerCase();
        if (!_email!.contains('@')) {
          _addAiMessage("Ese correo no parece válido. Por favor, asegúrate de escribirlo correctamente.");
          return;
        }
        _step = 1;
        _addAiMessage("Entendido. Ahora, por favor ingresa tu código de licencia (STK-XXXX-XXXX-XXXX).");
        break;
      case 1:
        _licenseKey = input.toUpperCase();
        _verifyLicenseAndRegister();
        break;
      case 2:
        _password = input;
        if (_password!.length < 6) {
          _addAiMessage("La contraseña debe tener al menos 6 caracteres por seguridad.");
          return;
        }
        _addAiMessage("Perfecto. Estoy creando tu acceso en el nodo central...");
        _registerUser();
        break;
    }
  }

  // --- LOGICA DE RECUPERACION ---
  void _processForgotPassword(String input) async {
    switch (_step) {
      case 0:
        _email = input.toLowerCase();
        _addAiMessage("Buscando nodo de usuario para $_email...");
        _checkUserExists();
        break;
      case 1:
        _licenseKey = input.toUpperCase();
        _verifyLicenseAndReset();
        break;
    }
  }

  Future<void> _checkUserExists() async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('email', _email!)
          .maybeSingle();

      if (profile != null) {
        _addAiMessage("Usuario localizado. Para confirmar que eres el titular del nodo, ingresa la Licencia de tu Organización.");
        _step = 1;
      } else {
        _addAiMessage("No encuentro ningún usuario registrado con el correo $_email en nuestra red.");
        _addAiMessage("Verifica que el correo sea correcto o contacta a tu administrador.");
      }
    } catch (e) {
      _addAiMessage("Error de conexión al verificar el usuario. Intenta de nuevo más tarde.");
    }
  }

  Future<void> _verifyLicenseAndReset() async {
    _addAiMessage("Verificando vinculación de licencia...");
    
    try {
      final tenant = await Supabase.instance.client
          .from('tenants')
          .select('id, name')
          .eq('license_key', _licenseKey!)
          .maybeSingle();

      if (tenant != null) {
        await Supabase.instance.client.auth.resetPasswordForEmail(_email!);
        
        await Supabase.instance.client.from('audit_logs').insert({
          'action': 'PASSWORD_RESET_REQUEST',
          'severity': 'WARNING',
          'details': {
            'email': _email,
            'method': 'AI_ASSISTANT',
            'license_used': _licenseKey
          }
        });

        _addAiMessage("¡Identidad confirmada! He activado el protocolo de recuperación.");
        _addAiMessage("He enviado un correo electrónico real a $_email con las instrucciones para restablecer tu acceso.");
        _addAiMessage("Por favor, revisa tu bandeja de entrada (y la carpeta de spam) para completar el proceso.");
        _step = 3;
      } else {
        _addAiMessage("La licencia proporcionada no coincide con los registros de este usuario.");
      }
    } catch (e) {
      _addAiMessage("Error al procesar la solicitud. Asegúrate de que el correo esté registrado.");
    }
  }

  // --- COMUN ---
  Future<void> _verifyLicenseAndRegister() async {
    _addAiMessage("Verificando licencia...");
    
    try {
      final response = await Supabase.instance.client
          .from('tenants')
          .select('id, name')
          .eq('license_key', _licenseKey!)
          .maybeSingle();
          
      if (response == null) {
        _addAiMessage("Lo siento, no encuentro ninguna organización vinculada a esa licencia.");
      } else {
        _tenantId = response['id'];
        _addAiMessage("Licencia válida para: ${response['name']}.");
        _step = 2;
        _addAiMessage("Finalmente, define la contraseña para tu nueva cuenta.");
      }
    } catch (e) {
      _addAiMessage("Error de conexión. Asegúrate de que las políticas de RLS permitan la verificación.");
    }
  }

  Future<void> _registerUser() async {
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _email!,
        password: _password!,
        data: {
          'full_name': 'Usuario Registrado por IA',
          'tenant_id': _tenantId,
          'role': 'admin'
        },
      );

      if (response.user != null) {
        _addAiMessage("¡Acceso concedido! Tu usuario ha sido provisionado exitosamente.");
        _addAiMessage("Ya puedes volver e iniciar sesión.");
        _step = 3;
      }
    } catch (e) {
      _addAiMessage("Error: Es posible que este correo ya esté en uso o la contraseña sea muy débil.");
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(LucideIcons.bot, color: Colors.red),
            const SizedBox(width: 12),
            Text(_currentMode == AuthMode.register ? "Activación de Cuenta" : "Recuperación de Acceso", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.only(left: 24, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("IA procesando...", style: TextStyle(color: Colors.white24, fontSize: 12)),
              ),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg) {
    return Align(
      alignment: msg.isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: msg.isAi ? const Color(0xFF1A1A1A) : Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ).animate().fadeIn().slideY(begin: 0.1),
    );
  }

  Widget _buildInputArea() {
    if (_step == 3) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Volver al Inicio"),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              obscureText: (_currentMode == AuthMode.register && _step == 2),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  _addUserMessage(val.trim());
                  _controller.clear();
                }
              },
              decoration: InputDecoration(
                hintText: "Escribe tu respuesta...",
                filled: true,
                fillColor: Colors.white.withOpacity(0.02),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () {
              if (_controller.text.trim().isNotEmpty) {
                _addUserMessage(_controller.text.trim());
                _controller.clear();
              }
            },
            icon: const Icon(LucideIcons.send, color: Colors.red),
          ),
        ],
      ),
    );
  }
}
