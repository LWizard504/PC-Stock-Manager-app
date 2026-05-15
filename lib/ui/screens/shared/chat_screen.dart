import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:pc_dev_flutter/ui/screens/shared/call_screen.dart';
import 'package:pc_dev_flutter/services/signaling_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _signaling = SignalingService();

  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _messages = [];
  Set<String> _onlineUserIds = {};
  Map<String, dynamic>? _selectedContact;
  bool _isLoadingContacts = true;
  bool _isLoadingMessages = false;
  String? _myId;
  String? _myTenantId;
  String? _myName;
  String? _myAvatar;
  RealtimeChannel? _presenceChannel;

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser?.id;
    _fetchContacts(); // Will trigger _setupRealtime after fetching profile
// _setupRealtime will be called inside _fetchContacts after profile load
  }

  void _setupRealtime() {
    if (_myId == null) return;

    // 1. Supabase Presence Channel (Global)
    _presenceChannel = _supabase.channel('neural-global-presence');
    _presenceChannel!.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _presenceChannel!.track({
          'isGlobalTyping': false,
          'isRecordingAudio': false,
          'typingIn': null,
          'name': _myName,
          'avatar': _myAvatar,
          't': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });

    // 2. Signaling API (Socket.io) Initialization
    _signaling.init();
    
    _signaling.onNewMessage = (msg) {
      if (_messages.any((m) => m['id'] == msg['id'])) return;
      
      bool isForCurrentChat = false;
      if (_selectedContact != null) {
        if (_selectedContact!['isGroup'] == true) {
          isForCurrentChat = msg['group_id'] == _selectedContact!['id'];
        } else {
          isForCurrentChat = msg['sender_id'] == _selectedContact!['id'] || msg['recipient_id'] == _selectedContact!['id'];
        }
      }

      if (isForCurrentChat) {
        if (mounted) setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    };

    _signaling.onOnlineUsers = (ids) {
      if (mounted) setState(() => _onlineUserIds = ids.toSet());
    };

    _signaling.onUserOnline = (id) {
      if (mounted) setState(() => _onlineUserIds.add(id));
    };

    _signaling.onUserOffline = (id) {
      if (mounted) setState(() => _onlineUserIds.remove(id));
    };

    _signaling.onIncomingCall = (payload) {
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(
          contact: payload['from'],
          roomId: payload['roomId'] ?? 'direct_call_${payload['from']['id']}',
          isVideo: payload['type'] == 'video',
          isIncoming: true,
          isGroup: payload['isGroup'] ?? false,
          initialOffer: payload['payload']['offer'],
        )));
      }
    };

    // 3. Realtime Fallback (Supabase)
    _supabase.channel('neural-chat-fallback')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chat_messages',
        callback: (payload) {
          final msg = payload.newRecord;
          if (_messages.any((m) => m['id'] == msg['id'])) return;
          
          bool isForCurrentChat = false;
          if (_selectedContact != null) {
            if (_selectedContact!['isGroup'] == true) {
              isForCurrentChat = msg['group_id'] == _selectedContact!['id'];
            } else {
              isForCurrentChat = msg['sender_id'] == _selectedContact!['id'] || msg['recipient_id'] == _selectedContact!['id'];
            }
          }

          if (isForCurrentChat) {
            if (mounted) setState(() => _messages.add(msg));
            _scrollToBottom();
          }
        },
      ).subscribe();

    // Heartbeat update
    _supabase.from('profiles').update({
      'last_seen_at': DateTime.now().toIso8601String(),
    }).eq('id', _myId!).then((_) {}).catchError((e) => debugPrint("Presence update error: $e"));
  }

  @override
  void dispose() {
    if (_presenceChannel != null) _supabase.removeChannel(_presenceChannel!);
    // _signaling.disconnect(); // Keep active for global calls
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }



  Future<void> _fetchContacts() async {
    if (_myId == null) {
      debugPrint("ChatScreen Error: No authenticated user ID");
      if (mounted) setState(() => _isLoadingContacts = false);
      return;
    }

    try {
      // Get my profile details first to ensure we have name/avatar for presence
      final myProfileRes = await _supabase.from('profiles').select('tenant_id, role, full_name, avatar_url').eq('id', _myId!).single();
      _myTenantId = myProfileRes['tenant_id'];
      final myRole = (myProfileRes['role'] ?? '').toString().toLowerCase();
      _myName = myProfileRes['full_name'] ?? 'Neural Node';
      _myAvatar = myProfileRes['avatar_url'];

      // 1. Fetch Profiles (Fetch all and filter locally like the Web API to bypass RLS complexities)
      List<dynamic> allProfiles = [];
      try {
        final res = await _supabase.from('profiles').select('*').neq('id', _myId!).order('full_name');
        allProfiles = res as List<dynamic>;
        
        // RBAC filtering similar to app/api/chat/contacts/route.ts:
        if (myRole != 'superadmin') {
          allProfiles = allProfiles.where((p) {
            final pRole = (p['role'] ?? '').toString().toLowerCase();
            // Same tenant OR is an admin/superadmin
            if (p['tenant_id'] == _myTenantId) return true;
            if (pRole == 'admin' || pRole == 'superadmin') return true;
            return false;
          }).toList();
        }
        debugPrint("ChatScreen: Profiles fetched and filtered (${allProfiles.length})");
      } catch (pe) {
        debugPrint("ChatScreen Warning: Error fetching profiles: $pe");
      }

      // 2. Fetch Groups
      List<dynamic> groupsRes = [];
      try {
        if (myRole == 'superadmin') {
          groupsRes = await _supabase.from('chat_groups').select('*');
        } else {
          final memberships = await _supabase.from('chat_group_members').select('group_id').eq('user_id', _myId!);
          final groupIds = (memberships as List).map((m) => m['group_id']).toList();
          if (groupIds.isNotEmpty) {
            groupsRes = await _supabase.from('chat_groups').select('*').inFilter('id', groupIds);
          }
        }
        debugPrint("ChatScreen: Groups fetched (${groupsRes.length})");
      } catch (ge) {
        debugPrint("ChatScreen Warning: Error fetching groups: $ge");
      }

      if (mounted) {
        setState(() {
          _contacts = List<Map<String, dynamic>>.from(allProfiles);
          _groups = List<Map<String, dynamic>>.from(groupsRes.map((g) => { ...g as Map<String, dynamic>, 'isGroup': true, 'full_name': g['name'] }));
          _isLoadingContacts = false;
        });
      }

      // Setup Realtime Presence after we have profile data
      _setupRealtime();
      
      // Neural Protocol: Register groups with Signaling API for real-time routing
      _signaling.register(_myId!, _groups.map((g) => g['id'].toString()).toList());

    } catch (e) {
      debugPrint("ChatScreen Fatal Error: $e");
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
      final isGroup = contact['isGroup'] == true;
      debugPrint("ChatScreen: Fetching messages for ${isGroup ? 'group' : 'user'} ${contact['id']}");

      dynamic res;
      if (isGroup) {
        res = await _supabase.from('chat_messages')
          .select()
          .eq('group_id', contact['id'])
          .order('created_at', ascending: true);
      } else {
        res = await _supabase.from('chat_messages')
          .select()
          .or('and(sender_id.eq.$_myId,recipient_id.eq.${contact['id']}),and(sender_id.eq.${contact['id']},recipient_id.eq.$_myId)')
          .order('created_at', ascending: true);
      }

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(res as List);
          _isLoadingMessages = false;
        });
        debugPrint("ChatScreen: Loaded ${_messages.length} messages");
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("ChatScreen: Error fetching messages: $e");
      if (mounted) setState(() => _isLoadingMessages = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedContact == null) return;

    final isGroup = _selectedContact!['isGroup'] == true;
    _messageController.clear();

    try {
      debugPrint("ChatScreen: Inserting message to DB...");
      final res = await _supabase.from('chat_messages').insert({
        'sender_id': _myId,
        'tenant_id': _myTenantId,
        if (isGroup) 'group_id': _selectedContact!['id'] else 'recipient_id': _selectedContact!['id'],
        'content': text,
      }).select().single();

      final msg = res as Map<String, dynamic>;
      debugPrint("ChatScreen: Message inserted, ID: ${msg['id']}");
      
      // Signaling API: Send via Socket for instant parity and log visibility
      _signaling.sendMessage(
        isGroup ? _selectedContact!['id'] : _selectedContact!['id'],
        text,
        isGroup: isGroup,
        senderName: _myName,
        senderAvatar: _myAvatar,
        tempId: msg['id'],
      );
      
      if (mounted) setState(() => _messages.add(msg));
      _scrollToBottom();
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
              : ListView(
                  children: [
                    if (_groups.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 20, 20, 10),
                        child: Text("CLUSTERS NEURALES", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      ),
                      ..._groups.map((group) {
                        bool isSelected = _selectedContact?['id'] == group['id'];
                        return ListTile(
                          onTap: () => _fetchMessages(group),
                          selected: isSelected,
                          selectedTileColor: Colors.white.withOpacity(0.02),
                          leading: CircleAvatar(
                            backgroundColor: Colors.white.withOpacity(0.05),
                            child: const Icon(LucideIcons.users, size: 16, color: Colors.white24),
                          ),
                          title: Text(group['name'] ?? 'Grupo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: const Text("Multi-Nivel / P2P activo", style: TextStyle(color: Colors.white24, fontSize: 11)),
                        );
                      }),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 20, 20, 10),
                      child: Text("CONTACTOS DIRECTOS", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ),
                    ..._contacts.map((contact) {
                      final isSelected = _selectedContact?['id'] == contact['id'];
                      final isOnline = _onlineUserIds.contains(contact['id']);
                      String name = contact['full_name'] ?? '${contact['first_name'] ?? ''} ${contact['last_name'] ?? ''}'.trim();
                      if (name.isEmpty) name = "Nodo Desconocido";

                      return ListTile(
                        onTap: () => _fetchMessages(contact),
                        selected: isSelected,
                        selectedTileColor: Colors.white.withOpacity(0.02),
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: isSelected ? Colors.red : Colors.white10,
                              backgroundImage: contact['avatar_url'] != null ? NetworkImage(contact['avatar_url']) : null,
                              child: contact['avatar_url'] == null 
                                ? Text(name[0].toUpperCase(), style: TextStyle(color: isSelected ? Colors.white : Colors.red, fontWeight: FontWeight.bold))
                                : null,
                            ),
                            if (isOnline)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      title: Text(name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.white70)),
                      subtitle: Text(contact['role']?.toUpperCase() ?? 'USER', style: const TextStyle(fontSize: 10, color: Colors.white24)),
                    ).animate().fadeIn();
                  }),
                ],
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
    bool isGroup = _selectedContact!['isGroup'] == true;
    bool isOnline = !isGroup && _onlineUserIds.contains(_selectedContact!['id']);
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name, 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), 
                  overflow: TextOverflow.ellipsis
                ),
                Text(
                  isGroup ? "Nodo de Red Industrial" : (isOnline ? "Conexión Segura / En Línea" : "Desconectado / Última conexión reciente"), 
                  style: TextStyle(color: isOnline ? Colors.greenAccent : Colors.white24, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(LucideIcons.phone, size: 20, color: Colors.white70), 
            onPressed: () {
              final isGroup = _selectedContact!['isGroup'] == true;
              final roomId = isGroup ? _selectedContact!['id'] : 'call_${_myId}_${_selectedContact!['id']}';
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(
                contact: _selectedContact!, 
                roomId: roomId, 
                isVideo: false,
                isGroup: isGroup,
              )));
            }
          ),
          IconButton(
            icon: const Icon(LucideIcons.video, size: 20, color: Colors.white70), 
            onPressed: () {
              final isGroup = _selectedContact!['isGroup'] == true;
              final roomId = isGroup ? _selectedContact!['id'] : 'call_${_myId}_${_selectedContact!['id']}';
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(
                contact: _selectedContact!, 
                roomId: roomId, 
                isVideo: true,
                isGroup: isGroup,
              )));
            }
          ),
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
            if (!isMe && _selectedContact!['isGroup'] == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  msg['sender_id'].toString().substring(0, 8),
                  style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            Text(msg['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
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
