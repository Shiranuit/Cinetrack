import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
import '../widgets/episode_sheet.dart';
import '../widgets/poster.dart';
import '../widgets/section.dart';
import '../widgets/states.dart';
import 'show_detail_screen.dart';

/// Calendar / Soon: upcoming & recently-aired episodes for followed shows.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late Future<(List<CalendarItem>, List<CalendarItem>)> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiClient>().calendar(langs: _langs);
  }

  String get _langs => context.read<SettingsController>().langsParam;

  Future<void> _reload() async {
    final f = context.read<ApiClient>().calendar(langs: _langs);
    setState(() {
      _future = f;
    });
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<(List<CalendarItem>, List<CalendarItem>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _Fill(child: LoadingView());
          }
          if (snap.hasError) return _Fill(child: ErrorView(message: '${snap.error}', onRetry: _reload));
          final (upcoming, recent) = snap.data!;
          if (upcoming.isEmpty && recent.isEmpty) {
            return _Fill(
              child: MessageView(
                icon: Icons.event_available_rounded,
                message: AppLocalizations.of(context).calendarEmpty,
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: Insets.xxl),
            children: [
              if (upcoming.isNotEmpty) ...[
                SectionHeader(title: AppLocalizations.of(context).upcoming, icon: Icons.upcoming_rounded),
                for (final it in upcoming) _CalendarRow(item: it),
              ],
              if (recent.isNotEmpty) ...[
                SectionHeader(title: AppLocalizations.of(context).recentlyAired, icon: Icons.history_rounded, accent: context.colors.warning),
                for (final it in recent) _CalendarRow(item: it),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({required this.item});
  final CalendarItem item;

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
      // Tapping the row opens the episode sheet; the show is reached from there
      // (tap the show name inside the sheet).
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
      trailing: _countdown(context),
      onTap: () => _openEpisode(context),
    );
  }

  /// Episode-focused bottom sheet: the same rich sheet shown from a show's
  /// episode list (still, overview, watch controls).
  void _openEpisode(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CalendarEpisodeSheet(item: item),
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
  const _CalendarEpisodeSheet({required this.item});
  final CalendarItem item;
  @override
  State<_CalendarEpisodeSheet> createState() => _CalendarEpisodeSheetState();
}

class _CalendarEpisodeSheetState extends State<_CalendarEpisodeSheet> {
  late Episode _episode;
  int _count = 0;
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
        if (!_touched) _count = counts[widget.item.episodeId] ?? 0;
      });
    } catch (_) {
      // Keep the provisional episode; the watch controls still work.
    }
  }

  Future<void> _watch() async {
    final id = widget.item.episodeId;
    if (id == null) return;
    setState(() {
      _touched = true;
      _count += 1;
    });
    try {
      await context.read<ApiClient>().watch(id);
    } catch (_) {
      if (mounted) setState(() => _count = _count > 0 ? _count - 1 : 0);
    }
  }

  Future<void> _unwatch() async {
    final id = widget.item.episodeId;
    if (id == null || _count == 0) return;
    setState(() {
      _touched = true;
      _count -= 1;
    });
    try {
      await context.read<ApiClient>().unwatch(id);
    } catch (_) {
      if (mounted) setState(() => _count += 1);
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
