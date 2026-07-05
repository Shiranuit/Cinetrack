import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/auth.dart';
import '../widgets/avatar.dart';
import 'calendar_screen.dart';
import 'discover_screen.dart';
import 'friends_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';

/// Root authenticated scaffold. Bottom nav: Library · Discover · Calendar.
/// Top bar: Friends icon + profile avatar (→ menu). Wide screens use a rail that
/// also surfaces Friends & Profile.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _icons = [
    Icons.local_movies_rounded,
    Icons.auto_awesome_rounded,
    Icons.calendar_month_rounded,
  ];
  final _bodies = const [LibraryScreen(), DiscoverScreen(), CalendarScreen()];

  void _openFriends() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final labels = [t.navLibrary, t.navDiscover, t.navCalendar];
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    // On wide layouts the rail adds a 4th (Friends) destination beyond the 3 body
    // tabs, so `_index` can be one past `labels`/`_bodies` — fall back to Friends.
    final title = _index < labels.length ? labels[_index] : t.friends;
    // The narrow layout has no Friends tab (it's reached via the app-bar icon), so
    // clamp into the 3 body tabs in case `_index` was left at Friends while wide.
    final bodyIndex = _index < _bodies.length ? _index : 0;
    return Scaffold(
      appBar: _AppBar(title: title, onFriends: _openFriends),
      body: wide ? _wide(labels, t.friends) : _bodies[bodyIndex],
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: bodyIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (var i = 0; i < _icons.length; i++)
                  NavigationDestination(icon: Icon(_icons[i]), label: labels[i]),
              ],
            ),
    );
  }

  Widget _wide(List<String> labels, String friends) => Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            groupAlignment: -0.9,
            destinations: [
              for (var i = 0; i < _icons.length; i++)
                NavigationRailDestination(icon: Icon(_icons[i]), label: Text(labels[i])),
              NavigationRailDestination(
                  icon: const Icon(Icons.people_alt_rounded), label: Text(friends)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _index < _bodies.length ? _bodies[_index] : const FriendsScreen()),
        ],
      );
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({required this.title, required this.onFriends});
  final String title;
  final VoidCallback onFriends;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppBar(
      titleSpacing: Insets.lg,
      title: Row(
        children: [
          Icon(Icons.local_movies_rounded, color: context.scheme.primary, size: 22),
          const SizedBox(width: Insets.sm),
          Text('CINETRACK', style: context.text.titleLarge?.copyWith(letterSpacing: 1.5, fontSize: 18)),
          const SizedBox(width: Insets.md),
          Flexible(
            child: Text('· $title',
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
          ),
        ],
      ),
      actions: [
        IconButton(onPressed: onFriends, icon: const Icon(Icons.people_alt_rounded), tooltip: t.friends),
        Padding(padding: const EdgeInsets.only(right: Insets.lg, left: Insets.xs), child: const _ProfileButton()),
      ],
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return InkResponse(
      radius: 24,
      // Straight to the profile (Settings + Log out live inside it now).
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
      child: UserAvatar(name: auth.me?.screenName ?? '?', url: auth.me?.avatarUrl, radius: 17),
    );
  }
}
