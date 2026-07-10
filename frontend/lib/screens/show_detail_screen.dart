import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/library_membership.dart';
import '../state/selection.dart';
import '../state/settings.dart';
import '../util/locale_labels.dart';
import '../widgets/artwork_gallery.dart';
import '../widgets/badges.dart';
import '../widgets/confirm_actions.dart';
import '../widgets/episode_sheet.dart';
import '../widgets/net_image.dart';
import '../widgets/poster.dart';
import '../widgets/rating_thumbs.dart';
import '../widgets/states.dart';

class ShowDetailScreen extends StatefulWidget {
  const ShowDetailScreen({super.key, required this.seriesId});
  final int seriesId;
  @override
  State<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends State<ShowDetailScreen> {
  late final ApiClient _api = context.read<ApiClient>();
  bool _loading = true;
  String? _error;

  Series? _series;
  UserShow? _rel;
  List<Episode> _episodes = [];
  Map<int, int> _counts = {};
  SeriesDetails?
  _details; // best-effort; fills in the meta strip + details sheet

  String get _langs => context.read<SettingsController>().langsParam;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Rich metadata is non-critical: fetch it alongside, and let the meta strip
    // fill in when it arrives (a failure never blocks the page).
    _api
        .seriesDetails(widget.seriesId)
        .then((d) {
          if (mounted) setState(() => _details = d);
        })
        .catchError((_) {});
    try {
      final r = await Future.wait([
        _api.series(widget.seriesId, langs: _langs),
        _api.showRelation(widget.seriesId, langs: _langs),
        _api.episodes(widget.seriesId, langs: _langs),
        _api.seenCounts(widget.seriesId),
      ]);
      if (!mounted) return;
      setState(() {
        _series = r[0] as Series;
        _rel = r[1] as UserShow;
        _episodes = r[2] as List<Episode>;
        _counts = r[3] as Map<int, int>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  int get _seenDistinct => _counts.values.where((c) => c > 0).length;

  /// How many COMPLETE passes through the whole series have been watched: the
  /// minimum ×N watch count across every episode (0 if any episode is still
  /// unwatched, i.e. not yet fully seen). A single rewatched episode never raises
  /// it; only rewatching every episode does.
  int get _seriesWatchFloor {
    if (_episodes.isEmpty) return 0;
    var floor = 1 << 30;
    for (final e in _episodes) {
      final c = _counts[e.id] ?? 0;
      if (c < floor) floor = c;
    }
    return floor;
  }

  Future<void> _refreshRel() async {
    final rel = await _api.showRelation(widget.seriesId, langs: _langs);
    if (mounted) setState(() => _rel = rel);
  }

  // Every tracking action below upserts the show's library row, so each records it
  // in [LibraryMembership] (captured before the await) so Discover reflects it
  // without a reload. The membership overlay is add-only (the backend never drops
  // the row on unfollow/unwatch), matching how in_library actually behaves.

  Future<void> _toggleFollow() async {
    final membership = context.read<LibraryMembership>();
    await _api.setFollow(widget.seriesId, !(_rel?.isFollowed ?? false));
    membership.add(SelKind.series, widget.seriesId);
    await _refreshRel();
  }

  Future<void> _toggleFavorite() async {
    final membership = context.read<LibraryMembership>();
    await _api.setFavorite(widget.seriesId, !(_rel?.isFavorited ?? false));
    membership.add(SelKind.series, widget.seriesId);
    await _refreshRel();
  }

  Future<void> _setStatus(String? status) async {
    final membership = context.read<LibraryMembership>();
    await _api.setStatus(widget.seriesId, status);
    membership.add(SelKind.series, widget.seriesId);
    await _refreshRel();
  }

  Future<void> _rate(int? rating) async {
    // Optimistic: reflect immediately, then persist.
    setState(
      () => _rel = _rel == null
          ? null
          : UserShow(
              seriesId: _rel!.seriesId,
              name: _rel!.name,
              imageUrl: _rel!.imageUrl,
              isFollowed: _rel!.isFollowed,
              isFavorited: _rel!.isFavorited,
              status: _rel!.status,
              archived: _rel!.archived,
              nbEpisodesSeen: _rel!.nbEpisodesSeen,
              rating: rating,
            ),
    );
    await _api.rateShow(widget.seriesId, rating);
    await _refreshRel();
  }

  void _openDetailsSheet(SeriesDetails d) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DetailsSheet(details: d, seriesName: _series?.name),
    );
  }

  Widget _ratingRow() {
    final r = _rel?.rating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0),
      // Full-width control: thumbs spread across the row (aligned with the action
      // bar above), label under the selected one. Self-contained in RatingThumbs.
      child: RatingThumbs(value: r, onRate: _rate),
    );
  }

