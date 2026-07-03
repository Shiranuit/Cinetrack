import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'net_image.dart';

/// A poster image in the canonical 2:3 aspect ratio with a graceful placeholder.
/// `overlay` is stacked on top (badges, progress, scrim, etc.).
class Poster extends StatelessWidget {
  const Poster({super.key, this.url, this.radius = Radii.md, this.overlay, this.heroTag});

  final String? url;
  final double radius;
  final Widget? overlay;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    Widget img = AspectRatio(
      aspectRatio: kPosterAspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _image(context),
          ?overlay,
        ],
      ),
    );
    if (heroTag != null) img = Hero(tag: heroTag!, child: img);
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
  }

  Widget _image(BuildContext context) => NetImage(url: url, icon: Icons.movie_outlined);
}
