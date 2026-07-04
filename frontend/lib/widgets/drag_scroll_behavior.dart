import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Makes a horizontal scrollable draggable with the **mouse** on web/desktop.
///
/// Uses a dedicated horizontal-drag recognizer restricted to mouse pointers and
/// drives the [ScrollController] from its updates:
///  * A real gesture recognizer (not a raw `Listener`) claims the pointer, so the
///    list tracks the cursor continuously instead of jumping only on release.
///  * Mouse-only, so touch and trackpad keep the child list's native physics
///    (the phone is unaffected).
///
/// Depends on `preventNativeDrag()` (called in `main`) — otherwise the browser
/// starts a native image-drag and withholds the move events this relies on.
class MouseDragScroll extends StatefulWidget {
  const MouseDragScroll({super.key, required this.builder});

  /// Builds the scrollable, wiring in the provided controller.
  final Widget Function(BuildContext context, ScrollController controller) builder;

  @override
  State<MouseDragScroll> createState() => _MouseDragScrollState();
}

class _MouseDragScrollState extends State<MouseDragScroll> {
  final ScrollController _controller = ScrollController();
  bool _dragging = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_controller.hasClients) return;
    if (!_dragging) setState(() => _dragging = true);
    final next = (_controller.offset - d.delta.dx).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.jumpTo(next);
  }

  void _stop() {
    if (_dragging) setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(
              supportedDevices: const {PointerDeviceKind.mouse},
            ),
            (r) => r
              ..onUpdate = _onUpdate
              ..onEnd = ((_) => _stop())
              ..onCancel = _stop,
          ),
        },
        child: widget.builder(context, _controller),
      ),
    );
  }
}
