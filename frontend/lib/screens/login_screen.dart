import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:provider/provider.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/auth.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _screenName = TextEditingController();
  final _inviteCode = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
    // Web invite deep link: app.cine-track.com/signup?invite=CODE — jump straight
    // into sign-up with the code pre-filled.
    final invite = Uri.base.queryParameters['invite'];
    if (invite != null && invite.isNotEmpty) {
      _register = true;
      _inviteCode.text = invite;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _screenName.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  bool get _passwordOk {
    final p = _password.text;
    return p.length >= 12 &&
        p.contains(RegExp(r'[a-z]')) &&
        p.contains(RegExp(r'[A-Z]')) &&
        p.contains(RegExp(r'\d')) &&
        p.contains(RegExp(r'[^A-Za-z0-9]'));
  }

  /// Confirm field non-empty and equal to the password (register only).
  bool get _passwordsMatch =>
      _confirm.text.isNotEmpty && _password.text == _confirm.text;

  Future<void> _submit() async {
    // Guard signup: strong password AND both entries identical (prevents a typo
    // from creating an account you can't log back into).
    if (_register && (!_passwordOk || !_passwordsMatch)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    try {
      if (_register) {
        await auth.register(
          _email.text.trim(),
          _password.text,
          _screenName.text.trim(),
          inviteCode: _inviteCode.text.trim(),
        );
      } else {
        await auth.login(_email.text.trim(), _password.text);
      }
      // Credentials worked — signal the password manager to offer to save them.
      TextInput.finishAutofillContext();
    } catch (e) {
      setState(() => _error = _pretty('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _pretty(String e) =>
      e.replaceFirst(RegExp(r'^ApiException\(\d+\):\s*'), '');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final registrationEnabled = context
        .watch<AuthController>()
        .registrationEnabled;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            // Wrap the fields in an AutofillGroup so Flutter web emits a real
            // <form> with <input>s carrying `autocomplete` attributes — that's what
            // browser/extension password managers (Bitwarden, etc.) scan for. Without
            // it the canvas-rendered fields are invisible to them.
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.local_movies_rounded,
                    size: 56,
                    color: context.scheme.primary,
                  ),
                  const SizedBox(height: Insets.md),
                  Text(
                    'CINETRACK',
                    textAlign: TextAlign.center,
                    style: context.text.headlineMedium?.copyWith(
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    t.tagline,
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Insets.xxl),
                  TextField(
                    controller: _email,
                    decoration: InputDecoration(
                      labelText: t.fieldEmail,
                      prefixIcon: const Icon(Icons.mail_outline_rounded),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    // username first (what password managers key the login on) + email.
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                  ),
                  const SizedBox(height: Insets.md),
                  if (_register) ...[
                    TextField(
                      controller: _screenName,
                      decoration: InputDecoration(
                        labelText: t.fieldScreenName,
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                    TextField(
                      controller: _inviteCode,
                      decoration: InputDecoration(
                        labelText: t.inviteCode,
                        prefixIcon: const Icon(Icons.card_giftcard_rounded),
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                  ],
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    // "new-password" on sign-up lets managers suggest a strong one;
                    // "password" on login lets them fill the saved credential.
                    autofillHints: _register
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: t.fieldPassword,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                        tooltip: _obscure ? t.showPassword : t.hidePassword,
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_register) _strength(),
                  if (_register) ...[
                    const SizedBox(height: Insets.md),
                    TextField(
                      controller: _confirm,
                      obscureText: _obscure,
                      onSubmitted: (_) => _submit(),
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: t.fieldConfirmPassword,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        // Live match state: neutral while empty, green tick when equal,
                        // error tint + hint when they differ.
                        suffixIcon: _confirm.text.isEmpty
                            ? null
                            : Icon(
                                _passwordsMatch
                                    ? Icons.check_circle_rounded
                                    : Icons.error_outline_rounded,
                                color: _passwordsMatch
                                    ? context.colors.seen
                                    : context.scheme.error,
                              ),
                        errorText:
                            (_confirm.text.isNotEmpty && !_passwordsMatch)
                            ? t.passwordsDontMatch
                            : null,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: Insets.md),
                    Text(
                      _error!,
                      style: TextStyle(color: context.scheme.error),
                    ),
                  ],
                  const SizedBox(height: Insets.lg),
                  FilledButton(
                    onPressed:
                        (_busy ||
                            (_register && (!_passwordOk || !_passwordsMatch)))
                        ? null
                        : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_register ? t.createAccount : t.logIn),
                  ),
                  // Hide the sign-up toggle when the server is invite-only — unless we
                  // arrived via an invite deep link (_register already true), so those
                  // users can still switch back to log in.
                  if (registrationEnabled || _register)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _confirm.clear();
                              _error = null;
                            }),
                      child: Text(
                        _register ? t.haveAccountLogIn : t.newHereCreate,
                      ),
                    ),
                  if (!_register)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            ),
                      child: Text(t.forgotPassword),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _strength() {
    final t = AppLocalizations.of(context);
    final p = _password.text;
    final checks = <(String, bool)>[
      (t.pw12chars, p.length >= 12),
      (t.pwUppercase, p.contains(RegExp(r'[A-Z]'))),
      (t.pwLowercase, p.contains(RegExp(r'[a-z]'))),
      (t.pwNumber, p.contains(RegExp(r'\d'))),
      (t.pwSpecial, p.contains(RegExp(r'[^A-Za-z0-9]'))),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Insets.md),
      child: Wrap(
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
      ),
    );
  }
}
