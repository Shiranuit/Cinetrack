import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
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
            return const _Fill(
              child: MessageView(
                icon: Icons.event_available_rounded,
                message: 'Nothing scheduled.\nFollow airing shows to see them here.',
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
  String get _when {
    final parts = <String>[];
    if (item.date != null) parts.add(_prettyDate(item.date!));
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
      // Tapping the show NAME opens the show; tapping anywhere else opens the episode.
      title: GestureDetector(
        onTap: () => _openShow(context),
        child: Text(item.name ?? 'Series ${item.seriesId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (epLine.isNotEmpty)
            Text(epLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (_when.isNotEmpty)
            Text(_when, style: context.text.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w500)),
        ],
      ),
      trailing: _countdown(context),
      onTap: () => _openEpisode(context),
    );
  }

  void _openShow(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ShowDetailScreen(seriesId: item.seriesId)),
      );

  /// Episode-focused bottom sheet: details + mark-watched + open-show.
  void _openEpisode(BuildContext context) {
    final tag = _epTag;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name ?? 'Series ${item.seriesId}',
                  style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Insets.xs),
              Text([?tag, ?item.episodeName].join(' · '),
                  style: context.text.titleSmall?.copyWith(color: context.scheme.primary)),
              if (_when.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Insets.xs),
                  child: Text(_when, style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
                ),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  if (item.episodeId != null)
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(AppLocalizations.of(context).markWatched),
                        onPressed: () {
                          final messenger = ScaffoldMessenger.of(context);
                          final markedMsg = AppLocalizations.of(context).markedWatched;
                          context.read<ApiClient>().watch(item.episodeId!).then((_) {
                            messenger.showSnackBar(SnackBar(content: Text(markedMsg)));
                          }).catchError((e) {
                            messenger.showSnackBar(SnackBar(content: Text('$e')));
                          });
                          Navigator.of(sheetCtx).pop();
                        },
                      ),
                    ),
                  if (item.episodeId != null) const SizedBox(width: Insets.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(AppLocalizations.of(context).openShow),
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        _openShow(context);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
    final (String value, String unit) = days == 0 ? ('Today', '') : ('$days', days == 1 ? 'day' : 'days');
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

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "2026-08-12" -> "12 Aug 2026"; returns the raw string if it doesn't parse.
String _prettyDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
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
