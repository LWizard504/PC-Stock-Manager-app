import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pc_dev_flutter/services/signaling_service.dart';
import 'package:pc_dev_flutter/services/config.dart';

class Participant {
  final String id;
  final String name;
  final String? avatar;
  final RTCVideoRenderer renderer;
  bool isVideoEnabled;
  bool isAudioEnabled;

  Participant({
    required this.id,
    required this.name,
    this.avatar,
    required this.renderer,
    this.isVideoEnabled = true,
    this.isAudioEnabled = true,
    this.signalQuality = 100,
  });

  int signalQuality;
}

class CallScreen extends StatefulWidget {
  final Map<String, dynamic> contact; // This can be a User or a Group
  final bool isVideo;
  final bool isIncoming;
  final String roomId;
  final Map<String, dynamic>? initialOffer;
  final bool isGroup;

  const CallScreen({
    super.key,
    required this.contact,
    required this.roomId,
    this.isVideo = false,
    this.isIncoming = false,
    this.initialOffer,
    this.isGroup = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  static const saasYellow = Color(0xFFEAB308);
  static const industrialRed = Color(0xFFFF0000);
  static const pureBlack = Color(0xFF050505);
  final _localRenderer = RTCVideoRenderer();
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, Participant> _remoteParticipants = {};
  
  bool _inCall = false;
  bool _isMicMuted = false;
  bool _isVideoMuted = false;
  bool _isSpeakerOn = true;

  MediaStream? _localStream;
  final _signaling = SignalingService();
  final _supabase = Supabase.instance.client;

  // Neural Aesthetics & Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _callStatus = 'connecting';
  DateTime? _callStartTime;
  Timer? _neuralTelemetryTimer;

  @override
  void initState() {
    super.initState();
    _isVideoMuted = !widget.isVideo;
    
    // Pulse Animation for Incoming Calls
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _initRenderers();
    _initWebrtc();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stopStatsTimer();
    
    // Neural Node Cleanup: Prevent signaling callbacks from firing on disposed screen
    _signaling.onSignal = null;
    _signaling.onHangup = null;
    
    _localStream?.getTracks().forEach((t) => t.stop());
    _peerConnections.values.forEach((pc) {
      try {
        pc.close();
      } catch (e) {
        debugPrint("Error closing peer connection: $e");
      }
    });
    _remoteParticipants.values.forEach((p) => p.renderer.dispose());

    _localRenderer.dispose();
    super.dispose();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
  }

  Future<void> _initWebrtc() async {
    final mediaConstraints = {
      'audio': true,
      'video': widget.isVideo
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error getting user media: $e");
      return;
    }

    // Listen for signaling events via Socket.io (Matches Web Signaling)
    _signaling.onSignal = (data) async {
      final senderId = data['from']['id'];
      final type = data['type'];
      final payload = data['payload'];

      if (type == 'ice-candidate' || payload['candidate'] != null) {
        final candidateData = payload['candidate'];
        final candidate = RTCIceCandidate(
          candidateData['candidate'],
          candidateData['sdpMid'],
          candidateData['sdpMLineIndex'],
        );
        if (_peerConnections.containsKey(senderId)) {
          final pc = _peerConnections[senderId]!;
          if (await pc.getRemoteDescription() != null) {
            await pc.addCandidate(candidate);
          } else {
            _pendingCandidates.putIfAbsent(senderId, () => []).add(candidate);
          }
        } else {
          _pendingCandidates.putIfAbsent(senderId, () => []).add(candidate);
          debugPrint("CallScreen: Queued ICE candidate for $senderId");
        }
      } else if (type == 'call-answer' || payload['answer'] != null) {
        final answer = payload['answer'];
        final desc = RTCSessionDescription(answer['sdp'], answer['type']);
        await _peerConnections[senderId]?.setRemoteDescription(desc);
        if (mounted) setState(() {
          _inCall = true;
          _callStatus = 'Conexión Segura';
          _callStartTime = DateTime.now();
          _startStatsTimer();
        });
      }
    };

    _signaling.onHangup = (data) {
      final senderId = data['from'];
      if (widget.isGroup) {
        _removeParticipant(senderId);
      } else {
        _endCall(sendSignal: false, reason: _inCall ? "Llamada finalizada" : "Llamada rechazada");
      }
    };

    if (!widget.isIncoming) {
      _initiateCall();
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String remoteUserId, String remoteUserName, String? remoteAvatar) async {
    final pc = await createPeerConnection(AppConfig.iceServers);

    _localStream!.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onIceCandidate = (candidate) {
      _sendSignal('ice-candidate', {
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      }, remoteUserId);
    };

    pc.onTrack = (event) async {
      debugPrint("CallScreen: Received remote track: ${event.track.kind}");
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
      }
      if (event.track.kind == 'video' || event.track.kind == 'audio') {
        if (!_remoteParticipants.containsKey(remoteUserId)) {
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.srcObject = event.streams[0];
          
          if (mounted) {
            setState(() {
              _remoteParticipants[remoteUserId] = Participant(
                id: remoteUserId,
                name: remoteUserName,
                avatar: remoteAvatar,
                renderer: renderer,
              );
              _inCall = true;
            });
          }
        }
      }
    };

    _peerConnections[remoteUserId] = pc;

    return pc;
  }

  Future<void> _processPendingCandidates(String remoteUserId) async {
    final pc = _peerConnections[remoteUserId];
    if (pc != null && await pc.getRemoteDescription() != null) {
      if (_pendingCandidates.containsKey(remoteUserId)) {
        final candidates = _pendingCandidates[remoteUserId]!;
        for (var candidate in candidates) {
          await pc.addCandidate(candidate);
        }
        debugPrint("CallScreen: Processed ${candidates.length} queued ICE candidates for $remoteUserId");
        _pendingCandidates.remove(remoteUserId);
      }
    }
  }

  Future<void> _initiateCall() async {
    setState(() => _callStatus = 'Estableciendo Señal...');
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    if (widget.isGroup) {
      // Mesh Topology: individual offers to all group members
      final membersRes = await _supabase.from('chat_group_members').select('user_id').eq('group_id', widget.contact['id']);
      final memberIds = (membersRes as List).map((m) => m['user_id'].toString()).where((id) => id != myId).toList();

      for (final targetId in memberIds) {
        _sendOffer(targetId);
      }
    } else {
      _sendOffer(widget.contact['id']);
    }
  }

  Future<void> _sendOffer(String targetId) async {
    final pc = await _createPeerConnection(targetId, widget.contact['full_name'] ?? widget.contact['name'] ?? 'User', widget.contact['avatar_url'] ?? widget.contact['avatar']);
    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': widget.isVideo,
      },
      'optional': [],
    };
    final offer = await pc.createOffer(constraints);
    await pc.setLocalDescription(offer);

    _sendSignal('call-offer', {
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'roomId': widget.roomId,
      'type': widget.isVideo ? 'video' : 'voice',
      'isGroup': widget.isGroup,
      'groupId': widget.isGroup ? widget.contact['id'] : null,
    }, targetId);
  }

