import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class _Particle {
  double x, y, vx, vy, size, alpha;
  bool isAccent;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.alpha,
    required this.isAccent,
  });
}

class ParticleBackground extends StatefulWidget {
  final Color primaryColor;
  final Color secondaryColor;

  static const Color defaultPrimary = Color(0xFFFFFFFF);
  static const Color defaultSecondary = Color(0xFF6366F1);

  const ParticleBackground({
    super.key,
    this.primaryColor = defaultPrimary,
    this.secondaryColor = defaultSecondary,
  });

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Particle> _particles = [];
  Offset _mousePos = const Offset(-1000, -1000);
  bool _hasMouse = false;
  Size _canvasSize = Size.zero;

  void _initParticles(Size size) {
    _particles.clear();
    final rand = Random();
    final count = min(200, (size.width * size.height / 6000).floor());
    for (int i = 0; i < count; i++) {
      _particles.add(_Particle(
        x: rand.nextDouble() * size.width,
        y: rand.nextDouble() * size.height,
        vx: rand.nextDouble() * 0.3 - 0.15,
        vy: rand.nextDouble() * 0.3 - 0.15,
        size: rand.nextDouble() * 1.2 + 0.3,
        alpha: rand.nextDouble() * 0.27 + 0.08,
        isAccent: rand.nextDouble() < 0.1,
      ));
    }
    _canvasSize = size;
  }

  void _updateParticles(Duration elapsed) {
    if (_particles.isEmpty) return;
    final mx = _mousePos.dx;
    final my = _mousePos.dy;
    final w = _canvasSize.width;
    final h = _canvasSize.height;
    final cx = w / 2;
    final cy = h / 2;

    for (final p in _particles) {
      if (_hasMouse && mx >= 0 && my >= 0 && mx <= w && my <= h) {
        final dx = mx - p.x;
        final dy = my - p.y;
        final dist = sqrt(dx * dx + dy * dy);
        final force = max(0.0, 1 - dist / 250) * 0.4;
        p.x -= dx * force * 0.008;
        p.y -= dy * force * 0.008;

        final driftX = (mx - cx) / w;
        final driftY = (my - cy) / h;
        p.x += driftX * 0.15;
        p.y += driftY * 0.15;
      }

      p.x += p.vx;
      p.y += p.vy;

      if (p.x < 0) {
        p.x += w;
      } else if (p.x > w) {
        p.x -= w;
      }
      if (p.y < 0) {
        p.y += h;
      } else if (p.y > h) {
        p.y -= h;
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_updateParticles);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_particles.isEmpty && size.width > 0 && size.height > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _initParticles(size);
          });
        }
        return MouseRegion(
          onHover: (e) {
            _mousePos = e.localPosition;
            if (!_hasMouse) _hasMouse = true;
          },
          onExit: (_) {
            _hasMouse = false;
            _mousePos = const Offset(-1000, -1000);
          },
          child: GestureDetector(
            onPanUpdate: (d) {
              _mousePos = d.localPosition;
              _hasMouse = true;
            },
            child: CustomPaint(
              painter: _ParticlePainter(
                particles: _particles,
                primaryColor: widget.primaryColor,
                secondaryColor: widget.secondaryColor,
              ),
              size: size,
            ),
          ),
        );
      },
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final Color primaryColor;
  final Color secondaryColor;

  _ParticlePainter({
    required this.particles,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..style = PaintingStyle.fill;
      if (p.isAccent) {
        paint.color = secondaryColor.withOpacity(p.alpha * 0.8);
      } else {
        paint.color = primaryColor.withOpacity(p.alpha);
      }
      canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
