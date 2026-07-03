import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'show_card.dart';

/// A grid delegate sized so each cell holds a full [ShowCard] (2:3 poster + the
/// fixed-height caption) with NO overflow — computed from the real cell width.
SliverGridDelegate posterGridDelegate(
  BuildContext context, {
  double hPadding = Insets.lg,
  double crossSpacing = Insets.md,
  double mainSpacing = Insets.lg,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final columns = Breakpoints.posterColumns(width);
  final cellWidth = (width - hPadding * 2 - crossSpacing * (columns - 1)) / columns;
  final cellHeight = cellWidth / kPosterAspect + Insets.sm + kCardCaptionHeight;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: crossSpacing,
    mainAxisSpacing: mainSpacing,
    mainAxisExtent: cellHeight,
  );
}
