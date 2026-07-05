import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
import '../widgets/poster.dart';
import '../widgets/states.dart';
import 'movie_detail_screen.dart';
import 'show_detail_screen.dart';

/// Review screen for uncertain import matches: a show whose TheTVDB id was dead, or
/// a movie whose title matched only approximately. We propose a best-guess and the
/// user confirms or dismisses; exact matches are imported without landing here.
class ImportMatchesScreen extends StatefulWidget {
  const ImportMatchesScreen({super.key});
  @override
  State<ImportMatchesScreen> createState() => _ImportMatchesScreenState();
}

class _ImportMatchesScreenState extends State<ImportMatchesScreen> {
  late Future<List<MatchSuggestion>> _future;
  // Keyed "type:id" — series and movie id spaces are separate, so a bare id could
  // collide between the two lists.
  final _resolving = <String>{};

  String _key(MatchSuggestion s) => '${s.entityType}:${s.id}';

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiClient>().importSuggestions(langs: context.read<SettingsController>().langsParam);
  }

  void _reload() {
    final f = context.read<ApiClient>().importSuggestions(langs: context.read<SettingsController>().langsParam);
    setState(() {
      _future = f;
    });
  }

  Future<void> _act(MatchSuggestion s, bool confirm) async {
    final api = context.read<ApiClient>();
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _resolving.add(_key(s)));
    try {
      if (confirm) {
        await api.confirmSuggestion(s.id, type: s.entityType);
      } else {
        await api.rejectSuggestion(s.id, type: s.entityType);
      }
      messenger.showSnackBar(SnackBar(
        content: Text(confirm ? t.matchedTo(s.suggestedName ?? t.seriesGeneric) : t.dismissedImport(s.importName)),
      ));
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _resolving.remove(_key(s)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.reviewImportMatches)),
      body: FutureBuilder<List<MatchSuggestion>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const LoadingView();
          if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _reload);
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return MessageView(
              icon: Icons.done_all_rounded,
              message: t.nothingToReview,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Insets.lg),
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: Text(
                    t.importMatchesIntro,
                    style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
                  ),
                );
              }
              return _SuggestionCard(
                s: items[i - 1],
                busy: _resolving.contains(_key(items[i - 1])),
                onConfirm: () => _act(items[i - 1], true),
                onReject: () => _act(items[i - 1], false),
              );
            },
          );
        },
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.s, required this.busy, required this.onConfirm, required this.onReject});
  final MatchSuggestion s;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      color: context.scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => s.isMovie
                          ? MovieDetailScreen(movieId: s.suggestedSeriesId)
                          : ShowDetailScreen(seriesId: s.suggestedSeriesId),
                    ),
                  ),
                  child: SizedBox(width: 54, height: 81, child: Poster(url: s.imageUrl, radius: Radii.sm)),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.youImported, style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant)),
                      Text(s.importName, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Insets.xs),
                      Row(children: [
                        Icon(Icons.arrow_downward_rounded, size: 14, color: context.colors.seen),
                        const SizedBox(width: 4),
                        Text(t.likelyMatch, style: context.text.labelSmall?.copyWith(color: context.colors.seen)),
                      ]),
                      Text(s.suggestedName ?? (s.isMovie ? s.importName : t.seriesWithId(s.suggestedSeriesId)),
                          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            if (busy)
              const Center(child: Padding(padding: EdgeInsets.all(Insets.xs), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(t.notIt),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(t.confirm),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
