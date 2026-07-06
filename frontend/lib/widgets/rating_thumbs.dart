import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../l10n/app_localizations.dart';

/// The labeled 1..5 rating scale, rendered as thumbs:
///   1 double thumbs down · 2 thumbs down · 3 mixed (OK) · 4 thumbs up · 5 double up.
/// A labeled scale sidesteps the "what does 7/10 mean" ambiguity of the old stars.

/// Localized label for a rating level (Hate it / Dislike it / OK / Like it / Love it).
String ratingLevelLabel(BuildContext context, int level) {
  final t = AppLocalizations.of(context);
  return switch (level) {
    1 => t.rateHate,
    2 => t.rateDislike,
    3 => t.rateOk,
    4 => t.rateLike,
    5 => t.rateLove,
    _ => '',
  };
}

/// Valence colour for a level: down = red, middle = neutral, up = green. The
/// single-vs-double glyph carries the intensity (1 vs 2, 4 vs 5).
Color _levelColor(BuildContext context, int level) => switch (level) {
      1 || 2 => context.scheme.error,
      3 => context.scheme.onSurfaceVariant,
      _ => context.colors.seen,
    };

/// The glyph for a level. Levels 1 and 5 are a pair of thumbs (the extremes),
/// arranged as a compact diagonal cluster so the pair keeps a roughly square
/// footprint and fills its circle like the single-thumb levels do. In the pair each
/// thumb is stroked with an [outline] colour (rendered as text so the icon glyph
/// gets a real border), so where the two overlap the front one draws a crisp edge
/// over the back one instead of merging into a single blob.
Widget ratingLevelGlyph(int level, double size, Color color, {Color? outline}) {
  Widget plain(IconData i, double s) => Icon(i, size: s, color: color);

  Widget stroked(IconData i, double s) {
    if (outline == null) return plain(i, s);
    final ch = String.fromCharCode(i.codePoint);
    final base = TextStyle(fontFamily: i.fontFamily, package: i.fontPackage, fontSize: s, height: 1.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(ch, style: base.copyWith(foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = outline)),
        Text(ch, style: base.copyWith(color: color)),
      ],
    );
  }

  // Tightly clustered like the Netflix double-thumb (values tuned in
  // tools/rating-thumbs-playground.html): two thumbs at fixed offsets, the outline
  // keeping them readable where they overlap. Which one sits ON TOP flips between
  // up and down, since the glyphs point opposite ways and the wrong order occludes
  // the second thumb.
  Widget pair(IconData i, {required bool aOnTop}) {
    final s = size * 0.72;
    final a = Positioned(left: size * 0.13, bottom: size * 0.17, child: stroked(i, s));
    final b = Positioned(left: size * 0.28, bottom: size * 0.28, child: stroked(i, s));
    return SizedBox(
      width: size,
      height: size,
      // Later child is drawn on top.
      child: Stack(children: aOnTop ? [b, a] : [a, b]),
    );
  }

  return switch (level) {
    1 => pair(Icons.thumb_down, aOnTop: false),
    2 => plain(Icons.thumb_down, size),
    3 => plain(Icons.thumbs_up_down, size),
    4 => plain(Icons.thumb_up, size),
    5 => pair(Icons.thumb_up, aOnTop: true),
    _ => const SizedBox.shrink(),
  };
}

/// A compact, read-only badge for one level (used for a show's community average).
class RatingThumbBadge extends StatelessWidget {
  const RatingThumbBadge({super.key, required this.level, this.size = 16});
  final int level; // 1..5
  final double size;
  @override
  Widget build(BuildContext context) =>
      ratingLevelGlyph(level, size, _levelColor(context, level), outline: context.scheme.surface);
}

/// The 1..5 thumbs rating control: the five thumbs spread evenly across the full
/// width (so it lines up with the action bar above it), with the label BELOW the
/// currently selected thumb. Before you rate, a centred "Rate this show" prompt
/// occupies that same line. Tapping a level sets it; tapping it again clears it.
class RatingThumbs extends StatelessWidget {
  const RatingThumbs({super.key, required this.value, required this.onRate, this.size = 30});
  final int? value; // 1..5, null = unrated
  final void Function(int? rating) onRate;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              Expanded(
                child: Center(
                  child: _LevelButton(
                    level: i,
                    selected: value == i,
                    size: size,
                    onTap: () => onRate(i == value ? null : i),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // Reserved label line: the selected level's label under its own thumb, or a
        // centred prompt when nothing is chosen yet. Fixed height so the layout
        // never jumps between the two states.
        SizedBox(
          height: 22,
          child: value == null
              ? Center(
                  child: Text(AppLocalizations.of(context).rateThisShow,
                      style: context.text.titleSmall?.copyWith(color: context.scheme.onSurfaceVariant)),
                )
              : Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Expanded(
                        child: Center(
                          child: value == i
                              // Allow the (wider) label to spill past its 1/5 slot,
                              // centred under the thumb, so it stays readable.
                              ? OverflowBox(
                                  maxWidth: double.infinity,
                                  child: Text(ratingLevelLabel(context, i),
                                      softWrap: false,
                                      style: context.text.titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w700, color: _levelColor(context, i))),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LevelButton extends StatelessWidget {
  const _LevelButton({required this.level, required this.selected, required this.size, required this.onTap});
  final int level;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _levelColor(context, level);
    // Every button gets a circle so the five read as distinct chips; the selected
    // one fills with its valence colour and takes a ring.
    final bg = selected ? accent.withValues(alpha: 0.20) : context.scheme.onSurfaceVariant.withValues(alpha: 0.10);
    // The opaque colour of the circle's interior (bg composited over the surface),
    // used as the outline so overlapping thumbs read as two separate shapes.
    final interior = Color.alphaBlend(bg, context.scheme.surface);
    // The fill MUST be fully opaque, otherwise the front thumb shows the one behind
    // it. Keep the muted look by compositing the tone over the circle interior
    // rather than using a translucent colour.
    final glyphColor =
        selected ? accent : Color.alphaBlend(context.scheme.onSurfaceVariant.withValues(alpha: 0.7), interior);
    final diameter = size + 14;
    return Tooltip(
      message: ratingLevelLabel(context, level),
      child: InkResponse(
        onTap: onTap,
        radius: diameter * 0.62,
        child: Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: selected ? Border.all(color: accent, width: 1.5) : null,
          ),
          child: ratingLevelGlyph(level, size, glyphColor, outline: interior),
        ),
      ),
    );
  }
}
