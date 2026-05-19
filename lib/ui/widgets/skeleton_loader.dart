import 'package:flutter/material.dart';

class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
  });

  // Pulse skeleton for a standard text line
  static Widget text({double width = double.infinity, double height = 16.0}) {
    return SkeletonLoader(width: width, height: height, borderRadius: 4.0);
  }

  // Pulse skeleton for a card shape
  static Widget card({double width = double.infinity, double height = 120.0}) {
    return SkeletonLoader(width: width, height: height, borderRadius: 16.0);
  }

  // Pulse skeleton for a table row simulation
  static Widget table({int rows = 5, int columns = 5}) {
    return Column(
      children: List.generate(rows, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(columns, (colIndex) {
              final widths = [100.0, 150.0, 120.0, 80.0, 110.0];
              final w = widths[colIndex % widths.length];
              return SkeletonLoader(
                width: w,
                height: 20.0,
                borderRadius: 6.0,
              );
            }),
          ),
        );
      }),
    );
  }

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0.05, end: 0.18).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}
