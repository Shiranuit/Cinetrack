import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';

/// Single source of truth for the password policy, shared by sign-up, reset, and
/// change-password so their rules can never drift apart: 12+ chars with a lower,
/// upper, digit and special character.
bool isStrongPassword(String p) =>
    p.length >= 12 &&
    p.contains(RegExp(r'[a-z]')) &&
    p.contains(RegExp(r'[A-Z]')) &&
    p.contains(RegExp(r'\d')) &&
    p.contains(RegExp(r'[^A-Za-z0-9]'));

/// Live checklist of the [isStrongPassword] requirements, each ticking green as
/// it's met. Mirrors what the sign-up screen shows.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = password;
    final checks = <(String, bool)>[
      (t.pw12chars, p.length >= 12),
      (t.pwUppercase, p.contains(RegExp(r'[A-Z]'))),
      (t.pwLowercase, p.contains(RegExp(r'[a-z]'))),
      (t.pwNumber, p.contains(RegExp(r'\d'))),
      (t.pwSpecial, p.contains(RegExp(r'[^A-Za-z0-9]'))),
    ];
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.xs,
      children: [
        for (final (label, ok) in checks)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 15,
                color: ok
                    ? context.colors.seen
                    : context.scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: context.text.labelSmall?.copyWith(
                  color: ok
                      ? context.colors.seen
                      : context.scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Insets.sm),
            ],
          ),
      ],
    );
  }
}
