import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../state/auth.dart';
import '../state/settings.dart';
import '../widgets/avatar.dart';
import '../widgets/net_image.dart';
import '../widgets/section.dart';
import '../widgets/show_card.dart';
import '../widgets/states.dart';
import 'settings_screen.dart';
import 'show_detail_screen.dart';
import 'user_library_screen.dart';

/// The showcase blocks a profile can display, in customizable order.
const kAllProfileBlocks = ['stats', 'favorites', 'shows'];
const _kBlockLabels = {
  'stats': 'Statistics',
  'favorites': 'Favorites',
  'shows': 'Shows',
};

/// A user's profile showcase — the current user's own profile when [userId] is
/// null, otherwise another user's (respecting their privacy). Both render the
/// same block-based layout, so a friend's profile honors the layout they chose.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId});

  /// The user to show; null means the authenticated user's own profile.
  final int? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final int _targetId;
  late Future<UserProfile> _profile;
  late Future<Stats> _stats;
  late Future<List<UserShow>> _shows;
  bool _busy = false;

  bool get _isSelf => widget.userId == null;

  @override
  void initState() {
    super.initState();
    _targetId = widget.userId ?? context.read<AuthController>().me!.id;
    _reload();
  }

  void _reload() {
    final api = context.read<ApiClient>();
    final langs = context.read<SettingsController>().langsParam;
    final p = api.userProfile(_targetId);
    final st = api.userStats(_targetId);
    final sh = api.userShows(_targetId, langs: langs);
    setState(() {
      _profile = p;
      _stats = st;
      _shows = sh;
    });
  }

  Future<void> _refresh() async {
    _reload();
    await _profile;
  }

  String _watchTime(int minutes) {
    final mo = minutes ~/ (60 * 24 * 30);
    final d = (minutes % (60 * 24 * 30)) ~/ (60 * 24);
    final h = (minutes % (60 * 24)) ~/ 60;
    return [if (mo > 0) '${mo}mo', if (d > 0) '${d}d', '${h}h'].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<UserProfile>(
        future: _profile,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(message: '${snap.error}', onRetry: _reload);
          }
          final p = snap.data!;
          // For the current user, blocks come from the live `me` so reordering
          // in the customize sheet reflects instantly; others come from the
          // fetched profile (the layout that user chose).
          final me = _isSelf ? context.watch<AuthController>().me : null;
          final blocks = me?.profileBlocks ?? p.profileBlocks;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: Insets.xxl),
              children: [
                _isSelf ? _selfBanner(me!) : _otherBanner(p),
                if (!_isSelf)
                  Padding(
                    padding: const EdgeInsets.all(Insets.lg),
                    child: _followButton(p),
                  ),
                _countsRow(p),
                if (!p.visible)
                  _privateNotice(p)
                else
                  for (final b in blocks) _block(b, p),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _countsRow(UserProfile p) => Padding(
        padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('${p.followerCount}', AppLocalizations.of(context).followers),
            _stat('${p.followingCount}', AppLocalizations.of(context).following),
          ],
        ),
      );

  Widget _privateNotice(UserProfile p) => Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          children: [
            Icon(Icons.lock_rounded,
                size: 40, color: context.scheme.onSurfaceVariant),
            const SizedBox(height: Insets.md),
            Text(AppLocalizations.of(context).accountPrivate,
                style: context.text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: Insets.xs),
            Text(AppLocalizations.of(context).followToSee(p.screenName),
                style: context.text.bodyMedium
                    ?.copyWith(color: context.scheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _block(String block, UserProfile p) {
    switch (block) {
      case 'stats':
        return _statsBlock();
      case 'favorites':
        return _favoritesBlock(p);
      case 'shows':
        return _showsBlock(p);
      default:
        return const SizedBox.shrink();
    }
  }

  /// Watch statistics (episodes, time watched, movies).
  Widget _statsBlock() {
    return FutureBuilder<Stats>(
      future: _stats,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return const SizedBox(height: Insets.md);
        final items = [
          ('${s.episodesSeen}', AppLocalizations.of(context).statEpisodes),
          (_watchTime(s.totalMinutes), AppLocalizations.of(context).statWatched),
          ('${s.moviesSeen}', AppLocalizations.of(context).statMovies),
        ];
        return Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Insets.lg),
            decoration: BoxDecoration(
                color: context.scheme.surface, borderRadius: Radii.card),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final (value, label) in items) _stat(value, label),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _favoritesBlock(UserProfile p) {
    return FutureBuilder<List<UserShow>>(
      future: _shows,
      builder: (context, snap) {
        final favorites =
            (snap.data ?? []).where((s) => s.isFavorited).toList();
        if (favorites.isEmpty) return const SizedBox.shrink();
        return _rail(
          '${AppLocalizations.of(context).favorites} (${favorites.length})',
          Icons.favorite_rounded,
          context.colors.favorite,
          favorites,
          onSeeAll: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ShowsGridScreen(
                  title: _isSelf ? AppLocalizations.of(context).favorites : '${p.screenName}\'s favorites',
                  shows: favorites))),
        );
      },
    );
  }

  /// The full library of tracked shows — "See all" opens the categorized
  /// library view (currently watching / up to date / stale / …) with progress.
  Widget _showsBlock(UserProfile p) {
    return FutureBuilder<List<UserShow>>(
      future: _shows,
      builder: (context, snap) {
        final shows = snap.data ?? [];
        if (shows.isEmpty) return const SizedBox.shrink();
        return _rail(
          '${AppLocalizations.of(context).shows} (${shows.length})',
          Icons.local_movies_rounded,
          context.scheme.primary,
          shows,
          onSeeAll: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => UserLibraryScreen(
                  userId: _targetId,
                  title: _isSelf ? 'Your shows' : '${p.screenName}\'s shows'))),
        );
      },
    );
  }

  Widget _rail(String title, IconData icon, Color accent, List<UserShow> shows,
          {VoidCallback? onSeeAll}) =>
      PosterRail(
        title: title,
        icon: icon,
        accent: accent,
        count: shows.length,
        onSeeAll: onSeeAll,
        itemBuilder: (context, i) {
          final s = shows[i];
          return ShowCard(
            title: s.name ?? 'Series ${s.seriesId}',
            imageUrl: s.imageUrl,
            favorite: s.isFavorited,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => ShowDetailScreen(seriesId: s.seriesId)),
            ),
          );
        },
      );

  Widget _stat(String value, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: context.text.titleLarge),
          const SizedBox(height: 2),
          Text(label,
              style: context.text.labelSmall
                  ?.copyWith(color: context.scheme.onSurfaceVariant)),
        ],
      );

  // ---- follow (other users) ----

  Future<void> _toggleFollow(UserProfile p) async {
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      // Following or requested → cancel; otherwise follow/request.
      await api.followUser(p.id, !(p.following || p.requested));
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _followButton(UserProfile p) {
    final (String label, bool filled) = p.following
        ? (AppLocalizations.of(context).unfollow, false)
        : p.requested
            ? (AppLocalizations.of(context).requested, false)
            : p.isPrivate
                ? (AppLocalizations.of(context).requestToFollow, true)
                : (AppLocalizations.of(context).follow, true);
    final child = _busy
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2))
        : Text(label);
    final onPressed = _busy ? null : () => _toggleFollow(p);
    // Force the same height for both states so the button doesn't jump.
    const size = Size.fromHeight(52);
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              style: FilledButton.styleFrom(minimumSize: size),
              onPressed: onPressed,
              child: child)
          : OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: size),
              onPressed: onPressed,
              child: child),
    );
  }

  // ---- banners ----

  /// Another user's banner: cover, avatar, name, privacy lock and bio.
  Widget _otherBanner(UserProfile p) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: 200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetImage(url: p.coverUrl),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0.2), bg.withValues(alpha: 0.8)],
              ),
            ),
          ),
          Positioned(
            left: Insets.lg,
            right: Insets.lg,
            bottom: Insets.lg,
            child: Row(
              children: [
                UserAvatar(name: p.screenName, url: p.avatarUrl, radius: 36),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(p.screenName,
                              style: context.text.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (p.isPrivate) ...[
                          const SizedBox(width: Insets.sm),
                          Icon(Icons.lock_rounded,
                              size: 16, color: context.scheme.onSurfaceVariant),
                        ],
                      ]),
                      if (p.bio?.isNotEmpty ?? false)
                        Text(p.bio!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                                color: context.scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(Insets.sm),
                child: CircleAvatar(
                  backgroundColor: context.colors.scrim.withValues(alpha: 0.5),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The current user's banner: editable cover/avatar plus customize, settings
  /// and logout actions.
  Widget _selfBanner(Me me) {
    return SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Bottom layer: tapping the background offers to change it (opaque so
          // it catches taps even over the gradient fallback; the avatar/buttons
          // above win hit-testing on their own areas).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _customizeImage(false),
            child: NetImage(url: me.coverUrl, fallback: _gradient()),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    context.colors.scrim.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: Insets.lg,
            right: Insets.lg,
            bottom: Insets.lg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _customizeImage(true),
                  child: UserAvatar(
                    name: me.screenName,
                    url: me.avatarUrl,
                    radius: 36,
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        me.screenName,
                        style: context.text.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (me.bio != null && me.bio!.isNotEmpty)
                        Text(
                          me.bio!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Insets.sm),
                    child: CircleAvatar(
                      backgroundColor:
                          context.colors.scrim.withValues(alpha: 0.5),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Insets.sm),
                    child: Row(
                      children: [
                        _bannerAction(Icons.tune_rounded, AppLocalizations.of(context).customizeProfile,
                            _openCustomize),
                        const SizedBox(width: Insets.sm),
                        _bannerAction(
                          Icons.settings_rounded,
                          'Settings',
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const SettingsScreen()),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        _bannerAction(Icons.logout_rounded, 'Log out', () {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                          context.read<AuthController>().logout();
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerAction(IconData icon, String tooltip, VoidCallback onPressed) =>
      CircleAvatar(
        backgroundColor: context.colors.scrim.withValues(alpha: 0.5),
        child: IconButton(
          icon: Icon(icon, color: Colors.white),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      );

  Widget _gradient() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              context.scheme.primary.withValues(alpha: 0.55),
              context.colors.favorite.withValues(alpha: 0.4),
            ],
          ),
        ),
      );

  /// Tap avatar/cover → offer to change that image.
  Future<void> _customizeImage(bool avatar) async {
    final picked = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                avatar ? Icons.account_circle_rounded : Icons.wallpaper_rounded,
              ),
              title: Text(
                avatar ? 'Change profile photo' : 'Change background',
              ),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (picked != true || !mounted) return;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (avatar) {
        await api.uploadAvatar(file!.bytes!, file.name);
      } else {
        await api.uploadCover(file!.bytes!, file.name);
      }
      await auth.reloadMe();
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _openCustomize() {
    final me = context.read<AuthController>().me;
    if (me == null) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => _CustomizeSheet(blocks: me.profileBlocks),
    );
  }
}

/// Reorder / toggle which profile blocks are shown. Persists to the server so
/// the layout is honored when others view this profile.
class _CustomizeSheet extends StatefulWidget {
  const _CustomizeSheet({required this.blocks});
  final List<String> blocks;
  @override
  State<_CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<_CustomizeSheet> {
  late List<String> _order; // all blocks, in display order
  late Set<String> _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.blocks.toSet();
    // Enabled first (in their order), then any disabled blocks.
    _order = [
      ...widget.blocks,
      ...kAllProfileBlocks.where((b) => !widget.blocks.contains(b)),
    ];
  }

  void _save() {
    final blocks = _order.where(_enabled.contains).toList();
    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    // Persist, then refresh `me` so the live profile picks up the new layout.
    api.setProfileBlocks(blocks).then((_) => auth.reloadMe());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              0,
              Insets.lg,
              Insets.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(AppLocalizations.of(context).customizeProfile, style: context.text.titleMedium),
            ),
          ),
          const Divider(height: 1),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            onReorderItem: (oldIndex, newIndex) {
              setState(
                () => _order.insert(newIndex, _order.removeAt(oldIndex)),
              );
              _save();
            },
            children: [
              for (var i = 0; i < _order.length; i++)
                ListTile(
                  key: ValueKey(_order[i]),
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle_rounded),
                  ),
                  title: Text(_kBlockLabels[_order[i]] ?? _order[i]),
                  trailing: Switch(
                    value: _enabled.contains(_order[i]),
                    onChanged: (on) {
                      setState(
                        () => on
                            ? _enabled.add(_order[i])
                            : _enabled.remove(_order[i]),
                      );
                      _save();
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: Insets.sm),
        ],
      ),
    );
  }
}
