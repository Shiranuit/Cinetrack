import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';

/// Complete a password reset from an emailed token (opened via the web deep link
/// `/reset-password?token=...`). On success, hands control back via [onDone].
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token, this.onDone});
  final String token;
  final VoidCallback? onDone;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _done = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _ok {
    final p = _password.text;
    return p.length >= 12 &&
        p.contains(RegExp(r'[a-z]')) &&
        p.contains(RegExp(r'[A-Z]')) &&
        p.contains(RegExp(r'\d')) &&
        p.contains(RegExp(r'[^A-Za-z0-9]')) &&
        _confirm.text == p;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().resetPassword(widget.token, _password.text);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst(RegExp(r'^ApiException\(\d+\):\s*'), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.resetPassword)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _done
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: Insets.md),
                    Text(t.passwordUpdated, textAlign: TextAlign.center),
                    const SizedBox(height: Insets.lg),
                    FilledButton(onPressed: () => widget.onDone?.call(), child: Text(t.logIn)),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: t.newPassword,
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: Insets.md),
                      TextField(
                        controller: _confirm,
                        obscureText: _obscure,
                        onSubmitted: (_) => _ok ? _submit() : null,
                        decoration: InputDecoration(
                          labelText: t.fieldConfirmPassword,
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          errorText: (_confirm.text.isNotEmpty && _confirm.text != _password.text)
                              ? t.passwordsDontMatch
                              : null,
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Insets.md),
                          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      const SizedBox(height: Insets.lg),
                      FilledButton(
                        onPressed: (_busy || !_ok) ? null : _submit,
                        child: _busy
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(t.resetPassword),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
