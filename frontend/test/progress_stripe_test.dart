import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/design/app_colors.dart';
import 'package:frontend/design/app_theme.dart';
import 'package:frontend/widgets/badges.dart';

/// The stripe on a poster card carries one bit of meaning by colour: amber means
/// there is still something to watch, mint means you're done. Comparing bar
/// LENGTHS across a rail is the thing this saves you from, so the colour rule is
/// the point — not decoration.
void main() {
  Future<LinearProgressIndicator?> pump(WidgetTester tester, double value, {Brightness brightness = Brightness.dark}) async {
    await tester.pumpWidget(MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(body: Stack(children: [ProgressStripe(value: value)])),
    ));
    final found = find.byType(LinearProgressIndicator);
    if (found.evaluate().isEmpty) return null;
    return tester.widget<LinearProgressIndicator>(found);
  }

  Color barColor(LinearProgressIndicator bar) => bar.valueColor!.value!;

  testWidgets('a part-watched show is amber', (tester) async {
    final bar = await pump(tester, 0.5);
    expect(bar, isNotNull);
    expect(barColor(bar!), Brand.primary);
  });

  testWidgets('a fully-watched show is the seen mint', (tester) async {
    final bar = await pump(tester, 1.0);
    expect(barColor(bar!), AppColors.dark.seen);
  });

  testWidgets('one episode short of the end is still amber', (tester) async {
    // The boundary this rule lives or dies on: 11 of 12 must not read as done.
    final bar = await pump(tester, 11 / 12);
    expect(barColor(bar!), Brand.primary);
  });

  testWidgets('over-counting still reads as done, not as amber', (tester) async {
    // Watch rows can outnumber the catalog when episodes are removed, so the
    // value arrives above 1. Clamped, that is finished.
    final bar = await pump(tester, 1.4);
    expect(barColor(bar!), AppColors.dark.seen);
    expect(bar.value, 1.0, reason: 'the bar must not overflow its track');
  });

  testWidgets('nothing watched draws no stripe at all', (tester) async {
    expect(await pump(tester, 0), isNull, reason: 'an empty bar would be noise on every unstarted card');
  });

  testWidgets('the same rule holds on the light theme', (tester) async {
    final partial = await pump(tester, 0.3, brightness: Brightness.light);
    expect(barColor(partial!), Brand.primary, reason: 'the amber is the brand one in both themes');
    final full = await pump(tester, 1.0, brightness: Brightness.light);
    expect(barColor(full!), AppColors.light.seen, reason: 'mint darkens for contrast on paper');
  });
}
