import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// Circular user avatar with initials fallback.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.url, this.radius = 18});
  final String name;
  final String? url;
  final double radius;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.scheme.primary.withValues(alpha: 0.22),
      // Persistent disk cache (survives restarts), same as posters via NetImage.
      foregroundImage: (url != null && url!.isNotEmpty) ? CachedNetworkImageProvider(url!) : null,
      child: Text(
        _initials,
        style: TextStyle(
          color: context.scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
