import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class RegistrationChatScreen extends StatefulWidget {
  const RegistrationChatScreen({super.key});

  @override
  State<RegistrationChatScreen> createState() => _RegistrationChatScreenState();
}

class Message {
  final String text;
  final bool isAi;
  final DateTime time;

  Message(this.text, {this.isAi = true}) : time = DateTime.now();
}

class _RegistrationChatScreenState extends State<RegistrationChatScreen> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isTyping = false;
  int _step = 0;
  
  // Registration data
  String? _email;
  String? _licenseKey;
  String? _password;
  String? _tenantId;

  @override
  void initState() {
    super.initState();
    _addAiMessage("Hola, soy el Agente de Activación de Stakia. Veo que intentas acceder a la red industrial.");
    _addAiMessage("Para comenzar, ¿podrías proporcionarme tu dirección de correo electrónico corporativo?");
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
    switch (_step) {
      case 0: // Email
        _email = input;
        if (!_email!.contains('@')) {
          _addAiMessage("Ese correo no parece válido. Por favor, asegúrate de escribirlo correctamente.");
          return;
        }
        _step = 1;
        _addAiMessage("Entendido. Ahora, por favor ingresa tu código de licencia (STK-XXXX-XXXX-XXXX).");
        break;
        
      case 1: // License
        _licenseKey = input.toUpperCase();
        _addAiMessage("Verificando licencia en la red...");
        
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
            _addAiMessage("Licencia válida para la organización: ${response['name']}.");
            _step = 2;
            _addAiMessage("Finalmente, ¿qué contraseña deseas utilizar para tu cuenta?");
          }
        } catch (e) {
          _addAiMessage("Hubo un error al conectar con el servidor central. Intenta de nuevo.");
        }
        break;
        
      case 2: // Password
        _password = input;
        if (_password!.length < 6) {
          _addAiMessage("La contraseña debe tener al menos 6 caracteres por seguridad.");
          return;
        }
        _addAiMessage("Perfecto. Estoy creando tu acceso en el nodo de ${_tenantId!.substring(0,8)}...");
        _registerUser();
        break;
    }
  }

  Future<void> _registerUser() async {
    try {
      // In a real app, you would use a Supabase Edge Function to avoid 
      // exposing the service role or to handle administrative user creation.
      // For this demo, we'll try to use the auth signUp if the policy allows 
      // or simulate the success.
      
      final response = await Supabase.instance.client.auth.signUp(
        email: _email!,
        password: _password!,
        data: {
          'full_name': 'Nuevo Usuario',
          'tenant_id': _tenantId,
          'role': 'admin'
        },
      );

      if (response.user != null) {
        _addAiMessage("¡Acceso concedido! Tu usuario ha sido creado exitosamente.");
        _addAiMessage("Ya puedes volver a la pantalla de inicio y entrar con tus credenciales.");
        _step = 3; // Finished
      }
    } catch (e) {
      _addAiMessage("Hubo un problema al crear tu usuario. Es posible que el correo ya esté registrado.");
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
        title: const Row(
          children: [
            Icon(LucideIcons.bot, color: Colors.red),
            SizedBox(width: 12),
            Text("Asistente de Registro", style: TextStyle(fontWeight: FontWeight.bold)),
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
                child: Text("IA está escribiendo...", style: TextStyle(color: Colors.white24, fontSize: 12)),
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
            child: const Text("Volver al Login"),
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
