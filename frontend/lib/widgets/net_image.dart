import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// A cached, retrying network image with a consistent placeholder/fallback.
/// Caching means a successful load survives rebuilds; transient failures fall
/// back to the placeholder instead of a broken image, and re-resolve on retry.
class NetImage extends StatelessWidget {
  const NetImage({super.key, required this.url, this.fit = BoxFit.cover, this.icon = Icons.tv, this.fallback});
  final String? url;
  final BoxFit fit;
  final IconData icon;

  /// Optional custom widget shown when there's no image / a load failure.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final fallback = this.fallback ??
        ColoredBox(
          color: context.colors.posterBg,
          child: Center(child: Icon(icon, color: context.scheme.onSurfaceVariant)),
        );
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => ColoredBox(color: context.colors.posterBg),
      errorWidget: (_, _, _) => fallback,
    );
  }
}
