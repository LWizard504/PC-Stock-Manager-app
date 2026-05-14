import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _selectedContact;
  bool _isLoadingContacts = true;
  bool _isLoadingMessages = false;
  String? _myId;
  RealtimeChannel? _chatChannel;

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser?.id;
    _fetchContacts();
    _setupRealtime();
  }

  @override
  void dispose() {
    if (_chatChannel != null) _supabase.removeChannel(_chatChannel!);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupRealtime() {
    _chatChannel = _supabase.channel('public:chat_messages')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chat_messages',
        callback: (payload) {
          final newMsg = payload.newRecord;
          if (_selectedContact != null) {
            // Check if message belongs to current conversation
            bool isFromMe = newMsg['sender_id'] == _myId;
            bool isToMe = newMsg['recipient_id'] == _myId;
            bool isFromSelected = newMsg['sender_id'] == _selectedContact!['id'];
            bool isToSelected = newMsg['recipient_id'] == _selectedContact!['id'];

            if ((isFromMe && isToSelected) || (isFromSelected && isToMe)) {
              setState(() {
                _messages.add(newMsg);
              });
              _scrollToBottom();
            }
          }
        },
      )
      .subscribe();
  }

  Future<void> _fetchContacts() async {
    try {
      final myProfile = await _supabase.from('profiles').select('tenant_id').eq('id', _myId!).single();
      final tenantId = myProfile['tenant_id'];

      final response = await _supabase
          .from('profiles')
          .select('*')
          .eq('tenant_id', tenantId)
          .neq('id', _myId!)
          .order('full_name');

      if (mounted) {
        setState(() {
          _contacts = List<Map<String, dynamic>>.from(response);
          _isLoadingContacts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingContacts = false);
    }
  }

  Future<void> _fetchMessages(Map<String, dynamic> contact) async {
    setState(() {
      _selectedContact = contact;
      _isLoadingMessages = true;
      _messages = [];
    });

    try {
      // Fetch messages between me and the contact
      final response = await _supabase
          .from('chat_messages')
          .select('*')
          .or('and(sender_id.eq.$_myId,recipient_id.eq.${contact['id']}),and(sender_id.eq.${contact['id']},recipient_id.eq.$_myId)')
          .order('created_at', ascending: true);

      if (mounted && _selectedContact?['id'] == contact['id']) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response);
          _isLoadingMessages = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMessages = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedContact == null) return;

    _messageController.clear();

    try {
      await _supabase.from('chat_messages').insert({
        'sender_id': _myId,
        'recipient_id': _selectedContact!['id'],
        'content': text,
      });
      // Realtime will handle adding to list
    } catch (e) {
      debugPrint("Error sending message: $e");
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
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          // Contacts Sidebar
          _buildContactsSidebar(),
          // Chat Area
          Expanded(child: _buildChatArea()),
        ],
      ),
    );
  }

  Widget _buildContactsSidebar() {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Mensajería Neural", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text("Red de Nodos Activos", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingContacts
              ? const Center(child: CircularProgressIndicator(color: Colors.red))
              : ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    final isSelected = _selectedContact?['id'] == contact['id'];
                    String name = contact['full_name'] ?? '${contact['first_name'] ?? ''} ${contact['last_name'] ?? ''}'.trim();
                    if (name.isEmpty) name = "Nodo Desconocido";

                    return ListTile(
                      onTap: () => _fetchMessages(contact),
                      selected: isSelected,
                      selectedTileColor: Colors.white.withOpacity(0.02),
                      leading: CircleAvatar(
                        backgroundColor: isSelected ? Colors.red : Colors.white10,
                        backgroundImage: contact['avatar_url'] != null ? NetworkImage(contact['avatar_url']) : null,
                        child: contact['avatar_url'] == null 
                          ? Text(name[0].toUpperCase(), style: TextStyle(color: isSelected ? Colors.white : Colors.red, fontWeight: FontWeight.bold))
                          : null,
                      ),
                      title: Text(name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.white70)),
                      subtitle: Text(contact['role']?.toUpperCase() ?? 'USER', style: const TextStyle(fontSize: 10, color: Colors.white24)),
                    ).animate().fadeIn(delay: Duration(milliseconds: 50 * index));
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    if (_selectedContact == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.messageSquare, size: 80, color: Colors.white.withOpacity(0.02)),
            const SizedBox(height: 16),
            const Text("Selecciona un nodo para iniciar la transmisión", style: TextStyle(color: Colors.white24)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildChatHeader(),
        Expanded(
          child: _isLoadingMessages
            ? const Center(child: CircularProgressIndicator(color: Colors.red))
            : _messages.isEmpty
              ? const Center(child: Text("Inicio de la cadena de mensajes", style: TextStyle(color: Colors.white10)))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg['sender_id'] == _myId;
                    return _buildMessageBubble(msg, isMe);
                  },
                ),
        ),
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildChatHeader() {
    String name = _selectedContact!['full_name'] ?? 'Chat';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: _selectedContact!['avatar_url'] != null ? NetworkImage(_selectedContact!['avatar_url']) : null,
            child: _selectedContact!['avatar_url'] == null ? Text(name[0]) : null,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Text("Conexión Segura / En Línea", style: TextStyle(color: Colors.greenAccent, fontSize: 10)),
            ],
          ),
          const Spacer(),
          IconButton(icon: const Icon(LucideIcons.phone, size: 20, color: Colors.white24), onPressed: () {}),
          IconButton(icon: const Icon(LucideIcons.video, size: 20, color: Colors.white24), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    final time = DateFormat('HH:mm').format(DateTime.parse(msg['created_at']));
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isMe ? Colors.red : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(msg['content'] ?? '', style: TextStyle(color: isMe ? Colors.white : Colors.white, fontSize: 14)),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(color: isMe ? Colors.white60 : Colors.white24, fontSize: 10)),
          ],
        ),
      ).animate().fadeIn().slideY(begin: 0.1),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: "Escribe un mensaje...",
                filled: true,
                fillColor: Colors.white.withOpacity(0.02),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          FloatingActionButton(
            onPressed: _sendMessage,
            backgroundColor: Colors.red,
            mini: true,
            child: const Icon(LucideIcons.send, size: 20, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
