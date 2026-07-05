import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';

/// Create invitations (link to share or emailed) and review their status.
class InvitesScreen extends StatefulWidget {
  const InvitesScreen({super.key});
  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  final _email = TextEditingController();
  late Future<List<InviteInfo>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiClient>().listInvites();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _reload() {
    // Compute the Future first, then assign inside a block-body setState so the
    // callback returns void (an arrow body would return the Future and warn).
    final f = context.read<ApiClient>().listInvites();
    setState(() {
      _future = f;
    });
  }

  void _copy(String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).copied)));
  }

  Future<void> _revoke(InviteInfo inv) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.revoke),
        content: Text(t.revokeInviteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.revoke)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.revokeInvite(inv.id);
      messenger.showSnackBar(SnackBar(content: Text(t.inviteRevoked)));
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^ApiException\(\d+\):\s*'), ''))));
    }
  }

  Future<void> _create() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final invite = await api.createInvite(email: _email.text.trim());
      _email.clear();
      if (mounted) await _showInvite(invite);
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^ApiException\(\d+\):\s*'), ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showInvite(InviteCreated invite) async {
    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.invites),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (invite.emailed) ...[
              Text(t.inviteSent),
              const SizedBox(height: Insets.md),
            ],
            SelectableText(invite.link, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invite.link));
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.copied)));
            },
            child: Text(t.copyLink),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t.ok)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.invites),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator()) : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Insets.lg),
            // Stretch so children (incl. the theme's full-width FilledButton) get a
            // bounded width. A Row here would measure the button with unbounded
            // width and crash, since the button style is minWidth = infinity.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: t.sendInviteByEmail,
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                  ),
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  t.inviteHelp,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: Insets.md),
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(t.createInvite),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<InviteInfo>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final items = snap.data!;
                if (items.isEmpty) {
                  return Center(child: Text(t.noInvitesYet, style: Theme.of(context).textTheme.bodyMedium));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final inv = items[i];
                    final scheme = Theme.of(context).colorScheme;
                    return ListTile(
                      leading: Icon(inv.used ? Icons.how_to_reg_rounded : Icons.mail_outline_rounded),
                      title: Text(inv.email ?? t.inviteLink),
                      subtitle: Text('${t.expires} ${inv.expiresAt.split('.').first}'),
                      // Accepted invites are terminal (just show status). Pending ones
                      // can be copied (if the link is still valid) and revoked.
                      trailing: inv.used
                          ? Text(t.inviteUsed, style: TextStyle(color: scheme.primary))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (inv.link != null)
                                  IconButton(
                                    icon: const Icon(Icons.copy_rounded),
                                    tooltip: t.copyLink,
                                    onPressed: () => _copy(inv.link!),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.link_off_rounded),
                                  tooltip: t.revoke,
                                  onPressed: () => _revoke(inv),
                                ),
                              ],
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
