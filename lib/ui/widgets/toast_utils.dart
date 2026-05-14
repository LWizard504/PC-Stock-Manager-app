import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ToastUtils {
  static void showPromiseToast(BuildContext context, {
    required String message,
    required Future<void> promise,
    required String successMessage,
    required String errorMessage,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final overlay = Overlay.of(context);
      final overlayEntry = OverlayEntry(
        builder: (context) => _PromiseToastWidget(
          message: message,
          promise: promise,
          successMessage: successMessage,
          errorMessage: errorMessage,
        ),
      );

      overlay.insert(overlayEntry);
      
      try {
        await promise;
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        await Future.delayed(const Duration(seconds: 3));
      } finally {
        if (overlayEntry.mounted) overlayEntry.remove();
      }
    });
  }

  static void showCustomToast(BuildContext context, String message, {bool isError = false}) {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isError ? Colors.red.withOpacity(0.5) : Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                isError ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
                color: isError ? Colors.red : Colors.greenAccent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromiseToastWidget extends StatefulWidget {
  final String message;
  final Future<void> promise;
  final String successMessage;
  final String errorMessage;

  const _PromiseToastWidget({
    required this.message,
    required this.promise,
    required this.successMessage,
    required this.errorMessage,
  });

  @override
  State<_PromiseToastWidget> createState() => _PromiseToastWidgetState();
}

class _PromiseToastWidgetState extends State<_PromiseToastWidget> {
  bool? _isSuccess;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _handlePromise();
  }

  void _handlePromise() async {
    try {
      await widget.promise;
      if (mounted) setState(() => _isSuccess = true);
    } catch (e) {
      if (mounted) setState(() {
        _isSuccess = false;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isSuccess == null 
                ? Colors.white10 
                : (_isSuccess! ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3)),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black54, blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: _isSuccess == null
                  ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.red)
                  : Icon(
                      _isSuccess! ? LucideIcons.check : LucideIcons.x,
                      color: _isSuccess! ? Colors.greenAccent : Colors.redAccent,
                      size: 20,
                    ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isSuccess == null 
                        ? widget.message 
                        : (_isSuccess! ? widget.successMessage : widget.errorMessage),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    if (_isSuccess == false && _errorText != null)
                      Text(
                        _errorText!,
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().slideX(begin: 1, end: 0, curve: Curves.easeOutBack),
      ),
    );
  }
}