  Future<void> _sendSignal(String event, Map<String, dynamic> payload, String targetId) async {
    final myId = _supabase.auth.currentUser?.id;
    final myProfile = await _supabase.from('profiles').select('full_name, avatar_url').eq('id', myId!).single();

    final from = {
      'id': myId,
      'name': myProfile['full_name'],
      'avatar': myProfile['avatar_url'],
    };

    // Send via Signaling API (Socket.io) for parity and visibility
    _signaling.sendSignal(
      targetId, 
      payload, 
      type: event, 
      isGroup: widget.isGroup, 
      groupId: widget.isGroup ? widget.contact['id'] : null, 
      from: from
    );
  }

  Future<void> _acceptCall() async {
    if (widget.initialOffer == null) return;
    
    final remoteUserId = widget.contact['id'];
    final pc = await _createPeerConnection(remoteUserId, widget.contact['full_name'] ?? widget.contact['name'] ?? 'User', widget.contact['avatar_url'] ?? widget.contact['avatar']);
    
    final desc = RTCSessionDescription(widget.initialOffer!['sdp'], widget.initialOffer!['type']);
    await pc.setRemoteDescription(desc);
    
    await _processPendingCandidates(remoteUserId);

    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': widget.isVideo,
      },
      'optional': [],
    };
    final answer = await pc.createAnswer(constraints);
    await pc.setLocalDescription(answer);

    _sendSignal('call-answer', {
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'roomId': widget.roomId,
      'isGroup': widget.isGroup,
      'groupId': widget.isGroup ? widget.contact['id'] : null,
    }, remoteUserId);
    
    setState(() => _inCall = true);
  }

  void _removeParticipant(String userId) {
    try {
       if (_remoteParticipants.containsKey(userId)) {
        final p = _remoteParticipants[userId]!;
        p.renderer.srcObject = null;
        p.renderer.dispose();
        setState(() {
          _remoteParticipants.remove(userId);
        });
      }
      
      final pc = _peerConnections[userId];
      if (pc != null) {
        pc.close();
        _peerConnections.remove(userId);
      }
    } catch (e) {
      debugPrint("Error removing participant $userId: $e");
    }
  }

  void _endCall({bool sendSignal = true, String? reason}) async {
    if (!mounted) return;

    String? formattedDuration;
    if (_callStartTime != null) {
      final duration = DateTime.now().difference(_callStartTime!);
      formattedDuration = "${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}";
    }

    setState(() {
      _callStatus = reason ?? 'Llamada finalizada';
      _inCall = false;
      _stopStatsTimer();
    });

    if (sendSignal) {
      final user = _supabase.auth.currentUser;
      final myId = user?.id;
      final myName = user?.userMetadata?['full_name'] ?? user?.email;
      final tenantId = user?.userMetadata?['tenant_id'];

      _peerConnections.keys.forEach((targetId) {
        _signaling.sendHangup(
          targetId, 
          myId!, 
          senderName: myName,
          status: _callStartTime != null ? 'completed' : 'rejected',
          duration: formattedDuration,
          tenantId: tenantId,
          isGroup: widget.isGroup
        );
      });
    }
    
    _localStream?.getTracks().forEach((t) => t.stop());
    _peerConnections.values.forEach((pc) {
      try {
        pc.close();
      } catch (e) {
        debugPrint("Error closing peer connection: $e");
      }
    });
    _remoteParticipants.values.forEach((p) => p.renderer.dispose());
    
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleMic() {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks()[0];
      audioTrack.enabled = !audioTrack.enabled;
      setState(() => _isMicMuted = !audioTrack.enabled);
    }
  }

  void _toggleVideo() {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        videoTracks[0].enabled = !videoTracks[0].enabled;
        setState(() => _isVideoMuted = !videoTracks[0].enabled);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final participants = _remoteParticipants.values.toList();
    final totalCount = participants.length + 1; // +1 for local

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: Stack(
          children: [
            // Participants Grid
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildGrid(participants, totalCount),
            ),

            // Incoming Call Overlay
            if (widget.isIncoming && !_inCall)
              _buildIncomingOverlay(),

            // Controls Bar
            _buildControlsBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<Participant> participants, int totalCount) {
    if (!_inCall && !widget.isIncoming) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAvatar(
              widget.contact['full_name'] ?? widget.contact['name'], 
              widget.contact['avatar_url'] ?? widget.contact['avatar'], 
              radius: 60,
              borderColor: const Color(0xFFEAB308).withOpacity(0.3),
            ),
            const SizedBox(height: 32),
            Text(
              (widget.contact['full_name'] ?? widget.contact['name'] ?? 'Neural Node').toUpperCase(),
              style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
            ),
            const SizedBox(height: 12),
            Text(
              _callStatus.toUpperCase(),
              style: GoogleFonts.outfit(
                color: const Color(0xFFEAB308), 
                fontWeight: FontWeight.w900, 
                fontSize: 10, 
                letterSpacing: 4,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int cols;
        int rows;
        
        if (totalCount == 1) {
          cols = 1; rows = 1;
        } else if (totalCount == 2) {
          cols = 2; rows = 1;
        } else if (totalCount <= 4) {
          cols = 2; rows = 2;
        } else if (totalCount <= 6) {
          cols = 3; rows = 2;
        } else {
          cols = 3; rows = (totalCount / 3).ceil();
        }

        // Calculate the best aspect ratio to fit everything without scrolling
        double itemWidth = (constraints.maxWidth - (cols - 1) * 12) / cols;
        double itemHeight = (constraints.maxHeight - (rows - 1) * 12) / rows;
        double aspectRatio = itemHeight > 0 ? (itemWidth / itemHeight) : 1.0;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          itemCount: totalCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildVideoCard("Tú", _localRenderer, _isVideoMuted, isLocal: true);
            }
            final p = participants[index - 1];
            return _buildVideoCard(p.name, p.renderer, !p.isVideoEnabled, avatar: p.avatar, signalQuality: p.signalQuality);
          },
        );
      },
    );
  }

  Widget _buildVideoCard(String name, RTCVideoRenderer renderer, bool muted, {bool isLocal = false, String? avatar, int signalQuality = 100}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Audio/Video Renderer (Must be always present for audio track playback)
            RTCVideoView(
              renderer,
              mirror: isLocal,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            // Avatar Overlay when video is muted
            if (muted)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF111111),
                  child: Center(child: _buildAvatar(name, avatar)),
                ),
              ),
            
            if (!isLocal) _buildSignalIndicator(signalQuality),
            
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  name.toUpperCase(),
                  style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalIndicator(int quality) {
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (index) {
            final barHeight = (index + 1) * 3.0;
            final isActive = quality >= (index + 1) * 25;
            return Container(
              margin: const EdgeInsets.only(left: 2),
              width: 3,
              height: barHeight,
              decoration: BoxDecoration(
                color: isActive ? Colors.green : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(1),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? name, String? url, {double radius = 40, Color? borderColor}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderColor != null ? Border.all(color: borderColor, width: 2) : null,
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFF080808),
        backgroundImage: url != null ? NetworkImage(url) : null,
        child: url == null ? Text(
          name?[0].toUpperCase() ?? 'N', 
          style: GoogleFonts.outfit(fontSize: radius * 0.8, color: Colors.white.withOpacity(0.1), fontWeight: FontWeight.w900)
        ) : null,
      ),
    );
  }

  Widget _buildIncomingOverlay() {


    return Container(
      color: pureBlack.withOpacity(0.98),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 160 * _pulseAnimation.value,
                      height: 160 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: saasYellow.withOpacity(0.3 * (1.5 - _pulseAnimation.value)),
                          width: 4,
                        ),
                      ),
                    );
                  },
                ),
                _buildAvatar(
                  widget.contact['full_name'] ?? widget.contact['name'], 
                  widget.contact['avatar_url'] ?? widget.contact['avatar'], 
                  radius: 80,
                  borderColor: saasYellow,
                ),
              ],
            ),
            const SizedBox(height: 48),
            Text(
              (widget.contact['full_name'] ?? widget.contact['name'] ?? 'Neural Node').toUpperCase(),
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
            ),
            const SizedBox(height: 8),
            Text(
              (widget.isGroup ? "CLUSTER CONNECTION REQUEST" : "INCOMING SECURE SIGNAL").toUpperCase(),
              style: GoogleFonts.outfit(
                color: saasYellow, 
                fontWeight: FontWeight.w900, 
                fontSize: 10, 
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 80),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildRoundButton(Icons.phone, Colors.green, _acceptCall, size: 84, glowColor: Colors.green.withOpacity(0.4)),
                const SizedBox(width: 64),
                _buildRoundButton(LucideIcons.phoneOff, industrialRed, () => _endCall(sendSignal: true), size: 84, glowColor: industrialRed.withOpacity(0.4)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildControlsBar() {
    if (widget.isIncoming && !_inCall) return const SizedBox();

    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF080808).withOpacity(0.8),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, spreadRadius: -10),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRoundButton(_isMicMuted ? LucideIcons.micOff : Icons.mic, 
                      _isMicMuted ? Colors.red : Colors.white.withOpacity(0.05), _toggleMic),
                  const SizedBox(width: 20),
                  _buildRoundButton(_isVideoMuted ? LucideIcons.videoOff : LucideIcons.video, 
                      _isVideoMuted ? Colors.red : Colors.white.withOpacity(0.05), _toggleVideo),
                  const SizedBox(width: 20),
                  _buildRoundButton(LucideIcons.phoneOff, const Color(0xFFFF0000), () => _endCall(sendSignal: true), isLarge: true, glowColor: Colors.red.withOpacity(0.3)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoundButton(IconData icon, Color bg, VoidCallback onTap, {bool isLarge = false, double? size, Color? glowColor}) {
    double s = size ?? (isLarge ? 72 : 56);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: glowColor != null ? [
            BoxShadow(color: glowColor, blurRadius: 20, spreadRadius: 0),
          ] : null,
        ),
        child: Icon(icon, color: Colors.white, size: s * 0.4),
      ),
    );
  }

  void _startStatsTimer() {
    _neuralTelemetryTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      for (var entry in _peerConnections.entries) {
        try {
          final stats = await entry.value.getStats();
          for (var report in stats) {
            if (report.type == 'candidate-pair' && report.values['state'] == 'succeeded') {
              final rtt = report.values['currentRoundTripTime'] ?? 0;
              final q = (100 - (rtt * 1000) / 2).clamp(0, 100).toInt();
              if (mounted) {
                setState(() {
                  if (_remoteParticipants.containsKey(entry.key)) {
                    _remoteParticipants[entry.key]!.signalQuality = q;
                  }
                });
              }
            }
          }
        } catch (e) {}
      }
    });
  }

  void _stopStatsTimer() {
    _neuralTelemetryTimer?.cancel();
    _neuralTelemetryTimer = null;
  }
}
