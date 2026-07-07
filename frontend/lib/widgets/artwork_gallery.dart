import 'package:flutter/material.dart';

import '../api/models.dart';
import '../design/tokens.dart';
import 'net_image.dart';

/// Push a full-screen, swipeable, zoomable gallery of a show/movie's artworks.
/// [future] is loaded inside the gallery so the tap gives immediate feedback.
void openArtworkGallery(BuildContext context, Future<List<Artwork>> future, {int initialIndex = 0}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ArtworkGallery(future: future, initialIndex: initialIndex),
  ));
}

/// Full-screen artwork viewer: a horizontal carousel (swipe to cycle) where each
/// image can be pinch/scroll-zoomed and dragged. Swiping is disabled while an image
/// is zoomed in (zoom back out to move on), so panning never fights the page swipe.
class ArtworkGallery extends StatefulWidget {
  const ArtworkGallery({super.key, required this.future, this.initialIndex = 0});
  final Future<List<Artwork>> future;
  final int initialIndex;

  @override
  State<ArtworkGallery> createState() => _ArtworkGalleryState();
}

class _ArtworkGalleryState extends State<ArtworkGallery> {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  final _transform = TransformationController();
  List<Artwork>? _arts;
  Object? _error;
  late int _index = widget.initialIndex;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    widget.future.then((a) {
      if (mounted) setState(() => _arts = a);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  void _onTransform() {
    final z = _transform.value.getMaxScaleOnAxis() > 1.05;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  void _go(int delta) {
    final len = _arts?.length ?? 0;
    final target = _index + delta;
    if (target < 0 || target >= len) return;
    // Reset any zoom so the (programmatic) page animation isn't blocked while zoomed.
    _transform.value = Matrix4.identity();
    _zoomed = false;
    _page.animateToPage(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _body()),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(Insets.sm),
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) => CircleAvatar(
        radius: 22,
        backgroundColor: Colors.black54,
        child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 28),
          onPressed: onTap,
        ),
      );

  Widget _body() {
    if (_error != null) {
      return const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48));
    }
    final arts = _arts;
    if (arts == null) return const Center(child: CircularProgressIndicator());
    if (arts.isEmpty) {
      return const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 48));
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _page,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          itemCount: arts.length,
          onPageChanged: (i) {
            _transform.value = Matrix4.identity(); // reset zoom when switching images
            setState(() => _index = i);
          },
          itemBuilder: (_, i) {
            final img = Center(
              child: NetImage(url: arts[i].imageUrl, fit: BoxFit.contain, icon: Icons.image_outlined),
            );
            // Only the current page is interactive; neighbours stay at identity so a
            // half-swiped page never appears zoomed. Panning is enabled only once
            // zoomed, so at 1x a horizontal drag swipes the carousel instead.
            if (i != _index) return img;
            return InteractiveViewer(
              transformationController: _transform,
              panEnabled: _zoomed,
              minScale: 1,
              maxScale: 5,
              child: img,
            );
          },
        ),
        // Prev / next arrows (essential on web/desktop where there's no swipe).
        if (_index > 0)
          Positioned(
            left: Insets.sm,
            top: 0,
            bottom: 0,
            child: Center(child: _navButton(Icons.chevron_left_rounded, () => _go(-1))),
          ),
        if (_index < arts.length - 1)
          Positioned(
            right: Insets.sm,
            top: 0,
            bottom: 0,
            child: Center(child: _navButton(Icons.chevron_right_rounded, () => _go(1))),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Insets.md),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.xs),
                    child: Text('${_index + 1} / ${arts.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
