import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
import '../widgets/badges.dart';
import '../widgets/episode_sheet.dart';
import '../widgets/poster.dart';
import '../widgets/states.dart';
import 'show_detail_screen.dart';

/// Calendar / Soon: upcoming & recently-aired episodes for followed shows.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // Each "show older" tap widens the recently-aired window by this many days, up
  // to [_recentMaxDays] (matching the backend clamp — a few months, no further).
  static const int _recentStepDays = 30;
  static const int _recentMaxDays = 180;

  List<CalendarItem>? _upcoming;
  List<CalendarItem>? _recent;
  Object? _error;
  bool _loading = true;
  // A "show older" fetch is in flight — keep the current list on screen, just
  // swap the button for a spinner (a full reload would blank the page).
  bool _loadingOlder = false;
  int _recentDays = _recentStepDays;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _langs => context.read<SettingsController>().langsParam;

  Future<void> _load() async {
    try {
      final (u, r) =
          await context.read<ApiClient>().calendar(langs: _langs, recentDays: _recentDays);
      if (!mounted) return;
      setState(() {
        _upcoming = u;
        _recent = r;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Pull-to-refresh: back to the default (last 30 days) window.
  Future<void> _reload() async {
    _recentDays = _recentStepDays;
    await _load();
  }

  /// Reach one step further into the past, keeping the current list visible.
  Future<void> _showOlder() async {
    if (_loadingOlder || _recentDays >= _recentMaxDays) return;
    setState(() {
      _recentDays = (_recentDays + _recentStepDays).clamp(0, _recentMaxDays);
      _loadingOlder = true;
    });
    await _load();
    if (mounted) setState(() => _loadingOlder = false);
  }

  // Stable anchor: the "Today" divider is the scroll view's center, so the page
  // opens with today at the top and the past laid out above it (scroll up to see).
  final _centerKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: _reload, child: _body(context));
  }

  Widget _body(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) return const _Fill(child: LoadingView());
    if (_error != null && _upcoming == null) {
      return _Fill(child: ErrorView(message: '$_error', onRetry: _reload));
    }
    final upcoming = _upcoming ?? const <CalendarItem>[]; // today + future (ASC)
    final recent = _recent ?? const <CalendarItem>[]; // strictly past (day DESC)
    final canGoOlder = _recentDays < _recentMaxDays;

    // Nothing anywhere and nothing left to page back to: the full-page empty state.
    if (upcoming.isEmpty && recent.isEmpty && !canGoOlder) {
      return _Fill(
        child: MessageView(
          icon: Icons.event_available_rounded,
          message: t.calendarEmpty,
        ),
      );
    }

    final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // `upcoming` starts at the server's "today"; peel those episodes off so they
    // sit directly under the (highlighted) Today chip, while every later day gets
    // its own date chip.
    final todayItems = [for (final it in upcoming) if (it.date == todayIso) it];
    final laterItems = [for (final it in upcoming) if (it.date != todayIso) it];

    // ABOVE today: past days, each led by a date chip, oldest at the very top.
    // Built in visual (top-to-bottom) order then reversed for the reverse-growth
    // pre-center sliver; the "show older" pager caps the top.
    final pastChildren = _groupByDay(_ascendingByDay(recent)).reversed.toList();
    if (canGoOlder) pastChildren.add(_olderButton(t));

    // TODAY and after: today's episodes (no chip — the Today chip is their header),
    // then each future day under its own date chip.
    final futureChildren = <Widget>[
      for (final it in todayItems) _CalendarRow(key: _rowKey(it), item: it),
      ..._groupByDay(laterItems),
    ];

    // One continuous timeline anchored on the Today chip (the CustomScrollView's
    // `center`): offset 0 puts today at the top, the past lays out above it, and
    // because the center is fixed, paging in older days never shifts the view.
    return CustomScrollView(
      center: _centerKey,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverList.list(children: pastChildren),
        SliverToBoxAdapter(
          key: _centerKey,
          child: _DateChip(date: todayIso, today: true),
        ),
        SliverList.list(children: futureChildren),
        const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)),
      ],
    );
  }

  /// Insert a [_DateChip] before the first episode of each day. `items` must be in
  /// the intended visual top-to-bottom order (ascending by day).
  List<Widget> _groupByDay(List<CalendarItem> items) {
    final out = <Widget>[];
    String? last;
    for (final it in items) {
      if (it.date != last) {
        out.add(_DateChip(date: it.date));
        last = it.date;
      }
      out.add(_CalendarRow(key: _rowKey(it), item: it));
    }
    return out;
  }

  /// A stable identity for an episode row so its (optimistic) watch state follows
  /// the episode across list changes (refresh / show older), not its position.
  Key _rowKey(CalendarItem it) => ValueKey(
        'ep-${it.episodeId ?? '${it.seriesId}:${it.date}:${it.episodeNumber}'}',
      );

  /// Flip a day-descending list (newest first, as the backend returns "recent")
  /// into day-ascending order, keeping each day's episodes in their original
  /// within-day order.
  List<CalendarItem> _ascendingByDay(List<CalendarItem> descByDay) {
    final groups = <List<CalendarItem>>[];
    String? cur;
    for (final it in descByDay) {
      if (groups.isEmpty || it.date != cur) {
        groups.add(<CalendarItem>[it]);
        cur = it.date;
      } else {
        groups.last.add(it);
      }
    }
    return [for (final g in groups.reversed) ...g];
  }

  Widget _olderButton(AppLocalizations t) => Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Insets.md,
          horizontal: Insets.lg,
        ),
        child: Center(
          child: _loadingOlder
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton.icon(
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: Text(t.showOlder),
                  onPressed: _showOlder,
                ),
        ),
      );
}

