import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
import '../widgets/badges.dart';
import '../widgets/episode_sheet.dart';
import '../widgets/net_image.dart';
import '../widgets/poster.dart';
import '../widgets/rating_bar.dart';
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
    try {
      final r = await Future.wait([
        _api.series(widget.seriesId, lang: _langs.split(',').first),
        _api.showRelation(widget.seriesId, langs: _langs),
        _api.episodes(widget.seriesId, lang: _langs.split(',').first),
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

  Future<void> _refreshRel() async {
    final rel = await _api.showRelation(widget.seriesId, langs: _langs);
    if (mounted) setState(() => _rel = rel);
  }

  Future<void> _toggleFollow() async {
    await _api.setFollow(widget.seriesId, !(_rel?.isFollowed ?? false));
    await _refreshRel();
  }

  Future<void> _toggleFavorite() async {
    await _api.setFavorite(widget.seriesId, !(_rel?.isFavorited ?? false));
    await _refreshRel();
  }

  Future<void> _setStatus(String? status) async {
    await _api.setStatus(widget.seriesId, status);
    await _refreshRel();
  }

  Future<void> _rate(int? rating) async {
    // Optimistic: reflect immediately, then persist.
    setState(() => _rel = _rel == null
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
          ));
    await _api.rateShow(widget.seriesId, rating);
    await _refreshRel();
  }

  Widget _ratingRow() {
    final r = _rel?.rating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0),
      child: Row(
        children: [
          Text(r == null ? AppLocalizations.of(context).rateThisShow : AppLocalizations.of(context).yourRating(r),
              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          Flexible(child: RatingBar(value: r, onRate: _rate)),
        ],
      ),
    );
  }

  Future<void> _watch(int episodeId) async {
    setState(() => _counts[episodeId] = (_counts[episodeId] ?? 0) + 1);
    try {
      await _api.watch(episodeId);
      _refreshRel();
    } catch (e) {
      if (mounted) setState(() => _counts[episodeId] = (_counts[episodeId] ?? 1) - 1);
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
    try {
      switch (action) {
        case 'watch':
          await _api.watchSeason(widget.seriesId, season);
        case 'rewatch':
          await _api.rewatchSeason(widget.seriesId, season);
        case 'unwatch':
          await _api.unwatchSeason(widget.seriesId, season);
      }
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
              : Stack(children: [RefreshIndicator(onRefresh: _load, child: _content()), _backButton()]),
    );
  }

  Widget _backButton() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Insets.sm),
          child: CircleAvatar(
            backgroundColor: context.colors.scrim.withValues(alpha: 0.55),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
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
    bool fullyWatched(int s) => bySeason[s]!.every((e) => (_counts[e.id] ?? 0) > 0);
    // Auto-expand only the FIRST not-fully-watched season (in display order).
    final int? expandSeason = seasons.cast<int?>().firstWhere((s) => !fullyWatched(s!), orElse: () => null);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Hero(series: _series!, seenDistinct: _seenDistinct, totalEpisodes: _episodes.length),
        Padding(padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0), child: _actionBar()),
        _ratingRow(),
        if (_series!.overview?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0),
            child: Text(_series!.overview!, style: context.text.bodyMedium?.copyWith(height: 1.5)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.xl, Insets.lg, Insets.sm),
          child: Text(AppLocalizations.of(context).episodes, style: context.text.titleLarge),
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
                  onPressed: _toggleFollow, icon: const Icon(Icons.check_rounded, size: 20), label: Text(AppLocalizations.of(context).showFollowing))
              : FilledButton.icon(
                  onPressed: _toggleFollow, icon: const Icon(Icons.add_rounded, size: 20), label: Text(AppLocalizations.of(context).follow)),
        ),
        const SizedBox(width: Insets.sm),
        IconButton.filledTonal(
          onPressed: _toggleFavorite,
          isSelected: rel.isFavorited,
          icon: Icon(rel.isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: rel.isFavorited ? context.colors.favorite : null),
          style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
        ),
        const SizedBox(width: Insets.sm),
        PopupMenuButton<String?>(
          tooltip: AppLocalizations.of(context).status,
          onSelected: (v) => _setStatus(v == 'clear' ? null : v),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'for_later', child: Text(AppLocalizations.of(context).forLater)),
            PopupMenuItem(value: 'stopped', child: Text(AppLocalizations.of(context).stopWatching)),
            PopupMenuItem(value: 'clear', child: Text(AppLocalizations.of(context).clearStatus)),
          ],
          child: IconButton.filledTonal(
            onPressed: null,
            icon: Icon(rel.status == null ? Icons.more_horiz_rounded : Icons.bookmark_rounded),
            style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.series, required this.seenDistinct, required this.totalEpisodes});
  final Series series;
  final int seenDistinct;
  final int totalEpisodes;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: NetImage(url: series.imageUrl),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0.2), bg.withValues(alpha: 0.55), bg],
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
                SizedBox(width: 120, child: Poster(url: series.imageUrl, heroTag: 'series-${series.id}')),
                const SizedBox(width: Insets.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(series.name ?? AppLocalizations.of(context).showFallback(series.id),
                          style: context.text.headlineSmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Insets.sm),
                      Wrap(spacing: Insets.sm, runSpacing: Insets.xs, children: [
                        if (series.status != null) Pill(label: series.status!),
                        if (series.year != null) Pill(label: '${series.year}', color: context.scheme.onSurfaceVariant),
                      ]),
                      const SizedBox(height: Insets.sm),
                      Text('$seenDistinct / $totalEpisodes ${AppLocalizations.of(context).episodesSeen}',
                          style: context.text.labelLarge?.copyWith(color: context.colors.seen)),
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
    final seen = widget.episodes.where((e) => (widget.counts[e.id] ?? 0) > 0).length;
    final total = widget.episodes.length;
    final allSeen = seen == total && total > 0;
    final label = widget.seasonNumber == 0
        ? AppLocalizations.of(context).specials
        : AppLocalizations.of(context).season(widget.seasonNumber);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.xs, Insets.lg, Insets.xs),
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
                padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.md),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: Motion.fast,
                      child: const Icon(Icons.chevron_right_rounded),
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(child: Text(label, style: context.text.titleMedium)),
                    Text('$seen/$total',
                        style: context.text.labelMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
                    PopupMenuButton<String>(
                      tooltip: AppLocalizations.of(context).seasonActions,
                      icon: Icon(
                        allSeen ? Icons.check_circle_rounded : Icons.done_all_rounded,
                        color: allSeen ? context.colors.seen : context.scheme.onSurfaceVariant,
                      ),
                      onSelected: (a) => widget.onSeasonAction(widget.seasonNumber, a),
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'watch', child: ListTile(leading: const Icon(Icons.done_all_rounded), title: Text(AppLocalizations.of(context).markAllWatched), dense: true)),
                        PopupMenuItem(value: 'rewatch', child: ListTile(leading: const Icon(Icons.replay_rounded), title: Text(AppLocalizations.of(context).rewatchSeason), dense: true)),
                        PopupMenuItem(value: 'unwatch', child: ListTile(leading: const Icon(Icons.remove_done_rounded), title: Text(AppLocalizations.of(context).unmarkAll), dense: true)),
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
  const _EpisodeCard({required this.episode, required this.count, required this.onWatch, required this.onUnwatch, this.showImageUrl});
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
                  child: SizedBox(width: 104, height: 58, child: NetImage(url: episode.imageUrl)),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('E${episode.number ?? 0} · ${episode.name ?? ''}',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (episode.aired != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(episode.aired!,
                              style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.sm),
                WatchControl(count: count, onWatch: onWatch, onUnwatch: onUnwatch),
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
      builder: (_) => EpisodeSheet(episode: episode, count: count, showImageUrl: showImageUrl, onWatch: onWatch, onUnwatch: onUnwatch),
    );
  }
}

