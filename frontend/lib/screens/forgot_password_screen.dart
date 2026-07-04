import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';

/// Request a password-reset email. Always reports success (the backend never
/// reveals whether the address exists).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().forgotPassword(_email.text.trim());
      if (mounted) setState(() => _sent = true);
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
      appBar: AppBar(title: Text(t.forgotPassword)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _sent
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.mark_email_read_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: Insets.md),
                    Text(t.resetLinkSent, textAlign: TextAlign.center),
                    const SizedBox(height: Insets.lg),
                    FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.logIn)),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofocus: true,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: t.fieldEmail,
                          prefixIcon: const Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Insets.md),
                          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      const SizedBox(height: Insets.lg),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
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
