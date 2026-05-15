import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:supabase_flutter/supabase_flutter.dart';

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  io.Socket? socket;
  final String _serverUrl = "https://api-stockm-call-service.onrender.com";
  
  // Callbacks for UI updates
  Function(Map<String, dynamic>)? onNewMessage;
  Function(Map<String, dynamic>)? onIncomingCall;
  Function(Map<String, dynamic>)? onSignal;
  Function(Map<String, dynamic>)? onHangup;
  Function(Map<String, dynamic>)? onTyping;
  Function(List<String>)? onOnlineUsers;
  Function(String)? onUserOnline;
  Function(String)? onUserOffline;

  Future<void> init({List<String> groupIds = const []}) async {
    if (socket != null && socket!.connected) return;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final session = supabase.auth.currentSession;
    final token = session?.accessToken;

    socket = io.io(_serverUrl, io.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .enableAutoConnect()
      .build());

    socket!.onConnect((_) {
      debugPrint('SignalingService: Connected to Signaling Server');
      socket!.emit('get-online-users');
      socket!.emit('register', { 'userId': user.id, 'groups': groupIds });
    });

    socket!.onConnectError((data) => debugPrint('SignalingService: Connect Error: $data'));
    socket!.onDisconnect((_) => debugPrint('SignalingService: Disconnected'));

    socket!.on('message', (data) {
      debugPrint("SignalingService: Received message: $data");
      if (onNewMessage != null) onNewMessage!(Map<String, dynamic>.from(data));
    });

    socket!.on('signal', (data) {
      if (onSignal != null) onSignal!(Map<String, dynamic>.from(data));
      if (data['payload'] != null && data['payload']['offer'] != null) {
        if (onIncomingCall != null) onIncomingCall!(Map<String, dynamic>.from(data));
      }
    });

    socket!.on('hangup', (data) {
      if (onHangup != null) onHangup!(Map<String, dynamic>.from(data));
    });

    socket!.on('typing', (data) {
      if (onTyping != null) onTyping!(Map<String, dynamic>.from(data));
    });

    socket!.on('online-users', (data) {
      if (onOnlineUsers != null) onOnlineUsers!(List<String>.from(data));
    });

    socket!.on('user-online', (data) {
      if (onUserOnline != null) onUserOnline!(data.toString());
    });

    socket!.on('user-offline', (data) {
      if (onUserOffline != null) onUserOffline!(data.toString());
    });
  }

  void sendMessage(String to, String content, {bool isGroup = false, String? fileUrl, String? fileType, String? replyTo, String? tempId, String? senderName, String? senderAvatar}) {
    if (socket == null || !socket!.connected) {
      debugPrint('SignalingService: Cannot send message, socket not connected');
      return;
    }

    socket!.emit('send-message', {
      'to': to,
      'content': content,
      'isGroup': isGroup,
      'fileUrl': fileUrl,
      'fileType': fileType,
      'replyTo': replyTo,
      'tempId': tempId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'senderName': senderName,
      'senderAvatar': senderAvatar,
    });
  }

  void sendSignal(String to, dynamic payload, {String type = 'video', bool isGroup = false, String? groupId, Map<String, dynamic>? from}) {
    if (socket == null || !socket!.connected) return;

    socket!.emit('signal', {
      'to': to,
      'from': from,
      'type': type,
      'payload': payload,
      'isGroup': isGroup,
      'groupId': groupId,
    });
  }

  void sendHangup(String to, String fromId) {
    if (socket == null || !socket!.connected) return;
    socket!.emit('hangup', {
      'to': to,
      'from': fromId,
    });
  }

  void disconnect() {
    socket?.disconnect();
    socket = null;
  }
}
