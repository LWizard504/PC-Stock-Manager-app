import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pc_dev_flutter/services/signaling_service.dart';
import 'package:pc_dev_flutter/ui/screens/shared/call_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _signaling = SignalingService();
  final _groupNameController = TextEditingController();
  final _fileUrlController = TextEditingController();
  final _replyScrollController = ScrollController();

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
  String? _myRole;
  RealtimeChannel? _presenceChannel;
  RealtimeChannel? _messagesChannel;
  String? _remoteTypingStatus;
  Timer? _typingTimer;
  bool _isSendingTyping = false;
  bool _showEmojiPicker = false;
  Map<String, dynamic>? _replyingTo;
  String? _fileUrl;
  TabController? _tabController;

  final List<String> _commonEmojis = [
    '😀', '😂', '😍', '🥰', '😎', '🤔', '😢', '😡',
    '👍', '👎', '❤️', '🔥', '💯', '🎉', '🙏', '💀',
    '✅', '❌', '⭐', '🚀', '👋', '🤝', '💪', '✨',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _myId = _supabase.auth.currentUser?.id;
    _setupRealtime();
    _fetchContacts();
    _messageController.addListener(_onMessageChanged);
    _searchController.addListener(() => setState(() {}));
  }

  void _setupRealtime() {
    if (_myId == null) return;

    _presenceChannel = _supabase.channel('global-presence');
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

    Future.microtask(() => _signaling.init());

    _signaling.onNewMessage = (data) {
      final fromData = data['from'];
      final senderId = fromData is Map ? fromData['id'] : (data['sender_id'] ?? data['from'] ?? data['senderId']);

      final msg = {
        'id': data['id'] ?? data['tempId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'sender_id': senderId,
        'recipient_id': data['recipient_id'] ?? data['to'],
        'group_id': data['group_id'] ?? data['groupId'],
        'content': data['content'] ?? data['text'] ?? '',
        'file_url': data['fileUrl'] ?? data['file_url'] ?? '',
        'reply_to_id': data['replyTo'] ?? data['reply_to_id'] ?? '',
        'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
      };

      if (_messages.any((m) => m['id'] == msg['id'])) return;

      bool isForCurrentChat = false;
      if (_selectedContact != null) {
        if (_selectedContact!['isGroup'] == true) {
          isForCurrentChat = msg['group_id'] == _selectedContact!['id'];
        } else {
          final sId = msg['sender_id'];
          final selectedId = _selectedContact!['id'];
          isForCurrentChat = sId == selectedId || msg['recipient_id'] == selectedId;
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

    _signaling.onMessageSent = (tempId, dbId) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) {
            _messages[idx]['id'] = dbId;
          }
        });
      }
    };

    _signaling.onTyping = (data) {
      if (_selectedContact == null) return;
      final fromData = data['from'];
      final senderId = fromData is Map ? fromData['id'] : (data['userId'] ?? data['from']);

      if (_isTargetChat(senderId, data['isGroup'] == true, data['groupId'])) {
        if (mounted) {
          setState(() {
            if (data['isTyping'] == true) {
              _remoteTypingStatus = "escribiendo...";
              _startTypingTimeout();
            } else {
              _remoteTypingStatus = null;
            }
          });
        }
      }
    };

    _signaling.onRecording = (data) {
      if (_selectedContact == null) return;
      final fromData = data['from'];
      final senderId = fromData is Map ? fromData['id'] : data['from'];

      if (_isTargetChat(senderId, data['isGroup'] == true, data['groupId'])) {
        if (mounted) {
          setState(() {
            if (data['isRecording'] == true) {
              _remoteTypingStatus = "grabando audio...";
              _startTypingTimeout();
            } else {
              _remoteTypingStatus = null;
            }
          });
        }
      }
    };

    _messagesChannel = _supabase.channel('chat-fallback');
    _messagesChannel!
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
      )
      .subscribe();

    _supabase.from('profiles').update({
      'last_seen_at': DateTime.now().toIso8601String(),
    }).eq('id', _myId!).then((_) {}).catchError((e) {});
  }

  bool _isTargetChat(dynamic senderId, bool isGroup, dynamic groupId) {
    if (_selectedContact == null) return false;
    if (isGroup) {
      return groupId == _selectedContact!['id'];
    } else {
      return senderId == _selectedContact!['id'];
    }
  }

  void _startTypingTimeout() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _remoteTypingStatus = null);
    });
  }

  @override
  void dispose() {
    _signaling.onNewMessage = null;
    _signaling.onOnlineUsers = null;
    _signaling.onUserOffline = null;
    _signaling.onTyping = null;
    _signaling.onRecording = null;
    _typingTimer?.cancel();
    if (_presenceChannel != null) _supabase.removeChannel(_presenceChannel!);
    if (_messagesChannel != null) _supabase.removeChannel(_messagesChannel!);
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _groupNameController.dispose();
    _fileUrlController.dispose();
    _replyScrollController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    if (_selectedContact == null || _myId == null) return;

    if (_messageController.text.isNotEmpty && !_isSendingTyping) {
      _isSendingTyping = true;
      _signaling.sendTyping(
        _selectedContact!['id'],
        true,
        isGroup: _selectedContact!['isGroup'] == true,
      );

      Timer(const Duration(seconds: 3), () {
        _isSendingTyping = false;
        if (_messageController.text.isEmpty) {
          _signaling.sendTyping(
            _selectedContact!['id'],
            false,
            isGroup: _selectedContact!['isGroup'] == true,
          );
        }
      });
    } else if (_messageController.text.isEmpty && _isSendingTyping) {
      _isSendingTyping = false;
      _signaling.sendTyping(
        _selectedContact!['id'],
        false,
        isGroup: _selectedContact!['isGroup'] == true,
      );
    }
  }

  List<Map<String, dynamic>> get _filteredContacts {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _contacts;
    return _contacts.where((c) {
      final name = (c['full_name'] ?? '').toString().toLowerCase();
      final email = (c['email'] ?? '').toString().toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredGroups {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _groups;
    return _groups.where((g) {
      final name = (g['name'] ?? '').toString().toLowerCase();
      return name.contains(query);
    }).toList();
  }

  Future<void> _fetchContacts() async {
    if (_myId == null) {
      if (mounted) setState(() => _isLoadingContacts = false);
      return;
    }

    try {
      final data = await _signaling.fetchContacts();
      final myProfile = data['currentProfile'];

      if (mounted) {
        setState(() {
          _myTenantId = myProfile['tenant_id'];
          _myName = myProfile['full_name'] ?? 'Usuario';
          _myAvatar = myProfile['avatar_url'];
          _myRole = myProfile['role']?.toString().toLowerCase();

          _contacts = List<Map<String, dynamic>>.from(data['contacts'] ?? []);
          _groups = List<Map<String, dynamic>>.from((data['groups'] as List? ?? []).map((g) => {
            ...g as Map<String, dynamic>,
            'isGroup': true,
            'full_name': g['name'],
          }));
          _isLoadingContacts = false;
        });
      }

      _signaling.register(_myId!, _groups.map((g) => g['id'].toString()).toList());
    } catch (e) {
      if (mounted) setState(() => _isLoadingContacts = false);
    }
  }

  Future<void> _fetchMessages(Map<String, dynamic> contact) async {
    setState(() {
      _selectedContact = contact;
      _isLoadingMessages = true;
      _messages = [];
      _replyingTo = null;
      _fileUrl = null;
      _showEmojiPicker = false;
    });

    try {
      final isGroup = contact['isGroup'] == true;
      final res = await _signaling.fetchHistory(contact['id'].toString(), isGroup);

      if (mounted) {
        setState(() {
          final List<dynamic> sorted = List.from(res);
          sorted.sort((a, b) => DateTime.parse(a['created_at']).compareTo(DateTime.parse(b['created_at'])));
          _messages = List<Map<String, dynamic>>.from(sorted);
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
    if (text.isEmpty && (_fileUrl == null || _fileUrl!.isEmpty) || _selectedContact == null) return;

    final isGroup = _selectedContact!['isGroup'] == true;
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final contentToSend = text.isEmpty && (_fileUrl != null && _fileUrl!.isNotEmpty) ? '[Archivo]' : text;
    _messageController.clear();

    final localMsg = {
      'id': tempId,
      'sender_id': _myId,
      'content': contentToSend,
      'file_url': _fileUrl ?? '',
      'reply_to_id': _replyingTo?['id'] ?? '',
      'created_at': DateTime.now().toIso8601String(),
      'is_temp': true,
      if (isGroup) 'group_id': _selectedContact!['id'] else 'recipient_id': _selectedContact!['id'],
    };

    if (mounted) setState(() {
      _messages.add(localMsg);
      _replyingTo = null;
      _fileUrl = null;
      _fileUrlController.clear();
    });
    _scrollToBottom();

    try {
      _signaling.sendMessage(
        _selectedContact!['id'],
        contentToSend,
        isGroup: isGroup,
        senderName: _myName,
        senderAvatar: _myAvatar,
        tempId: tempId,
        fileUrl: _fileUrl,
        fileType: _fileUrl != null && _fileUrl!.isNotEmpty ? (() {
          final lower = _fileUrl!.toLowerCase();
          if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp')) return 'image';
          if (lower.endsWith('.mp4') || lower.endsWith('.webm') || lower.endsWith('.mov')) return 'video';
          if (lower.endsWith('.pdf')) return 'pdf';
          return 'file';
        })() : null,
        replyTo: _replyingTo?['id'],
      );
    } catch (se) {}

    _messageController.clear();
    _isSendingTyping = false;
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

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty || _selectedGroupMembers.isEmpty) return;

    try {
      final res = await _signaling.fetchContacts();
      final session = _supabase.auth.currentSession;
      if (session == null) return;

      final groupInsert = await _supabase.from('chat_groups').insert({
        'name': name,
        'created_by': _myId,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      final groupId = groupInsert['id'];

      final members = [{'group_id': groupId, 'user_id': _myId, 'joined_at': DateTime.now().toIso8601String()}];
      for (final uid in _selectedGroupMembers) {
        members.add({'group_id': groupId, 'user_id': uid, 'joined_at': DateTime.now().toIso8601String()});
      }

      await _supabase.from('chat_group_members').insert(members);

      if (mounted) {
        Navigator.of(context).pop();
        _groupNameController.clear();
        _selectedGroupMembers.clear();
        _fetchContacts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al crear grupo: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  final List<String> _selectedGroupMembers = [];

  void _showCreateGroupDialog() {
    _selectedGroupMembers.clear();
    _groupNameController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.white10)),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(LucideIcons.users, color: Colors.white70, size: 22),
                    ),
                    const SizedBox(width: 16),
                    const Text("Nuevo Grupo", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 24),
                const Text("NOMBRE DEL GRUPO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                TextField(
                  controller: _groupNameController,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: "Ej. Equipo de Ventas",
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.03),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 20),
                const Text("SELECCIONAR MIEMBROS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: ListView(
                    children: _contacts.map((contact) {
                      final isSelected = _selectedGroupMembers.contains(contact['id']);
                      final name = contact['full_name'] ?? 'Contacto';
                      return ListTile(
                        onTap: () {
                          setDialogState(() {
                            if (isSelected) {
                              _selectedGroupMembers.remove(contact['id']);
                            } else {
                              _selectedGroupMembers.add(contact['id']);
                            }
                          });
                        },
                        leading: CircleAvatar(
                          backgroundColor: Colors.white.withOpacity(0.05),
                          backgroundImage: contact['avatar_url'] != null ? NetworkImage(contact['avatar_url']) : null,
                          child: contact['avatar_url'] == null
                            ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white54))
                            : null,
                        ),
                        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        trailing: isSelected
                          ? Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(LucideIcons.check, size: 14, color: Colors.white),
                            )
                          : Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24),
                              ),
                            ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancelar", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: (_groupNameController.text.trim().isNotEmpty && _selectedGroupMembers.isNotEmpty) ? () {
              Navigator.of(ctx).pop();
              _createGroup();
            } : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Crear Grupo"),
          ),
        ],
      ),
    );
  }

  void _startCall(bool isVideo) {
    if (_selectedContact == null) return;
    final isGroup = _selectedContact!['isGroup'] == true;
    final roomId = isGroup ? _selectedContact!['id'] : 'call_${_myId}_${_selectedContact!['id']}';
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(
      contact: _selectedContact!,
      roomId: roomId,
      isVideo: isVideo,
      isGroup: isGroup,
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          _buildContactsSidebar(),
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
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Mensajería", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                    IconButton(
                      icon: const Icon(LucideIcons.plus, color: Colors.white54, size: 20),
                      onPressed: _showCreateGroupDialog,
                      tooltip: "Crear grupo",
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text("Red de Contactos Activos", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Buscar contactos...",
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                      prefixIcon: const Icon(LucideIcons.search, color: Colors.white24, size: 18),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 16, color: Colors.white24),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.05),
          ),
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            indicatorColor: const Color(0xFF6366F1),
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              border: Border(bottom: BorderSide(color: const Color(0xFF6366F1), width: 2)),
            ),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.messageCircle, size: 14),
                    const SizedBox(width: 6),
                    Text("Directos", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.users, size: 14),
                    const SizedBox(width: 6),
                    Text("Grupos", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: _isLoadingContacts
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDirectTab(),
                    _buildGroupsTab(),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectTab() {
    final filtered = _filteredContacts;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.messageCircle, size: 40, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isNotEmpty ? "Sin resultados" : "No hay contactos disponibles",
              style: const TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final contact = filtered[index];
        final isSelected = _selectedContact?['id'] == contact['id'] && _selectedContact?['isGroup'] != true;
        final isOnline = _onlineUserIds.contains(contact['id']);
        final name = contact['full_name'] ?? 'Contacto';
        final lastMsg = contact['last_message'] ?? '';

        return _buildContactTile(contact, name, isSelected, isOnline, lastMsg, false);
      },
    );
  }

  Widget _buildGroupsTab() {
    final filtered = _filteredGroups;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.users, size: 40, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isNotEmpty ? "Sin resultados" : "No hay grupos",
              style: const TextStyle(color: Colors.white24, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _showCreateGroupDialog,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text("Crear grupo"),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF6366F1)),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final group = filtered[index];
        final isSelected = _selectedContact?['id'] == group['id'] && _selectedContact?['isGroup'] == true;
        final name = group['name'] ?? 'Grupo';
        final lastMsg = group['last_message'] ?? '';

        return _buildContactTile(group, name, isSelected, false, lastMsg, true);
      },
    );
  }

  Widget _buildContactTile(Map<String, dynamic> contact, String name, bool isSelected, bool isOnline, String lastMsg, bool isGroup) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () => _fetchMessages(contact),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white.withOpacity(0.05),
              backgroundImage: contact['avatar_url'] != null ? NetworkImage(contact['avatar_url']) : null,
              child: contact['avatar_url'] == null
                ? Icon(isGroup ? LucideIcons.users : LucideIcons.user, size: 18, color: Colors.white38)
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
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0D0D0D), width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: lastMsg.isNotEmpty
          ? Text(
              lastMsg,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              isGroup ? "Chat grupal" : (isOnline ? "En línea" : "Desconectado"),
              style: TextStyle(color: isOnline ? const Color(0xFF10B981).withOpacity(0.7) : Colors.white24, fontSize: 11),
            ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildChatArea() {
    if (_selectedContact == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0F0F0F),
              const Color(0xFF0A0A0A),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(LucideIcons.messageSquare, color: Colors.white12, size: 36),
              ),
              const SizedBox(height: 24),
              const Text(
                "Mensajería",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                "Selecciona un contacto o grupo para iniciar",
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0F0F0F),
            const Color(0xFF0A0A0A),
          ],
        ),
      ),
      child: Column(
        children: [
          _buildChatHeader(),
          Expanded(
            child: _isLoadingMessages
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
              : _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.inbox, size: 48, color: Colors.white.withOpacity(0.06)),
                        const SizedBox(height: 16),
                        const Text("No hay mensajes aún", style: TextStyle(color: Colors.white24, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text("Envía un mensaje para iniciar la conversación", style: TextStyle(color: Colors.white.withOpacity(0.12), fontSize: 12)),
                      ],
                    ),
                  )
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
          if (_remoteTypingStatus != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: const Color(0xFF6366F1).withOpacity(0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _remoteTypingStatus!,
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildChatHeader() {
    final isGroup = _selectedContact!['isGroup'] == true;
    final isOnline = !isGroup && _onlineUserIds.contains(_selectedContact!['id']);
    final name = _selectedContact!['full_name'] ?? _selectedContact!['name'] ?? 'Chat';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.05),
            backgroundImage: _selectedContact!['avatar_url'] != null ? NetworkImage(_selectedContact!['avatar_url']) : null,
            child: _selectedContact!['avatar_url'] == null
              ? Icon(isGroup ? LucideIcons.users : LucideIcons.user, size: 18, color: Colors.white38)
              : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isGroup ? "${(_selectedContact!['member_count'] ?? 0)} miembros" : (isOnline ? "En línea" : "Desconectado"),
                  style: TextStyle(color: isOnline ? const Color(0xFF10B981) : Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ),
          if (_myRole == 'superadmin') ...[
            IconButton(
              icon: const Icon(LucideIcons.phone, size: 18, color: Colors.white54),
              onPressed: () => _startCall(false),
              tooltip: "Llamada de voz",
            ),
            IconButton(
              icon: const Icon(LucideIcons.video, size: 18, color: Colors.white54),
              onPressed: () => _startCall(true),
              tooltip: "Videollamada",
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    final time = DateFormat('HH:mm').format(DateTime.parse(msg['created_at']).toLocal());
    final hasFile = msg['file_url'] != null && msg['file_url'].toString().isNotEmpty;
    final isTemp = msg['is_temp'] == true;
    final fileUrl = msg['file_url']?.toString() ?? '';
    final isImage = hasFile && (fileUrl.endsWith('.png') || fileUrl.endsWith('.jpg') || fileUrl.endsWith('.jpeg') || fileUrl.endsWith('.gif') || fileUrl.endsWith('.webp'));
    final isVideo = hasFile && (fileUrl.endsWith('.mp4') || fileUrl.endsWith('.webm') || fileUrl.endsWith('.mov'));
    final isPdf = hasFile && fileUrl.endsWith('.pdf');
    final replyToId = msg['reply_to_id']?.toString() ?? '';
    final replyMsg = replyToId.isNotEmpty ? _messages.where((m) => m['id'] == replyToId).firstOrNull : null;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPressStart: (_) {
          if (isMe) {
            _showMessageActions(msg);
          }
        },
        onTap: () {
          if (!isMe) {
            setState(() => _replyingTo = msg);
            _messageFocusNode.requestFocus();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.45),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF6366F1).withOpacity(0.85) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyMsg != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(left: BorderSide(color: isMe ? Colors.white38 : const Color(0xFF6366F1), width: 3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        replyMsg!['sender_id'] == _myId ? "Tú" : "Respondiendo",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isMe ? Colors.white70 : const Color(0xFF6366F1),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        replyMsg['content'] ?? '',
                        style: TextStyle(fontSize: 11, color: isMe ? Colors.white60 : Colors.white38),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              if (!isMe && _selectedContact!['isGroup'] == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Text(
                    _contacts.where((c) => c['id'] == msg['sender_id']).firstOrNull?['full_name'] ?? msg['sender_id'].toString().substring(0, 8),
                    style: const TextStyle(color: Color(0xFF6366F1), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(14, (!isMe && _selectedContact!['isGroup'] == true) ? 4 : 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          fileUrl,
                          width: 250,
                          height: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 250,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.image, color: Colors.white24, size: 24),
                                SizedBox(height: 4),
                                Text("Error al cargar", style: TextStyle(color: Colors.white24, fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (isVideo)
                      Container(
                        width: 250,
                        height: 140,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Icon(LucideIcons.video, color: Colors.white38, size: 40),
                        ),
                      ),
                    if (isPdf)
                      Container(
                        width: 250,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(LucideIcons.fileText, color: Colors.white54, size: 20),
                            SizedBox(width: 8),
                            Expanded(child: Text("PDF", style: TextStyle(color: Colors.white54, fontSize: 12))),
                          ],
                        ),
                      ),
                    if (msg['content'] != null && msg['content'].toString().isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: (isImage || isVideo || isPdf) ? 6 : 0),
                        child: Text(
                          msg['content'] ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          time,
                          style: TextStyle(color: isMe ? Colors.white60 : Colors.white30, fontSize: 10),
                        ),
                        if (isTemp)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(LucideIcons.clock, size: 10, color: isMe ? Colors.white.withOpacity(0.4) : Colors.white30),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, duration: 200.ms),
      ),
    );
  }

  void _showMessageActions(Map<String, dynamic> msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.reply, color: Colors.white70),
                title: const Text("Responder", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _replyingTo = msg);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.copy, color: Colors.white70),
                title: const Text("Copiar texto", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: const Color(0xFF6366F1), width: 3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Respondiendo a ${_replyingTo!['sender_id'] == _myId ? 'ti mismo' : 'contacto'}",
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyingTo!['content'] ?? '',
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16, color: Colors.white38),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          if (_fileUrl != null && _fileUrl!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _fileUrl!.endsWith('.png') || _fileUrl!.endsWith('.jpg') || _fileUrl!.endsWith('.jpeg') || _fileUrl!.endsWith('.gif') || _fileUrl!.endsWith('.webp')
                      ? LucideIcons.image
                      : _fileUrl!.endsWith('.pdf') ? LucideIcons.fileText : LucideIcons.link,
                    color: const Color(0xFF6366F1),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fileUrl!,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 14, color: Colors.white38),
                    onPressed: () => setState(() {
                      _fileUrl = null;
                      _fileUrlController.clear();
                    }),
                  ),
                ],
              ),
            ),
          if (_showEmojiPicker)
            Container(
              height: 48,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: _commonEmojis.length,
                separatorBuilder: (_, __) => const SizedBox(width: 2),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      _messageController.text += _commonEmojis[index];
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _messageController.text.length),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_commonEmojis[index], style: const TextStyle(fontSize: 22)),
                    ),
                  );
                },
              ),
            ),
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_showEmojiPicker ? LucideIcons.x : LucideIcons.smile, size: 20, color: Colors.white38),
                    onPressed: () => setState(() => _showEmojiPicker = !_showEmojiPicker),
                    tooltip: "Emojis",
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.link, size: 20, color: Colors.white38),
                    onPressed: () => _showFileUrlDialog(),
                    tooltip: "Adjuntar archivo (URL)",
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    onSubmitted: (_) => _sendMessage(),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: "Escribe un mensaje...",
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 4,
                    minLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(LucideIcons.send, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFileUrlDialog() {
    _fileUrlController.text = _fileUrl ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
        title: const Text("Adjuntar archivo", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: _fileUrlController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: "URL del archivo o imagen...",
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancelar", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final url = _fileUrlController.text.trim();
              setState(() => _fileUrl = url.isEmpty ? null : url);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Adjuntar"),
          ),
        ],
      ),
    );
  }
}
