import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Fades + rises its child in, optionally after [delay]. Used to stagger the
/// reveal of content rows on load for a polished entrance.
class Reveal extends StatefulWidget {
  const Reveal({super.key, this.delay = Duration.zero, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.medium);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: _c.value,
        child: Transform.translate(offset: Offset(0, (1 - _c.value) * 18), child: child),
      ),
      child: widget.child,
    );
  }
}
