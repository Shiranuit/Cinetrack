import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/auth.dart';
import '../state/settings.dart';
import '../widgets/password_strength.dart';
import '../widgets/section.dart';
import 'import_matches_screen.dart';
import 'invites_screen.dart';
import 'security_log_screen.dart';

const kLanguages = {
  'eng': 'English',
  'fra': 'Français',
  'jpn': '日本語',
  'spa': 'Español',
  'deu': 'Deutsch',
  'ita': 'Italiano',
  'por': 'Português',
  'kor': '한국어',
  'zho': '中文',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  int _suggestions = 0;

  @override
  void initState() {
    super.initState();
    _refreshSuggestions();
  }

  void _refreshSuggestions() {
    context
        .read<ApiClient>()
        .importSuggestions(langs: context.read<SettingsController>().langsParam)
        .then((s) {
          if (mounted) setState(() => _suggestions = s.length);
        })
        .catchError((_) {});
  }

  Future<void> _openMatches() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ImportMatchesScreen()));
    _refreshSuggestions();
  }

  Future<void> _importGdpr() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    final f = res?.files.firstOrNull;
    if (f?.bytes == null || !mounted) return;
    final api = context.read<ApiClient>();
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final s = await api.importGdpr(f!.bytes!, f.name);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t.importGdprSuccess(
              s['shows'] as int,
              s['watch_events'] as int,
              s['favorites'] as int,
            ),
          ),
        ),
      );
      // The background prefetch resolves dead ids; poll a few times for suggestions.
      for (final delay in [8, 20, 40]) {
        Future.delayed(Duration(seconds: delay), () {
          if (mounted) _refreshSuggestions();
        });
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${AppLocalizations.of(context).deleteAccount}?'),
        content: Text(AppLocalizations.of(context).deleteAccountConfirmBody),
        // Sensitive action: make Cancel the obvious, prominent default and Delete
        // the deliberately-understated (subtle text) choice so it's hard to hit by
        // accident.
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: context.scheme.onSurfaceVariant,
            ),
            child: Text(AppLocalizations.of(ctx).deleteAnyway),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx).keepMyAccount),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await api.deleteAccount();
      // Pop Settings/Profile off the stack BEFORE logging out, otherwise they
      // stay mounted over the login screen and the app looks stuck.
      navigator.popUntil((r) => r.isFirst);
      await auth.logout(); // clears token → app root returns to the auth screen
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPrivacy(bool isPrivate) async {
    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await api.setPrivacy(isPrivate);
      await auth.reloadMe();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errText(Object e) => e is ApiException ? e.message : '$e';

  /// A single-field text dialog; returns the trimmed value or null if cancelled.
  Future<String?> _promptText({
    required String title,
    required String label,
    required String initial,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final formKey = GlobalKey<FormState>();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            keyboardType: keyboard,
            decoration: InputDecoration(labelText: label),
            validator: validator,
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: Text(AppLocalizations.of(ctx).save),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  Future<void> _editName() async {
    final t = AppLocalizations.of(context);
    final me = context.read<AuthController>().me;
    final name = await _promptText(
      title: t.displayName,
      label: t.fieldName,
      initial: me?.screenName ?? '',
      keyboard: TextInputType.name,
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? t.nameCannotBeEmpty : null,
    );
    if (name == null || !mounted) return;
    await _saveProfile(screenName: name);
  }

  Future<void> _editEmail() async {
    final t = AppLocalizations.of(context);
    final me = context.read<AuthController>().me;
    final email = await _promptText(
      title: t.fieldEmail,
      label: t.fieldEmail,
      initial: me?.email ?? '',
      keyboard: TextInputType.emailAddress,
      validator: (v) =>
          (v == null || !v.contains('@')) ? t.enterValidEmail : null,
    );
    if (email == null || !mounted) return;
    await _saveProfile(email: email);
  }

  Future<void> _saveProfile({String? screenName, String? email}) async {
    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await api.updateProfile(screenName: screenName, email: email);
      await auth.reloadMe();
      messenger.showSnackBar(SnackBar(content: Text(t.profileUpdated)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Change password: requires the CURRENT password (backend enforces it). The
  /// backend rotates the session token, so we adopt the returned one.
  Future<void> _changePassword() async {
    final t = AppLocalizations.of(context);
    final cur = TextEditingController();
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      // StatefulBuilder so the checklist and the Update button react live as the
      // fields change. Gate the button on the SAME policy as sign-up/reset
      // (isStrongPassword) instead of the old length-only check.
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final strong = isStrongPassword(p1.text);
          final match = p2.text == p1.text;
          final canSubmit = cur.text.isNotEmpty && strong && match;
          return AlertDialog(
            title: Text(t.changePassword),
            content: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: cur,
                    obscureText: true,
                    autofocus: true,
                    autofillHints: const [AutofillHints.password],
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(labelText: t.currentPassword),
                  ),
                  const SizedBox(height: Insets.sm),
                  TextField(
                    controller: p1,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(labelText: t.newPassword),
                  ),
                  const SizedBox(height: Insets.sm),
                  PasswordChecklist(password: p1.text),
                  const SizedBox(height: Insets.sm),
                  TextField(
                    controller: p2,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      labelText: t.fieldConfirmPassword,
                      errorText: (p2.text.isNotEmpty && !match)
                          ? t.passwordsDontMatch
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx).cancel),
              ),
              FilledButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(ctx, (cur.text, p1.text))
                    : null,
                child: Text(AppLocalizations.of(ctx).update),
              ),
            ],
          );
        },
      ),
    );
    cur.dispose();
    p1.dispose();
    p2.dispose();
    if (result == null || !mounted) return;

    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await api.changePassword(
        result.$1,
        result.$2,
      ); // this session stays valid
      TextInput.finishAutofillContext(); // let the manager update the stored password
      messenger.showSnackBar(SnackBar(content: Text(t.passwordUpdated)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final settings = context.watch<SettingsController>();
    final me = context.watch<AuthController>().me;
    final isPrivate = me?.isPrivate ?? false;
    final available = kLanguages.keys
        .where((k) => !settings.languages.contains(k))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Insets.xxl),
        children: [
          SectionHeader(title: t.sectionAccount, icon: Icons.person_rounded),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(t.fieldName),
            subtitle: Text(me?.screenName ?? '—'),
            trailing: const Icon(Icons.edit_rounded, size: 20),
            onTap: _busy ? null : _editName,
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email_rounded),
            title: Text(t.fieldEmail),
            subtitle: Text(me?.email ?? '—'),
            trailing: const Icon(Icons.edit_rounded, size: 20),
            onTap: _busy ? null : _editEmail,
          ),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: Text(t.changePassword),
            subtitle: Text(t.setNewPassword),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : _changePassword,
          ),
          ListTile(
            leading: const Icon(Icons.card_giftcard_rounded),
            title: Text(t.invites),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const InvitesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(t.securityActivity),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SecurityLogScreen()),
            ),
          ),
          SectionHeader(
            title: t.sectionPrivacy,
            icon: Icons.lock_outline_rounded,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_person_rounded),
            title: Text(t.privateProfile),
            subtitle: Text(t.privacyHint),
            value: isPrivate,
            onChanged: _busy ? null : _setPrivacy,
          ),
          SectionHeader(
            title: t.sectionAppearance,
            icon: Icons.palette_rounded,
          ),
          Padding(
            padding: Insets.pageH,
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_rounded),
                  label: Text(t.themeDark),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_rounded),
                  label: Text(t.themeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_rounded),
                  label: Text(t.themeAuto),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
            ),
          ),
          SectionHeader(
            title: t.sectionLanguages,
            icon: Icons.translate_rounded,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            child: Text(
              t.langPriorityHint,
              style: context.text.labelMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.sm,
            ),
            onReorderItem: (oldIndex, newIndex) {
              final langs = List<String>.from(settings.languages);
              langs.insert(newIndex, langs.removeAt(oldIndex));
              settings.setLanguages(langs);
            },
            children: [
              for (var i = 0; i < settings.languages.length; i++)
                // The whole card is the drag surface - a far bigger target than a
                // small handle. The drag icon stays as a visual affordance; the
                // remove button still taps normally (tap wins over drag).
                ReorderableDragStartListener(
                  key: ValueKey(settings.languages[i]),
                  index: i,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: Insets.sm),
                    color: context.scheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: Icon(Icons.drag_handle_rounded, color: context.scheme.onSurfaceVariant),
                      title: Text(
                      kLanguages[settings.languages[i]] ??
                          settings.languages[i],
                    ),
                    subtitle: i == 0
                        ? Text(
                            t.primary,
                            style: TextStyle(color: context.scheme.primary),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Priority number (1 = primary) on the right of each card.
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == 0 ? context.scheme.primary : Colors.transparent,
                            border: i == 0 ? null : Border.all(color: context.scheme.outlineVariant),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: context.text.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: i == 0 ? context.scheme.onPrimary : context.scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (settings.languages.length > 1)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            onPressed: () {
                              final langs = List<String>.from(settings.languages)..removeAt(i);
                              settings.setLanguages(langs);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (available.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                0,
                Insets.lg,
                Insets.sm,
              ),
              child: Text(
                t.addLanguage,
                style: context.text.labelMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: Insets.pageH,
              child: Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final k in available)
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: Text(kLanguages[k]!),
                      onPressed: () =>
                          settings.setLanguages([...settings.languages, k]),
                    ),
                ],
              ),
            ),
          ],
          SectionHeader(title: t.sectionData, icon: Icons.storage_rounded),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: Text(t.importTvTime),
            subtitle: Text(t.importGdprHint),
            onTap: _busy ? null : _importGdpr,
          ),
          if (_suggestions > 0)
            ListTile(
              leading: Badge(
                label: Text('$_suggestions'),
                child: const Icon(Icons.rule_rounded),
              ),
              title: Text(t.reviewImportMatches),
              subtitle: Text(t.showsNeedConfirming(_suggestions)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _busy ? null : _openMatches,
            ),
          SectionHeader(
            title: t.sectionDangerZone,
            icon: Icons.person_off_rounded,
            accent: context.scheme.error,
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_rounded,
              color: context.scheme.error,
            ),
            title: Text(
              t.deleteAccount,
              style: TextStyle(color: context.scheme.error),
            ),
            subtitle: Text(t.deleteAccountHint),
            onTap: _busy ? null : _deleteAccount,
          ),
        ],
      ),
    );
  }
}