class _CalendarRow extends StatefulWidget {
  const _CalendarRow({super.key, required this.item});
  final CalendarItem item;
  @override
  State<_CalendarRow> createState() => _CalendarRowState();
}

class _CalendarRowState extends State<_CalendarRow> {
  late int _count = widget.item.watchedCount;

  CalendarItem get item => widget.item;

  @override
  void didUpdateWidget(covariant _CalendarRow old) {
    super.didUpdateWidget(old);
    // A fresh calendar load (refresh / show older) swapped in new server data for
    // this row; adopt the authoritative count.
    if (item.episodeId != old.item.episodeId ||
        item.watchedCount != old.item.watchedCount) {
      _count = item.watchedCount;
    }
  }

  /// "S4E12" — omitted entirely if we have neither number.
  String? get _epTag {
    final s = item.seasonNumber, e = item.episodeNumber;
    if (s == null && e == null) return null;
    return 'S${s ?? '?'}E${e ?? '?'}';
  }

  /// "Mon 12 Aug · 22:30" — date first, release time appended when known.
  String _when(BuildContext context) {
    final parts = <String>[];
    if (item.date != null) parts.add(_prettyDate(context, item.date!));
    if (item.time != null && item.time!.isNotEmpty) parts.add(item.time!);
    return parts.join(' · ');
  }

  /// An episode can be marked watched once it has aired (today or earlier) and we
  /// have its id. Not-yet-aired rows show a countdown instead.
  bool get _available {
    final iso = item.date;
    if (item.episodeId == null || iso == null) return false;
    final d = DateTime.tryParse(iso);
    if (d == null) return false;
    final now = DateTime.now();
    return !DateTime(
      d.year,
      d.month,
      d.day,
    ).isAfter(DateTime(now.year, now.month, now.day));
  }

  Future<void> _watch() async {
    final id = item.episodeId;
    if (id == null) return;
    setState(() => _count += 1);
    try {
      await context.read<ApiClient>().watch(id);
    } catch (_) {
      if (mounted) setState(() => _count = _count > 0 ? _count - 1 : 0);
    }
  }

  Future<void> _unwatch() async {
    final id = item.episodeId;
    if (id == null || _count == 0) return;
    setState(() => _count -= 1);
    try {
      await context.read<ApiClient>().unwatch(id);
    } catch (_) {
      if (mounted) setState(() => _count += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tag = _epTag;
    // Second line: "S4E12 · Episode name" (either part optional).
    final epParts = <String>[?tag, ?item.episodeName];
    final epLine = epParts.join(' · ');
    final muted = context.scheme.onSurfaceVariant;

    return ListTile(
      isThreeLine: epLine.isNotEmpty,
      leading: SizedBox(width: 42, height: 63, child: Poster(url: item.imageUrl, radius: Radii.sm)),
      // Tapping the row (outside the watch control) opens the episode sheet; the
      // show is reached from there (tap the show name inside the sheet).
      title: Text(item.name ?? AppLocalizations.of(context).seriesFallback(item.seriesId),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (epLine.isNotEmpty)
            Text(epLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (_when(context).isNotEmpty)
            Text(_when(context), style: context.text.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w500)),
        ],
      ),
      // Aired episodes get the same inline watch control as the show's episode
      // list; not-yet-aired ones keep the countdown.
      trailing: _available
          ? WatchControl(count: _count, onWatch: _watch, onUnwatch: _unwatch)
          : _countdown(context),
      onTap: () => _openEpisode(context),
    );
  }

  /// Episode-focused bottom sheet: the same rich sheet shown from a show's
  /// episode list (still, overview, watch controls). Seeded with the row's current
  /// count and kept in sync so watching there reflects back on the row.
  void _openEpisode(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CalendarEpisodeSheet(
        item: item,
        initialCount: _count,
        onCountChanged: (c) {
          if (mounted) setState(() => _count = c);
        },
      ),
    );
  }

