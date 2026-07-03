import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/filters.dart';
import '../api/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/infinite_grid.dart';
import '../widgets/show_card.dart';
import '../widgets/states.dart';
import 'movie_detail_screen.dart';
import 'show_detail_screen.dart';

const _types = {'series': 'Series', 'anime': 'Anime', 'movie': 'Movies'};

/// Discover: advanced browse/filter over the mirrored catalog.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _f = AdvancedFilters();
  FilterOptions _options = const FilterOptions();
  // Bumping this resets the infinite grid to the first page (kinds/filters changed).
  int _reloadToken = 0;
  // The type toggles are multi-select and combinable; all on by default.
  Set<String> _kinds = {'series', 'anime', 'movie'};

  @override
  void initState() {
    super.initState();
    context
        .read<ApiClient>()
        .filterOptions()
        .then((o) {
          if (mounted) setState(() => _options = o);
        })
        .catchError((_) {});
  }

  /// The backend kinds to query for the current selection. "series" already
  /// includes anime, so we only query "anime" separately when "series" is off.
  List<String> _backendKinds() {
    final k = <String>[];
    if (_kinds.contains('series')) {
      k.add('series');
    } else if (_kinds.contains('anime')) {
      k.add('anime');
    }
    if (_kinds.contains('movie')) k.add('movie');
    return k;
  }

  /// One page: fan out over the selected kinds at this offset and merge (each
  /// result carries its own `kind`, so navigation stays correct in the mixed grid).
  Future<List<SearchResult>> _pageFetch(int offset, int limit) async {
    final kinds = _backendKinds();
    if (kinds.isEmpty) return [];
    final api = context.read<ApiClient>();
    final langs = context.read<SettingsController>().langsParam;
    final lists = await Future.wait(
        kinds.map((k) => api.filteredSearch(_f, type: k, langs: langs, offset: offset, limit: limit)));
    return [for (final l in lists) ...l];
  }

  void _reload() => setState(() => _reloadToken++);

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(filters: _f, options: _options),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String typeLabel(String key) => switch (key) {
          'series' => t.typeSeries,
          'anime' => t.typeAnime,
          'movie' => t.typeMovies,
          _ => key,
        };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.sm,
            Insets.lg,
            Insets.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  multiSelectionEnabled: true,
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    for (final e in _types.entries)
                      ButtonSegment(
                        value: e.key,
                        label: Text(typeLabel(e.key),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade),
                      ),
                  ],
                  selected: _kinds,
                  onSelectionChanged: (s) {
                    setState(() => _kinds = s);
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: Insets.sm),
              Badge(
                isLabelVisible: _f.activeCount > 0,
                label: Text('${_f.activeCount}'),
                child: OutlinedButton.icon(
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(t.filters),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: InfiniteGrid(
            resetKey: _reloadToken,
            fetchPage: _pageFetch,
            empty: const MessageView(
              icon: Icons.auto_awesome_rounded,
              message: 'No matches in your catalog yet.\nImport or search shows to fill it, then filter here.',
            ),
            itemBuilder: (context, r) => ShowCard(
              title: r.name ?? '—',
              imageUrl: r.imageUrl,
              subtitle: r.year?.toString(),
              onTap: r.tvdbId == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => r.kind == 'movie'
                          ? MovieDetailScreen(movieId: r.tvdbId!)
                          : ShowDetailScreen(seriesId: r.tvdbId!))),
            ),
          ),
        ),
      ],
    );
  }
}
