import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/selection.dart';
import 'badges.dart';
import 'poster.dart';

/// Height reserved for a card's caption (title + optional subtitle). Fixed so
/// cards never overflow their rail/grid cell.
const double kCardCaptionHeight = 44;

/// The canonical show/movie tile: poster + title (+ optional subtitle, favorite
/// heart, progress). Used in rails and grids.
///
/// When [selection] is set AND the card is under a [SelectionScope], the card joins
/// multi-select: long-press enters selection mode and selects it, taps toggle it
/// while a selection is active (otherwise [onTap] runs), and a checkbox overlay +
/// tint reflect its state.
class ShowCard extends StatelessWidget {
  const ShowCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.onTap,
    this.onLongPress,
    this.subtitle,
    this.favorite = false,
    this.progress = 0,
    this.heroTag,
    this.selection,
    this.inLibrary = false,
  });

  final String title;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? subtitle;
  final bool favorite;
  final double progress;
  final Object? heroTag;

  /// Identity for multi-select. Null (or no [SelectionScope] above) → the card is
  /// a plain tile and ignores selection entirely.
  final SelItem? selection;

  /// Whether this title is already in the viewer's library. When true (only set in
  /// Discover) the card gets a sky-blue "In library" pill + border.
  final bool inLibrary;

  @override
  Widget build(BuildContext context) {
    // `of` registers a dependency, so the card rebuilds when the selection changes.
    final controller = selection == null ? null : SelectionScope.of(context);
    final selecting = controller?.active ?? false;
    final selected = controller != null && selection != null && controller.contains(selection!.kind, selection!.id);

    // In-library marker (Discover only): a sky-blue "In library" pill + border,
    // deliberately different from the amber selection ring. The pill STAYS even while
    // the card is selected (it renders under the amber selection fill, so a selected
    // card still reads as "in library"); the blue border yields to the amber selection
    // border when this card is selected.
    final showPill = inLibrary;
    final showLibBorder = inLibrary && !selected;

    void handleTap() {
      if (selecting && controller != null && selection != null) {
        controller.toggle(selection!);
      } else {
        onTap?.call();
      }
    }

    void handleLongPress() {
      // Long-press / right-click: enter selection mode when idle, otherwise toggle
      // this card (so right-click can DESELECT too, matching left-click once a
      // selection is active). Falls back to the card's own long-press only when
      // it isn't selectable.
      if (controller != null && selection != null) {
        if (controller.active) {
          controller.toggle(selection!);
        } else {
          controller.select(selection!);
        }
      } else {
        onLongPress?.call();
      }
    }

    // Long-press is gated by POINTER KIND, not platform: touch/stylus (real mobile
    // and mobile-browser / device-emulation) enters selection, while a desktop
    // mouse uses right-click (onSecondaryTap) instead — a mouse press+drag would
    // otherwise get caught by the long-press recognizer and starve a rail's
    // horizontal drag. (The old `kIsWeb` guard wrongly killed long-press on mobile
    // web too.)
    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(
            supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
          ),
          (r) => r.onLongPress = handleLongPress,
        ),
      },
      child: InkWell(
        onTap: handleTap,
        onSecondaryTap: handleLongPress,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
          Poster(
            url: imageUrl,
            heroTag: heroTag,
            overlay: Stack(
              fit: StackFit.expand,
              children: [
                if (favorite)
                  Positioned(
                    top: Insets.xs,
                    right: Insets.xs,
                    child: Icon(Icons.favorite, size: 18, color: context.colors.favorite),
                  ),
                ProgressStripe(value: progress),
                if (showLibBorder)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.colors.library, width: 3),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                  ),
                // Pill BEFORE the selection fill below, so the amber selection tint
                // layers over it and the pill stays visible on a selected card.
                if (showPill)
                  const Positioned(top: Insets.xs, left: Insets.xs, child: _LibraryPill()),
                if (selected)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.scheme.primary.withValues(alpha: 0.28),
                      border: Border.all(color: context.scheme.primary, width: 3),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                  ),
                if (selecting)
                  Positioned(
                    top: Insets.xs,
                    // Sit top-right when a pill occupies the top-left (Discover cards
                    // carry no favorite heart there), so the dot never hides the pill.
                    left: inLibrary ? null : Insets.xs,
                    right: inLibrary ? Insets.xs : null,
                    child: _SelectDot(selected: selected),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Insets.sm),
          SizedBox(
            height: kCardCaptionHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: subtitle == null ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// "In library" chip overlaid on a Discover poster (check icon + short label).
class _LibraryPill extends StatelessWidget {
  const _LibraryPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Insets.xs, 2, Insets.sm, 2),
      decoration: BoxDecoration(
        color: context.colors.library,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            AppLocalizations.of(context).inLibrary,
            style: context.text.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// The circular checkbox shown top-left of a card while a selection is active.
class _SelectDot extends StatelessWidget {
  const _SelectDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? context.scheme.primary : context.scheme.surface.withValues(alpha: 0.75),
        shape: BoxShape.circle,
        border: Border.all(color: selected ? context.scheme.primary : context.scheme.onSurface.withValues(alpha: 0.6), width: 2),
      ),
      child: Icon(
        selected ? Icons.check_rounded : null,
        size: 16,
        color: context.scheme.onPrimary,
      ),
    );
  }
}
