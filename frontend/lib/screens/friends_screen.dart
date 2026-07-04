import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../widgets/avatar.dart';
import '../widgets/section.dart';
import '../l10n/app_localizations.dart';
import '../widgets/states.dart';
import 'profile_screen.dart';

/// Friends: find & follow users, handle incoming requests, and see activity.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<UserBrief>? _userResults;
  bool _searchBusy = false;
  late Future<List<UserBrief>> _following;
  late Future<List<UserBrief>> _followers;
  late Future<List<UserBrief>> _requests;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _following = api.following();
    _followers = api.followers();
    _requests = api.followRequests();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _query => _searchCtrl.text.trim();

  void _onSearch() {
    _debounce?.cancel();
    setState(() {});
    if (_query.isEmpty) {
      setState(() => _userResults = null);
      return;
    }
    setState(() => _searchBusy = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await context.read<ApiClient>().searchUsers(_query);
        if (mounted) {
          setState(() {
            _userResults = r;
            _searchBusy = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searchBusy = false);
      }
    });
  }

  Future<void> _toggleFollow(UserBrief u) async {
    final api = context.read<ApiClient>();
    await api.followUser(u.id, !(u.following || u.requested));
    if (!mounted) return;
    if (_query.isNotEmpty) {
      final r = await api.searchUsers(_query);
      if (mounted) setState(() => _userResults = r);
    }
    _refresh();
  }

  void _refresh() {
    final api = context.read<ApiClient>();
    final fl = api.following();
    final fw = api.followers();
    final rq = api.followRequests();
    setState(() {
      _following = fl;
      _followers = fw;
      _requests = rq;
    });
  }

  Future<void> _removeFollower(UserBrief u) async {
    await context.read<ApiClient>().removeFollower(u.id);
    _refresh();
  }

  Future<void> _openProfile(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: id)));
    _refresh();
  }

  Future<void> _respond(UserBrief u, bool accept) async {
    final api = context.read<ApiClient>();
    if (accept) {
      await api.acceptRequest(u.id);
    } else {
      await api.rejectRequest(u.id);
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.friends)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.sm),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: t.findPeople,
                prefixIcon: const Icon(Icons.person_search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _searchCtrl.clear),
              ),
            ),
          ),
          Expanded(child: _query.isEmpty ? _homeView() : _userResultsView()),
        ],
      ),
    );
  }

  /// A tappable user row with a privacy-aware follow control.
  Widget _userTile(UserBrief u, {Widget? trailing}) => ListTile(
        onTap: () => _openProfile(u.id),
        leading: UserAvatar(name: u.screenName, url: u.avatarUrl, radius: 20),
        title: Text(u.screenName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: u.isPrivate
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_rounded, size: 12, color: context.scheme.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(AppLocalizations.of(context).private),
              ])
            : null,
        trailing: trailing ?? _followButton(u),
      );

  // Compact style: the app theme makes buttons full-width (minimumSize height 52
  // → infinite width), which a ListTile.trailing can't accommodate. Shrink them.
  static final _compact = ButtonStyle(
    minimumSize: WidgetStateProperty.all(Size.zero),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  Widget _followButton(UserBrief u) {
    final t = AppLocalizations.of(context);
    if (u.following) return OutlinedButton(style: _compact, onPressed: () => _toggleFollow(u), child: Text(t.following));
    if (u.requested) return OutlinedButton(style: _compact, onPressed: () => _toggleFollow(u), child: Text(t.requested));
    return FilledButton(style: _compact, onPressed: () => _toggleFollow(u), child: Text(u.isPrivate ? t.requestToFollow : t.follow));
  }

  Widget _userResultsView() {
    if (_searchBusy && _userResults == null) return const LoadingView();
    final users = _userResults ?? [];
    if (users.isEmpty) return const MessageView(icon: Icons.person_off_rounded, message: 'No users found.');
    return ListView.builder(itemCount: users.length, itemBuilder: (context, i) => _userTile(users[i]));
  }

  Widget _homeView() {
    final t = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await Future.wait([_following, _followers, _requests]);
      },
      child: FutureBuilder<List<UserBrief>>(
        future: _following,
        builder: (context, snap) {
          final friends = snap.data ?? [];
          final loading = snap.connectionState == ConnectionState.waiting;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Insets.xxl),
            children: [
              _requestsSection(),
              SectionHeader(title: t.following, icon: Icons.people_alt_rounded, trailing: friends.isEmpty ? null : Text('${friends.length}')),
              if (loading)
                const Padding(padding: EdgeInsets.all(Insets.xl), child: Center(child: CircularProgressIndicator()))
              else if (friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: Insets.xl),
                  child: MessageView(
                    icon: Icons.group_add_rounded,
                    message: "You aren't following anyone yet.\nSearch above to find people.",
                  ),
                )
              else
                for (final u in friends) _userTile(u),
              _followersSection(),
            ],
          );
        },
      ),
    );
  }

  Widget _followersSection() {
    final t = AppLocalizations.of(context);
    return FutureBuilder<List<UserBrief>>(
      future: _followers,
      builder: (context, snap) {
        final followers = snap.data ?? [];
        if (followers.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: t.followers, icon: Icons.group_rounded, trailing: Text('${followers.length}')),
            for (final u in followers)
              _userTile(u,
                  trailing: OutlinedButton(
                    style: _compact,
                    onPressed: () => _removeFollower(u),
                    child: Text(t.remove),
                  )),
          ],
        );
      },
    );
  }

  Widget _requestsSection() {
    final t = AppLocalizations.of(context);
    return FutureBuilder<List<UserBrief>>(
      future: _requests,
      builder: (context, snap) {
        final reqs = snap.data ?? [];
        if (reqs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: t.followRequests, icon: Icons.person_add_rounded, accent: context.scheme.primary),
            for (final u in reqs)
              _userTile(u,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: t.accept,
                      icon: Icon(Icons.check_circle_rounded, color: context.colors.seen),
                      onPressed: () => _respond(u, true),
                    ),
                    IconButton(
                      tooltip: t.decline,
                      icon: Icon(Icons.cancel_rounded, color: context.scheme.onSurfaceVariant),
                      onPressed: () => _respond(u, false),
                    ),
                  ])),
          ],
        );
      },
    );
  }
}
