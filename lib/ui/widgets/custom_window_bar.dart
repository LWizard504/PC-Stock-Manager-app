import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lucide_icons/lucide_icons.dart';

class CustomWindowBar extends StatefulWidget implements PreferredSizeWidget {
  final Color backgroundColor;
  final bool showLogo;

  const CustomWindowBar({
    super.key,
    this.backgroundColor = Colors.transparent,
    this.showLogo = false,
  });

  @override
  State<CustomWindowBar> createState() => _CustomWindowBarState();

  @override
  Size get preferredSize => const Size.fromHeight(40);
}

class _CustomWindowBarState extends State<CustomWindowBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximizedState() async {
    final max = await windowManager.isMaximized();
    if (mounted) {
      setState(() {
        _isMaximized = max;
      });
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = true;
      });
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: widget.backgroundColor,
      child: Row(
        children: [
          // Drag area
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                windowManager.startDragging();
              },
              onDoubleTap: () async {
                bool isMax = await windowManager.isMaximized();
                if (isMax) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Row(
                  children: [
                    if (widget.showLogo) ...[
                      const Icon(LucideIcons.boxes, size: 16, color: Color(0xFFE50914)),
                      const SizedBox(width: 8),
                      const Text(
                        "StockManager",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Window action buttons
          _AnimatedWindowButton(
            icon: LucideIcons.minus,
            hoverColor: Colors.blueAccent.withOpacity(0.2),
            iconColor: Colors.blueAccent,
            onPressed: () => windowManager.minimize(),
            tooltip: "Minimizar",
          ),
          _AnimatedWindowButton(
            icon: _isMaximized ? LucideIcons.copy : LucideIcons.square,
            hoverColor: Colors.greenAccent.withOpacity(0.2),
            iconColor: Colors.greenAccent,
            onPressed: () async {
              bool isMax = await windowManager.isMaximized();
              if (isMax) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
            tooltip: _isMaximized ? "Restaurar" : "Maximizar",
          ),
          _AnimatedWindowButton(
            icon: LucideIcons.x,
            hoverColor: Colors.redAccent.withOpacity(0.2),
            iconColor: Colors.redAccent,
            onPressed: () => windowManager.close(),
            tooltip: "Cerrar",
            isCloseButton: true,
          ),
        ],
      ),
    );
  }
}

class _AnimatedWindowButton extends StatefulWidget {
  final IconData icon;
  final Color hoverColor;
  final Color iconColor;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isCloseButton;

  const _AnimatedWindowButton({
    required this.icon,
    required this.hoverColor,
    required this.iconColor,
    required this.onPressed,
    required this.tooltip,
    this.isCloseButton = false,
  });

  @override
  State<_AnimatedWindowButton> createState() => _AnimatedWindowButtonState();
}

class _AnimatedWindowButtonState extends State<_AnimatedWindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isCloseButton 
        ? const Color(0xFFE50914) 
        : widget.iconColor;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: 48,
            height: 40,
            decoration: BoxDecoration(
              color: _isHovered 
                  ? (widget.isCloseButton 
                      ? const Color(0xFFE50914).withOpacity(0.15) 
                      : widget.hoverColor)
                  : Colors.transparent,
            ),
            child: Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: _isHovered ? 1.15 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    widget.icon,
                    size: 14,
                    color: _isHovered ? activeColor : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
