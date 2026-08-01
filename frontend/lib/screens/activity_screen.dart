import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
import '../widgets/activity_tile.dart';
import '../widgets/states.dart';
import 'movie_detail_screen.dart';
import 'show_detail_screen.dart';

/// How many entries one page request fetches.
const int _kPageSize = 30;

/// Open what an activity entry refers to: the movie, or the show an episode
/// belongs to. A no-op for an entry whose catalog record is gone (a dead id
/// left by an import), which has nowhere to navigate to.
void openActivityItem(BuildContext context, ActivityItem item) {
  final route = switch (item) {
    ActivityItem(isMovie: true, movieId: final id?) =>
      MaterialPageRoute<void>(builder: (_) => MovieDetailScreen(movieId: id)),
    ActivityItem(isMovie: false, seriesId: final id?) =>
      MaterialPageRoute<void>(builder: (_) => ShowDetailScreen(seriesId: id)),
    _ => null,
  };
  if (route != null) Navigator.of(context).push(route);
}

/// A user's full watch-activity timeline (newest first), paged as you scroll.
/// Works for your own activity and, when their privacy setting allows it, for
/// someone else's — the backend returns an empty list when it doesn't.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.userId, required this.title});

  final String userId;
  final String title;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _scroll = ScrollController();
  final _items = <ActivityItem>[];
  int _offset = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) _loadMore();
  }

  Future<void> _reset() async {
    setState(() {
      _items.clear();
      _offset = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // Await BEFORE touching state — never do async work inside setState.
    final api = context.read<ApiClient>();
    final langs = context.read<SettingsController>().langsParam;
    try {
      final page = await api.userActivity(
        widget.userId,
        langs: langs,
        limit: _kPageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset += page.length;
        // A short page means we've reached the end.
        if (page.length < _kPageSize) _hasMore = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(onRefresh: _reset, child: _body(t)),
    );
  }

  Widget _body(AppLocalizations t) {
    // First-page states: a full-height scrollable so pull-to-refresh still works.
    if (_items.isEmpty) {
      if (_loading) return const LoadingView();
      final child = _error != null
          ? ErrorView(message: '$_error', onRetry: _reset)
          : MessageView(icon: Icons.history_rounded, message: t.noActivityYet);
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.22), child],
      );
    }

    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: Insets.sm, bottom: Insets.xxl),
      // One extra row carries the paging spinner / retry affordance.
      itemCount: _items.length + 1,
      separatorBuilder: (_, i) => i < _items.length - 1
          ? const Divider(height: 1, indent: Insets.lg, endIndent: Insets.lg)
          : const SizedBox.shrink(),
      itemBuilder: (context, i) {
        if (i < _items.length) {
          final item = _items[i];
          return ActivityTile(item: item, onTap: () => openActivityItem(context, item));
        }
        return Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Center(
            child: _loading
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null
                    ? TextButton(onPressed: _loadMore, child: Text(t.retry))
                    : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
