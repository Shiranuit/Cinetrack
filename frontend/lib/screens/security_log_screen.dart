import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';

/// Recent security activity on the account (from the backend audit trail).
class SecurityLogScreen extends StatefulWidget {
  const SecurityLogScreen({super.key});
  @override
  State<SecurityLogScreen> createState() => _SecurityLogScreenState();
}

class _SecurityLogScreenState extends State<SecurityLogScreen> {
  late Future<List<SecurityEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiClient>().securityLog();
  }

  (IconData, String) _describe(AppLocalizations t, String event) => switch (event) {
        'login.success' => (Icons.login_rounded, t.evLoginOk),
        'login.failed' => (Icons.gpp_bad_rounded, t.evLoginFail),
        'password.changed' => (Icons.password_rounded, t.evPasswordChanged),
        'password.reset_requested' => (Icons.mail_lock_rounded, t.evResetRequested),
        'password.reset_completed' => (Icons.lock_reset_rounded, t.evResetCompleted),
        'user.registered' => (Icons.person_add_rounded, t.evRegistered),
        'invite.created' => (Icons.card_giftcard_rounded, t.evInviteCreated),
        'account.deleted' => (Icons.person_off_rounded, t.evAccountDeleted),
        _ => (Icons.info_outline_rounded, event),
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.securityActivity)),
      body: FutureBuilder<List<SecurityEvent>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'.replaceFirst(RegExp(r'^ApiException\(\d+\):\s*'), '')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(child: Text(t.noActivityYet, style: Theme.of(context).textTheme.bodyMedium));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = items[i];
              final (icon, label) = _describe(t, e.event);
              final when = e.createdAt.replaceFirst('T', ' ').split('.').first;
              final failed = e.event == 'login.failed';
              return ListTile(
                leading: Icon(icon, color: failed ? Theme.of(context).colorScheme.error : null),
                title: Text(label),
                subtitle: Text([when, if (e.ip != null && e.ip != 'unknown') e.ip!].join('  ·  ')),
                dense: true,
              );
            },
          );
        },
      ),
    );
  }
}