  /// A right-aligned "N days" countdown to air (big number over a "days" caption),
  /// TV Time style. Null when the date is unknown/in the past.
  Widget? _countdown(BuildContext context) {
    final iso = item.date;
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    if (d == null) return null;
    final now = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 0) return null;
    final t = AppLocalizations.of(context);
    final (String value, String unit) = days == 0 ? (t.today, '') : ('$days', days == 1 ? t.day : t.days);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: context.scheme.primary)),
        if (unit.isNotEmpty)
          Text(unit, style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// "2026-08-12" -> "12 Aug 2026"; returns the raw string if it doesn't parse.
String _prettyDate(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMd(locale).format(d);
}

/// "2026-08-12" -> "August 12, 2026" (full month, for the day-separator chips).
String _prettyDateLong(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMMd(locale).format(d);
}

/// A day separator between rows: a centered date chip flanked by hairline rules.
/// `today` highlights it (it also serves as the timeline's scroll anchor).
class _DateChip extends StatelessWidget {
  const _DateChip({required this.date, this.today = false});
  final String? date;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pretty = date == null ? null : _prettyDateLong(context, date!);
    final label = today ? [t.today, ?pretty].join(' · ') : (pretty ?? '');
    final accent = today ? context.scheme.primary : context.scheme.onSurfaceVariant;
    final rule = Expanded(
      child: Divider(color: accent.withValues(alpha: 0.2)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, Insets.md),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.sm,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: today ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (today) ...[
                    Icon(Icons.today_rounded, size: 18, color: accent),
                    const SizedBox(width: Insets.sm),
                  ],
                  Text(
                    label,
                    style: context.text.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          rule,
        ],
      ),
    );
  }
}

/// Wraps a widget in a scrollable so pull-to-refresh works on empty/loading.
class _Fill extends StatelessWidget {
  const _Fill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.3), child],
      );
}

/// Loads the full episode (overview / still) and current watch count for a
/// calendar item, then shows the shared [EpisodeSheet]. Starts from what the
/// calendar already knows so the sheet appears instantly, enriching once the
/// series' episodes load.
class _CalendarEpisodeSheet extends StatefulWidget {
  const _CalendarEpisodeSheet({
    required this.item,
    required this.initialCount,
    this.onCountChanged,
  });
  final CalendarItem item;
  final int initialCount;

  /// Reports the live watch count back to the row so its inline control stays in
  /// sync when the user watches/unwatches from inside the sheet.
  final ValueChanged<int>? onCountChanged;

  @override
  State<_CalendarEpisodeSheet> createState() => _CalendarEpisodeSheetState();
}

class _CalendarEpisodeSheetState extends State<_CalendarEpisodeSheet> {
  late Episode _episode;
  late int _count = widget.initialCount;
  bool _touched = false; // once the user taps watch/unwatch, don't clobber _count

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    // No episode still yet — the calendar only carries the series art, which is
    // passed to EpisodeSheet as the fallback. The real still fills in on _load.
    _episode = Episode(
      id: it.episodeId ?? -1,
      seasonNumber: it.seasonNumber,
      number: it.episodeNumber,
      name: it.episodeName,
      aired: it.date,
    );
    _load();
  }

  /// Update the count and mirror it back to the row.
  void _setCount(int v) {
    if (!mounted) return;
    setState(() => _count = v);
    widget.onCountChanged?.call(v);
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final langs = context.read<SettingsController>().langsParam;
    try {
      final results = await Future.wait([
        api.episodes(widget.item.seriesId, langs: langs),
        api.seenCounts(widget.item.seriesId),
      ]);
      if (!mounted) return;
      final eps = results[0] as List<Episode>;
      final counts = results[1] as Map<int, int>;
      Episode? full;
      for (final e in eps) {
        if (e.id == widget.item.episodeId) {
          full = e;
          break;
        }
      }
      setState(() {
        if (full != null) _episode = full;
      });
      // Reconcile to the server's authoritative count (unless the user already
      // acted here), keeping the row in sync too.
      if (!_touched) _setCount(counts[widget.item.episodeId] ?? 0);
    } catch (_) {
      // Keep the provisional episode; the watch controls still work.
    }
  }

  Future<void> _watch() async {
    final id = widget.item.episodeId;
    if (id == null) return;
    final prev = _count;
    _touched = true;
    _setCount(_count + 1);
    try {
      await context.read<ApiClient>().watch(id);
    } catch (_) {
      _setCount(prev);
    }
  }

  Future<void> _unwatch() async {
    final id = widget.item.episodeId;
    if (id == null || _count == 0) return;
    final prev = _count;
    _touched = true;
    _setCount(_count - 1);
    try {
      await context.read<ApiClient>().unwatch(id);
    } catch (_) {
      _setCount(prev);
    }
  }

  @override
  Widget build(BuildContext context) => EpisodeSheet(
        episode: _episode,
        count: _count,
        showImageUrl: widget.item.imageUrl,
        showName: widget.item.name ?? AppLocalizations.of(context).seriesFallback(widget.item.seriesId),
        onOpenShow: () {
          // Close the sheet, then open the full show page.
          final nav = Navigator.of(context);
          nav.pop();
          nav.push(MaterialPageRoute(builder: (_) => ShowDetailScreen(seriesId: widget.item.seriesId)));
        },
        onWatch: _watch,
        onUnwatch: _unwatch,
      );
}