  Future<void> _watch(int episodeId) async {
    final membership = context.read<LibraryMembership>();
    // A fresh watch (0 -> 1), as opposed to a rewatch, is what can leave a gap.
    final wasSeen = (_counts[episodeId] ?? 0) > 0;
    setState(() => _counts[episodeId] = (_counts[episodeId] ?? 0) + 1);
    try {
      await _api.watch(episodeId);
      membership.add(SelKind.series, widget.seriesId);
      _refreshRel();
    } catch (e) {
      if (mounted) {
        setState(() => _counts[episodeId] = (_counts[episodeId] ?? 1) - 1);
      }
      return;
    }
    if (!wasSeen && mounted) await _offerFillGap(episodeId);
  }

  /// After marking an episode watched for the first time, if earlier episodes of
  /// the same season are still unseen, offer to mark those too (fill the gap).
  Future<void> _offerFillGap(int episodeId) async {
    Episode? ep;
    for (final e in _episodes) {
      if (e.id == episodeId) {
        ep = e;
        break;
      }
    }
    final season = ep?.seasonNumber;
    final number = ep?.number;
    // Specials (season 0) and episodes without a number have no "previous" to fill.
    if (season == null || season <= 0 || number == null) return;
    final hasGap = _episodes.any((e) =>
        e.seasonNumber == season && (e.number ?? 0) < number && (_counts[e.id] ?? 0) == 0);
    if (!hasGap) return;

    final t = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.markEarlierTitle),
        content: Text(t.markEarlierBody),
        // Side-by-side Yes/No. "Yes" (mark previous) is the common choice, so it's
        // the prominent (filled, right) button and "No" the outlined secondary
        // (left). confirmActions renders confirmLabel outlined-left and cancelLabel
        // filled-right, so the affirmative maps to cancelLabel.
        actions: confirmActions(
          ctx,
          confirmLabel: t.markEarlierDismiss,
          onConfirm: () => Navigator.pop(ctx, false),
          cancelLabel: t.markEarlierConfirm,
          onCancel: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _api.watchSeasonUpTo(widget.seriesId, season, number);
      final counts = await _api.seenCounts(widget.seriesId);
      if (mounted) setState(() => _counts = counts);
      _refreshRel();
    } catch (_) {
      // The single-episode watch already succeeded; ignore a fill failure.
    }
  }

  Future<void> _unwatch(int episodeId) async {
    final c = _counts[episodeId] ?? 0;
    if (c <= 0) return;
    setState(() => _counts[episodeId] = c - 1);
    try {
      await _api.unwatch(episodeId);
      _refreshRel();
    } catch (e) {
      if (mounted) setState(() => _counts[episodeId] = c);
    }
  }

  Future<void> _seasonAction(int season, String action) async {
    final membership = context.read<LibraryMembership>();
    try {
      switch (action) {
        case 'watch':
          await _api.watchSeason(widget.seriesId, season);
        case 'rewatch':
          await _api.rewatchSeason(widget.seriesId, season);
        case 'decrement':
          await _api.decrementSeason(widget.seriesId, season);
        case 'unwatch':
          await _api.unwatchSeason(widget.seriesId, season);
      }
      membership.add(SelKind.series, widget.seriesId);
      final counts = await _api.seenCounts(widget.seriesId);
      if (mounted) setState(() => _counts = counts);
      _refreshRel();
    } catch (_) {
      _load();
    }
  }

  /// Whole-series equivalent of [_seasonAction]: mark all watched / rewatch /
  /// unmark all, across every season.
  Future<void> _seriesAction(String action) async {
    final membership = context.read<LibraryMembership>();
    try {
      switch (action) {
        case 'watch':
          await _api.watchSeries(widget.seriesId);
        case 'rewatch':
          await _api.rewatchSeries(widget.seriesId);
        case 'decrement':
          await _api.decrementSeries(widget.seriesId);
        case 'unwatch':
          await _api.unwatchSeries(widget.seriesId);
      }
      membership.add(SelKind.series, widget.seriesId);
      final counts = await _api.seenCounts(widget.seriesId);
      if (mounted) setState(() => _counts = counts);
      _refreshRel();
    } catch (_) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : Stack(
              children: [
                RefreshIndicator(onRefresh: _load, child: _content()),
                _backButton(),
              ],
            ),
    );
  }

  Widget _backButton() => SafeArea(
    child: Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(Insets.sm),
        child: CircleAvatar(
          backgroundColor: context.colors.scrim.withValues(alpha: 0.55),
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
    ),
  );

  Widget _content() {
    final bySeason = <int, List<Episode>>{};
    for (final e in _episodes) {
      bySeason.putIfAbsent(e.seasonNumber ?? 0, () => []).add(e);
    }
    // Normal seasons ascending, then Specials (season 0) LAST — so the first
    // real season is at the top and gets the auto-expand, not the specials.
    final seasons = bySeason.keys.toList()
      ..sort((a, b) {
        if (a == 0) return 1;
        if (b == 0) return -1;
        return a.compareTo(b);
      });
    bool fullyWatched(int s) =>
        bySeason[s]!.every((e) => (_counts[e.id] ?? 0) > 0);
    // Auto-expand only the FIRST not-fully-watched season (in display order).
    final int? expandSeason = seasons.cast<int?>().firstWhere(
      (s) => !fullyWatched(s!),
      orElse: () => null,
    );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Hero(
          series: _series!,
          seenDistinct: _seenDistinct,
          totalEpisodes: _episodes.length,
          onTapArtwork: () =>
              openArtworkGallery(context, _api.seriesArtworks(widget.seriesId)),
        ),
        if (_details != null)
          _MetaStrip(
            details: _details!,
            onMore: () => _openDetailsSheet(_details!),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.lg,
            Insets.lg,
            0,
          ),
          child: _actionBar(),
        ),
        _ratingRow(),
        if (_series!.overview?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.lg,
              Insets.lg,
              0,
            ),
            child: SelectableText(
              _series!.overview!,
              style: context.text.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.xl,
            Insets.lg,
            Insets.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).episodes,
                  style: context.text.titleLarge,
                ),
              ),
              // When every episode has been watched at least once, show how many
              // FULL passes through the series that is (the min ×N across episodes)
              // instead of a plain "all watched" check; one rewatched episode does
              // not bump it (min, not max).
              if (_seriesWatchFloor >= 1) ...[
                CountBadge(count: _seriesWatchFloor, size: 30),
                const SizedBox(width: Insets.sm),
              ],
              // Whole-series watch actions, mirroring the per-season menu.
              PopupMenuButton<String>(
                tooltip: AppLocalizations.of(context).seriesActions,
                icon: Icon(
                  Icons.done_all_rounded,
                  color: context.scheme.onSurfaceVariant,
                ),
                onSelected: _seriesAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'watch',
                    child: ListTile(
                      leading: const Icon(Icons.done_all_rounded),
                      title: Text(AppLocalizations.of(context).markAllWatched),
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rewatch',
                    child: ListTile(
                      leading: const Icon(Icons.replay_rounded),
                      title: Text(AppLocalizations.of(context).rewatchSeries),
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'decrement',
                    child: ListTile(
                      leading: const Icon(Icons.exposure_minus_1_rounded),
                      title: Text(AppLocalizations.of(context).removeOneWatch),
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'unwatch',
                    child: ListTile(
                      leading: const Icon(Icons.remove_done_rounded),
                      title: Text(AppLocalizations.of(context).unmarkAll),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final s in seasons)
          _SeasonSection(
            seasonNumber: s,
            episodes: bySeason[s]!,
            counts: _counts,
            initiallyExpanded: seasons.length == 1 || s == expandSeason,
            onWatch: _watch,
            onUnwatch: _unwatch,
            onSeasonAction: _seasonAction,
            showImageUrl: _series!.imageUrl,
          ),
        const SizedBox(height: Insets.xxl),
      ],
    );
  }

  Widget _actionBar() {
    final rel = _rel!;
    return Row(
      children: [
        Expanded(
          child: rel.isFollowed
              ? FilledButton.tonalIcon(
                  onPressed: _toggleFollow,
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text(AppLocalizations.of(context).showFollowing),
                )
              : FilledButton.icon(
                  onPressed: _toggleFollow,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(AppLocalizations.of(context).follow),
                ),
        ),
        const SizedBox(width: Insets.sm),
        IconButton.filledTonal(
          onPressed: _toggleFavorite,
          isSelected: rel.isFavorited,
          icon: Icon(
            rel.isFavorited
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: rel.isFavorited ? context.colors.favorite : null,
          ),
          style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
        ),
        const SizedBox(width: Insets.sm),
        PopupMenuButton<String?>(
          tooltip: AppLocalizations.of(context).status,
          onSelected: (v) => _setStatus(v == 'clear' ? null : v),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'for_later',
              child: Text(AppLocalizations.of(context).forLater),
            ),
            PopupMenuItem(
              value: 'stopped',
              child: Text(AppLocalizations.of(context).stopWatching),
            ),
            PopupMenuItem(
              value: 'clear',
              child: Text(AppLocalizations.of(context).clearStatus),
            ),
          ],
          child: IconButton.filledTonal(
            onPressed: null,
            icon: Icon(
              rel.status == null
                  ? Icons.more_horiz_rounded
                  : Icons.bookmark_rounded,
            ),
            style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.series,
    required this.seenDistinct,
    required this.totalEpisodes,
    required this.onTapArtwork,
  });
  final Series series;
  final int seenDistinct;
  final int totalEpisodes;
  final VoidCallback onTapArtwork;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tap the backdrop (or the poster below) to browse the show's artworks.
          GestureDetector(
            onTap: onTapArtwork,
            child: NetImage(url: series.imageUrl),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  bg.withValues(alpha: 0.2),
                  bg.withValues(alpha: 0.55),
                  bg,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          Positioned(
            left: Insets.lg,
            right: Insets.lg,
            bottom: Insets.lg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 120,
                  child: GestureDetector(
                    onTap: onTapArtwork,
                    child: Poster(
                      url: series.imageUrl,
                      heroTag: 'series-${series.id}',
                    ),
                  ),
                ),
                const SizedBox(width: Insets.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(
                        series.name ??
                            AppLocalizations.of(
                              context,
                            ).showFallback(series.id),
                        style: context.text.headlineSmall,
                        maxLines: 3,
                      ),
                      const SizedBox(height: Insets.sm),
                      Wrap(
                        spacing: Insets.sm,
                        runSpacing: Insets.xs,
                        children: [
                          if (series.status != null)
                            Pill(label: series.status!),
                          if (series.year != null)
                            Pill(
                              label: '${series.year}',
                              color: context.scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                      const SizedBox(height: Insets.sm),
                      Text(
                        '$seenDistinct / $totalEpisodes ${AppLocalizations.of(context).episodesSeen}',
                        style: context.text.labelLarge?.copyWith(
                          color: context.colors.seen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A collapsible, clearly-tappable season card with a "mark whole season" toggle.
class _SeasonSection extends StatefulWidget {
  const _SeasonSection({
    required this.seasonNumber,
    required this.episodes,
    required this.counts,
    required this.initiallyExpanded,
    required this.onWatch,
    required this.onUnwatch,
    required this.onSeasonAction,
    this.showImageUrl,
  });
  final int seasonNumber;
  final List<Episode> episodes;
  final Map<int, int> counts;
  final bool initiallyExpanded;
  final void Function(int) onWatch;
  final void Function(int) onUnwatch;
  final void Function(int season, String action) onSeasonAction;
  final String? showImageUrl;

  @override
  State<_SeasonSection> createState() => _SeasonSectionState();
}

class _SeasonSectionState extends State<_SeasonSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final seen = widget.episodes
        .where((e) => (widget.counts[e.id] ?? 0) > 0)
        .length;
    final total = widget.episodes.length;
    // Complete passes through this season: the min ×N across its episodes (0 until
    // every episode is watched). Shown as a ×N badge; a single rewatched episode
    // does not raise it.
    final watchFloor = total == 0
        ? 0
        : widget.episodes
              .map((e) => widget.counts[e.id] ?? 0)
              .reduce((a, b) => a < b ? a : b);
    final label = widget.seasonNumber == 0
        ? AppLocalizations.of(context).specials
        : AppLocalizations.of(context).season(widget.seasonNumber);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.xs,
        Insets.lg,
        Insets.xs,
      ),
      child: Column(
        children: [
          // Tinted, clearly-clickable header.
          Material(
            color: context.scheme.surfaceContainerHighest,
            borderRadius: Radii.card,
            child: InkWell(
              borderRadius: Radii.card,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.lg,
                  vertical: Insets.md,
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: Motion.fast,
                      child: const Icon(Icons.chevron_right_rounded),
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(label, style: context.text.titleMedium),
                    ),
                    Text(
                      '$seen/$total',
                      style: context.text.labelMedium?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                    // Full-season watch count (replaces the plain "all watched" tick).
                    if (watchFloor >= 1) ...[
                      const SizedBox(width: Insets.sm),
                      CountBadge(count: watchFloor, size: 30),
                    ],
                    PopupMenuButton<String>(
                      tooltip: AppLocalizations.of(context).seasonActions,
                      icon: Icon(
                        Icons.done_all_rounded,
                        color: context.scheme.onSurfaceVariant,
                      ),
                      onSelected: (a) =>
                          widget.onSeasonAction(widget.seasonNumber, a),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'watch',
                          child: ListTile(
                            leading: const Icon(Icons.done_all_rounded),
                            title: Text(
                              AppLocalizations.of(context).markAllWatched,
                            ),
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'rewatch',
                          child: ListTile(
                            leading: const Icon(Icons.replay_rounded),
                            title: Text(
                              AppLocalizations.of(context).rewatchSeason,
                            ),
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'decrement',
                          child: ListTile(
                            leading: const Icon(Icons.exposure_minus_1_rounded),
                            title: Text(
                              AppLocalizations.of(context).removeOneWatch,
                            ),
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'unwatch',
                          child: ListTile(
                            leading: const Icon(Icons.remove_done_rounded),
                            title: Text(AppLocalizations.of(context).unmarkAll),
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Column(
                children: [
                  for (final e in widget.episodes)
                    _EpisodeCard(
                      episode: e,
                      count: widget.counts[e.id] ?? 0,
                      showImageUrl: widget.showImageUrl,
                      onWatch: () => widget.onWatch(e.id),
                      onUnwatch: () => widget.onUnwatch(e.id),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.count,
    required this.onWatch,
    required this.onUnwatch,
    this.showImageUrl,
  });
  final Episode episode;
  final int count;
  final VoidCallback onWatch;
  final VoidCallback onUnwatch;
  final String? showImageUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Material(
        color: context.scheme.surface,
        borderRadius: Radii.card,
        child: InkWell(
          borderRadius: Radii.card,
          onTap: () => _openSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(Insets.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: SizedBox(
                    width: 104,
                    height: 58,
                    child: NetImage(url: episode.imageUrl),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'E${episode.number ?? 0} · ${episode.name ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (episode.aired != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            episode.aired!,
                            style: context.text.labelSmall?.copyWith(
                              color: context.scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.sm),
                WatchControl(
                  count: count,
                  onWatch: onWatch,
                  onUnwatch: onUnwatch,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => EpisodeSheet(
        episode: episode,
        count: count,
        showImageUrl: showImageUrl,
        onWatch: onWatch,
        onUnwatch: onUnwatch,
      ),
    );
  }
}

/// Tier 1: at-a-glance metadata under the hero — genre chips, community rating,
/// a compact facts line, and a "more details" entry point.
class _MetaStrip extends StatefulWidget {
  const _MetaStrip({required this.details, required this.onMore});
  final SeriesDetails details;
  final VoidCallback onMore;
  @override
  State<_MetaStrip> createState() => _MetaStripState();
}

class _MetaStripState extends State<_MetaStrip> {
  bool _allGenres = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final muted = context.scheme.onSurfaceVariant;
    final details = widget.details;
    final facts = <String>[
      if ((details.seasonCount ?? 0) > 0) t.seasonsCount(details.seasonCount!),
      if ((details.runtime ?? 0) > 0) t.runtimeMinutes(details.runtime!),
      if (details.originalLanguage != null)
        langName(context, details.originalLanguage!),
    ];
    final shown = _allGenres ? details.genres : details.genres.take(4).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.genres.isNotEmpty)
            Wrap(
              spacing: Insets.xs,
              runSpacing: Insets.xs,
              children: [
                for (final g in shown) Pill(label: g),
                // Tap "+N" to reveal the rest of the genres in place.
                if (!_allGenres && details.genres.length > 4)
                  GestureDetector(
                    onTap: () => setState(() => _allGenres = true),
                    child: Pill(
                      label: '+${details.genres.length - 4}',
                      color: context.scheme.primary,
                    ),
                  ),
              ],
            ),
          if (details.communityRating != null || facts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Row(
                children: [
                  if (details.communityRating != null) ...[
                    RatingThumbBadge(
                      level: details.communityRating!.round().clamp(1, 5),
                      size: 17,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${details.communityRating!.toStringAsFixed(1)} / 5',
                      style: context.text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((details.ratingCount ?? 0) > 0)
                      Text(
                        ' (${details.ratingCount})',
                        style: context.text.labelMedium?.copyWith(color: muted),
                      ),
                    const SizedBox(width: Insets.md),
                  ],
                  Expanded(
                    child: Text(
                      facts.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onMore,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.moreDetails),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tier 2: full metadata in a bottom sheet.
class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({required this.details, this.seriesName});
  final SeriesDetails details;
  final String? seriesName;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = details;
    final rows = <Widget>[];
    void row(String label, String? value) {
      if (value == null || value.isEmpty) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(value, style: context.text.bodyMedium),
              ),
            ],
          ),
        ),
      );
    }

    void chips(String label, List<String> items) {
      if (items.isEmpty) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.text.labelMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.xs),
              Wrap(
                spacing: Insets.xs,
                runSpacing: Insets.xs,
                children: [for (final i in items) Pill(label: i)],
              ),
            ],
          ),
        ),
      );
    }

    if (d.communityRating != null) {
      row(
        t.communityRating,
        '${d.communityRating!.toStringAsFixed(1)} / 5${(d.ratingCount ?? 0) > 0 ? '  (${d.ratingCount})' : ''}',
      );
    }
    chips(t.genres, d.genres);
    chips(t.themes, d.tags);
    chips(t.networks, d.networks);
    chips(t.studios, d.studios);
    if (d.originalLanguage != null) {
      row(t.language, langName(context, d.originalLanguage!));
    }
    if (d.originalCountry != null) {
      row(t.country, countryName(context, d.originalCountry!));
    }
    if ((d.runtime ?? 0) > 0) {
      row(t.episodeLength, t.runtimeMinutes(d.runtime!));
    }
    if ((d.episodeCount ?? 0) > 0) {
      row(t.episodes, t.episodesCount(d.episodeCount!));
    }
    final aired = _airedRange(d.firstAired, d.lastAired);
    if (aired != null) row(t.aired, aired);
    chips(t.alsoKnownAs, d.aliases);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            0,
            Insets.lg,
            Insets.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      seriesName ?? t.showDetails,
                      style: context.text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),
              if (rows.isEmpty)
                Text(
                  t.nothingHereYet,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                )
              else
                ...rows,
            ],
          ),
        ),
      ),
    );
  }
}

/// "2016 – 2021", or "2016" if single year / one date known.
String? _airedRange(String? first, String? last) {
  final f = first?.split('-').first;
  final l = last?.split('-').first;
  if (f == null && l == null) return null;
  if (f != null && l != null && f != l) return '$f – $l';
  return f ?? l;
}
