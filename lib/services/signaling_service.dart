import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/services/config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  io.Socket? socket;
  final String _serverUrl = AppConfig.signalingUrl;
  
  final ValueNotifier<Set<String>> onlineUsersNotifier = ValueNotifier<Set<String>>({});
  
  // Callbacks for UI updates
  Function(Map<String, dynamic>)? onNewMessage;
  Function(Map<String, dynamic>)? onIncomingCall;
  Function(Map<String, dynamic>)? onSignal;
  Function(Map<String, dynamic>)? onHangup;
  Function(Map<String, dynamic>)? onTyping;
  Function(Map<String, dynamic>)? onRecording;
  Function(List<String>)? onOnlineUsers;
  Function(String)? onUserOnline;
  Function(String)? onUserOffline;
  Function(String, String)? onMessageSent;

  Future<void> init({List<String> groupIds = const []}) async {
    if (socket != null && socket!.connected) {
      debugPrint('SignalingService: Socket already connected, skipping init');
      return;
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('SignalingService: No user found for init');
      return;
    }

    final session = supabase.auth.currentSession;
    final token = session?.accessToken;
    debugPrint('SignalingService: Initializing socket with token: ${token?.substring(0, 10)}...');

    socket = io.io(_serverUrl, io.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token, 'client': 'pcdev'})
      .enableAutoConnect()
      .build());

    socket!.onConnect((_) {
      debugPrint('SignalingService: Socket Connected. ID: ${socket!.id}');
      socket!.emit('get-online-users');
      // Neural Protocol: Only send groups, server derives userId from token
      debugPrint('SignalingService: Emitting register with groups: $groupIds');
      socket!.emit('register', { 'groups': groupIds });
    });

    socket!.onConnectError((data) => debugPrint('SignalingService: Connect Error: $data'));
    socket!.onDisconnect((_) => debugPrint('SignalingService: Socket Disconnected'));

    socket!.on('new-message', (data) {
      debugPrint("SignalingService: Received message: $data");
      if (onNewMessage != null) onNewMessage!(Map<String, dynamic>.from(data));
    });

    socket!.on('typing', (data) {
      debugPrint("SignalingService: Received typing: $data");
      if (onTyping != null) onTyping!(Map<String, dynamic>.from(data));
    });

    socket!.on('recording', (data) {
      debugPrint("SignalingService: Received recording: $data");
      if (onRecording != null) onRecording!(Map<String, dynamic>.from(data));
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

    socket!.on('online-users', (data) {
      final ids = List<String>.from(data).toSet();
      onlineUsersNotifier.value = ids;
      if (onOnlineUsers != null) onOnlineUsers!(List<String>.from(data));
    });

    socket!.on('user-online', (data) {
      final userId = data.toString();
      final current = Set<String>.from(onlineUsersNotifier.value);
      current.add(userId);
      onlineUsersNotifier.value = current;
      if (onUserOnline != null) onUserOnline!(userId);
    });

    socket!.on('user-offline', (data) {
      final userId = data.toString();
      final current = Set<String>.from(onlineUsersNotifier.value);
      current.remove(userId);
      onlineUsersNotifier.value = current;
      if (onUserOffline != null) onUserOffline!(userId);
    });

    socket!.on('message-sent', (data) {
      debugPrint("SignalingService: Message persisted: $data");
      if (onMessageSent != null) onMessageSent!(data['tempId'].toString(), data['dbId'].toString());
    });
  }

  // API Proxy Methods (Android Parity)
  
  Future<Map<String, dynamic>> fetchContacts() async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null) throw Exception("No auth session");

    final response = await http.get(
      Uri.parse("$_serverUrl/get-contacts"),
      headers: {
        'Authorization': 'Bearer $token',
        'X-Client-Platform': 'pcdev',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Failed to fetch contacts: ${response.body}");
    }
  }

  Future<List<dynamic>> fetchHistory(String chatId, bool isGroup) async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null) throw Exception("No auth session");

    final response = await http.get(
      Uri.parse("$_serverUrl/get-history?chatId=$chatId&isGroup=$isGroup"),
      headers: {
        'Authorization': 'Bearer $token',
        'X-Client-Platform': 'pcdev',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Failed to fetch history: ${response.body}");
    }
  }

  Future<void> adminResetPassword(String targetUserId, String email, String newPassword) async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null) throw Exception("No auth session");

    final response = await http.post(
      Uri.parse("$_serverUrl/admin/reset-password"),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-Client-Platform': 'pcdev',
      },
      body: json.encode({
        'target_user_id': targetUserId,
        'email': email,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      try {
        final errData = json.decode(response.body);
        throw Exception(errData['error'] ?? "Failed to reset password");
      } catch (e) {
        throw Exception("Failed to reset password: ${response.body}");
      }
    }
  }

  Future<void> adminCreateUser({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    String? tenantId,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null) throw Exception("No auth session");

    final response = await http.post(
      Uri.parse("$_serverUrl/admin/create-user"),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-Client-Platform': 'pcdev',
      },
      body: json.encode({
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
        'role': role,
        'tenant_id': tenantId,
      }),
    );

    if (response.statusCode != 200) {
      try {
        final errData = json.decode(response.body);
        throw Exception(errData['error'] ?? "Failed to provision user");
      } catch (e) {
        throw Exception("Failed to provision user: ${response.body}");
      }
    }
  }

  Future<void> adminPurgeUser(String targetUserId, String targetName, String targetEmail) async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null) throw Exception("No auth session");

    final response = await http.post(
      Uri.parse("$_serverUrl/admin/purge-user"),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-Client-Platform': 'pcdev',
      },
      body: json.encode({
        'target_user_id': targetUserId,
        'target_name': targetName,
        'target_email': targetEmail,
      }),
    );

    if (response.statusCode != 200) {
      try {
        final errData = json.decode(response.body);
        throw Exception(errData['error'] ?? "Failed to purge user");
      } catch (e) {
        throw Exception("Failed to purge user: ${response.body}");
      }
    }
  }

  void sendMessage(String to, String content, {bool isGroup = false, String? fileUrl, String? fileType, String? replyTo, String? tempId, String? senderName, String? senderAvatar}) {
    if (socket == null || !socket!.connected) {
      debugPrint('SignalingService: Cannot send message, socket not connected');
      return;
    }

    debugPrint('SignalingService: Emitting send-message to $to');
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

  void sendHangup(String to, String fromId, {String? senderName, String? status, String? duration, String? tenantId, bool isGroup = false}) {
    if (socket == null || !socket!.connected) return;
    socket!.emit('hangup', {
      'to': to,
      'from': fromId,
      'senderName': senderName,
      'status': status,
      'duration': duration,
      'tenantId': tenantId,
      'isGroup': isGroup
    });
  }
  void sendTyping(String to, bool isTyping, {bool isAudio = false, bool isGroup = false}) {
    if (socket == null || !socket!.connected) return;
    socket!.emit('typing', {
      'to': to,
      'isTyping': isTyping,
      'isAudio': isAudio,
      'isGroup': isGroup,
    });
  }

  void register(String userId, List<String> groupIds) {
    if (socket == null || !socket!.connected) {
      debugPrint('SignalingService: Cannot register, socket not connected');
      return;
    }
    debugPrint('SignalingService: Registering groups: $groupIds');
    socket!.emit('register', {
      'groups': groupIds,
    });
  }

  void disconnect() {
    socket?.disconnect();
    socket = null;
  }
}
