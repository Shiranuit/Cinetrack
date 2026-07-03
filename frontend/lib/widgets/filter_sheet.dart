import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:world_countries/world_countries.dart';

import '../api/filters.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';

const kSorts = {
  'popularity': 'Popular',
  'rating': 'Top rated',
  'year': 'Release date',
  'updated': 'Last updated',
  'seasons': 'Seasons',
  'episodes': 'Episodes',
  'runtime': 'Longest',
  'name': 'A–Z',
};

// TheTVDB uses ISO 639-2 (3-letter) language codes, but CLDR (via
// flutter_localized_locales) is keyed by 2-letter — map the common ones. Names
// then come back localized in the user's UI language for free.
const _iso639 = {
  'eng': 'en', 'jpn': 'ja', 'fra': 'fr', 'deu': 'de', 'spa': 'es', 'ita': 'it', 'por': 'pt', 'kor': 'ko',
  'zho': 'zh', 'zhtw': 'zh', 'rus': 'ru', 'ara': 'ar', 'hin': 'hi', 'nld': 'nl', 'swe': 'sv', 'nor': 'no',
  'dan': 'da', 'fin': 'fi', 'pol': 'pl', 'tur': 'tr', 'tha': 'th', 'vie': 'vi', 'heb': 'he', 'hun': 'hu',
  'ces': 'cs', 'ell': 'el', 'ukr': 'uk', 'ron': 'ro', 'ind': 'id', 'fas': 'fa', 'cat': 'ca', 'tgl': 'tl',
  'msa': 'ms',
};
String _langName(BuildContext context, String code) {
  final two = _iso639[code] ?? (code.length == 2 ? code : null);
  final name = two == null ? null : LocaleNames.of(context)?.nameOf(two);
  return name ?? code.toUpperCase();
}

// TheTVDB gives ISO 3166 alpha-3 codes (lowercase, e.g. "usa", "jpn"). Resolve
// to a WorldCountry and read its name translated for the current UI locale
// (via world_countries' TypedLocaleDelegate). Falls back to the English common
// name, then the raw code, when a code is unknown or untranslated.
String _countryName(BuildContext context, String code) {
  final country = WorldCountry.maybeFromCode(code.toUpperCase());
  if (country == null) return code.toUpperCase();
  return context.maybeLocale?.maps.countryTranslations[country] ?? country.name.common;
}

/// Advanced-filter bottom sheet, shared by Discover and the Library filter.
/// Mutates [filters] in place; the caller reloads results on dismiss.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.filters, required this.options, this.showFavorites = false});
  final AdvancedFilters filters;
  final FilterOptions options;
  /// Whether to offer the "Favorites only" toggle (library filter only).
  final bool showFavorites;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  AdvancedFilters get f => widget.filters;
  FilterOptions get o => widget.options;

  static const _runtimeBuckets = <(String, int?, int?)>[
    ('Any', null, null),
    ('< 30m', null, 29),
    ('30–60m', 30, 60),
    ('> 60m', 61, null),
  ];
  bool _isRuntime(int? min, int? max) => f.runtimeMin == min && f.runtimeMax == max;

  @override
  Widget build(BuildContext context) {
    final thisYear = DateTime.now().year;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.xxl),
        children: [
          Row(
            children: [
              Text('Filters', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(onPressed: () => setState(f.reset), child: Text(AppLocalizations.of(context).reset)),
            ],
          ),

          if (widget.showFavorites)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: FilterChip(
                avatar: Icon(Icons.favorite_rounded, size: 18, color: f.favoritesOnly ? context.colors.favorite : null),
                label: Text(AppLocalizations.of(context).favoritesOnly),
                selected: f.favoritesOnly,
                onSelected: (v) => setState(() => f.favoritesOnly = v),
              ),
            ),

          _label(context, AppLocalizations.of(context).sortBy),
          Wrap(spacing: Insets.sm, children: [
            for (final e in kSorts.entries)
              ChoiceChip(label: Text(e.value), selected: f.sort == e.key, onSelected: (_) => setState(() => f.sort = e.key)),
          ]),

          // Every option facet is a collapsible section (see [_ChipSection]).
          if (o.genres.isNotEmpty)
            _triSection('Genres', [for (final g in o.genres) (g.id, g.name)], f.genresInc, f.genresExc),
          if (o.statuses.isNotEmpty)
            _multiSection<String>('Status', [for (final s in o.statuses) (s, s)], f.statuses),
          if (o.languages.isNotEmpty)
            _multiSection<String>(AppLocalizations.of(context).filterOrigLanguage,
                [for (final c in o.languages) (c, _langName(context, c))], f.originalLanguages),
          if (o.countries.isNotEmpty)
            _multiSection<String>(AppLocalizations.of(context).filterOrigCountry,
                [for (final c in o.countries) (c, _countryName(context, c))], f.originalCountries),

          if (o.tags.isNotEmpty)
            _triSection('Themes', [for (final t in o.tags) (t.id, t.name)], f.tagsInc, f.tagsExc),
          if (o.networks.isNotEmpty)
            _multiSection<int>('Networks', [for (final c in o.networks) (c.id, c.name)], f.networks),
          if (o.studios.isNotEmpty)
            _multiSection<int>('Studios', [for (final c in o.studios) (c.id, c.name)], f.studios),

          _rangeSection(context, 'Release year', f.years ?? RangeValues(1950, thisYear.toDouble()),
              1950, thisYear.toDouble(), (v) => f.years = v, () => f.years = null, f.years != null),
          _rangeSection(context, 'Seasons', f.seasons ?? const RangeValues(1, 20), 1, 20,
              (v) => f.seasons = v, () => f.seasons = null, f.seasons != null),
          _rangeSection(context, 'Episodes', f.episodes ?? const RangeValues(0, 1000), 0, 1000,
              (v) => f.episodes = v, () => f.episodes = null, f.episodes != null, step: 25),

          _label(context, 'Episode / runtime length'),
          Wrap(spacing: Insets.sm, children: [
            for (final b in _runtimeBuckets)
              ChoiceChip(
                label: Text(b.$1),
                selected: _isRuntime(b.$2, b.$3),
                onSelected: (_) => setState(() {
                  f.runtimeMin = b.$2;
                  f.runtimeMax = b.$3;
                }),
              ),
          ]),

          const SizedBox(height: Insets.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('${AppLocalizations.of(context).showResults}${f.activeCount > 0 ? ' · ${f.activeCount}' : ''}'),
          ),
        ],
      ),
    );
  }

  // ---- section builders ----

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.sm),
        child: Text(text, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      );

  Widget _rangeSection(BuildContext context, String title, RangeValues values, double min, double max,
      void Function(RangeValues) onChange, VoidCallback onClear, bool active,
      {double step = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.xs),
          child: Row(children: [
            Text('$title  ·  ${values.start.round()}–${values.end.round()}',
                style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (active) TextButton(onPressed: () => setState(onClear), child: Text(AppLocalizations.of(context).clear)),
          ]),
        ),
        RangeSlider(
          values: values,
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          labels: RangeLabels('${values.start.round()}', '${values.end.round()}'),
          onChanged: (v) => setState(() => onChange(v)),
        ),
      ],
    );
  }

  /// Collapsible section of tri-state chips (include → exclude → off): genres, themes.
  Widget _triSection(String title, List<(int, String)> items, Set<int> inc, Set<int> exc) =>
      _ChipSection<int>(
        title: title,
        subtitle: 'tap: include → exclude → off',
        items: items,
        selectedCount: inc.length + exc.length,
        chipBuilder: (id, name) => _triChip(name, inc, exc, id),
      );

  /// Collapsible section of multi-select chips: status, language, country, networks, studios.
  Widget _multiSection<K>(String title, List<(K, String)> items, Set<K> selected) => _ChipSection<K>(
        title: title,
        items: items,
        selectedCount: selected.length,
        chipBuilder: (key, name) => _multiChip(name, selected.contains(key), () => setState(() => selected.toggle(key))),
      );

  // ---- chip primitives ----

  Widget _triChip(String name, Set<int> inc, Set<int> exc, int id) {
    final state = inc.contains(id) ? 1 : (exc.contains(id) ? 2 : 0);
    final (Color? bg, Color? fg, IconData? icon) = switch (state) {
      1 => (context.colors.seen.withValues(alpha: 0.22), context.colors.seen, Icons.add_rounded),
      2 => (context.scheme.error.withValues(alpha: 0.20), context.scheme.error, Icons.remove_rounded),
      _ => (null, null, null),
    };
    return GestureDetector(
      onTap: () => setState(() {
        // off → include → exclude → off
        if (inc.remove(id)) {
          exc.add(id);
        } else if (exc.remove(id)) {
        } else {
          inc.add(id);
        }
      }),
      child: Chip(
        backgroundColor: bg,
        side: state == 0 ? null : BorderSide(color: fg!),
        avatar: icon == null ? null : Icon(icon, size: 16, color: fg),
        label: Text(name, style: TextStyle(color: fg)),
      ),
    );
  }

  Widget _multiChip(String label, bool selected, VoidCallback onTap) =>
      FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
}

extension _Toggle<T> on Set<T> {
  void toggle(T v) => contains(v) ? remove(v) : add(v);
}

/// A collapsible option facet (ExpansionTile): a header with a selected-count
/// badge, an internal search box (only shown for long lists), and a wrap of
/// chips. Generic over the chip key [K] so it backs every facet — genres and
/// themes (int, tri-state), status/language/country (String) and
/// networks/studios (int, multi-select).
class _ChipSection<K> extends StatefulWidget {
  const _ChipSection({
    required this.title,
    this.subtitle,
    required this.items,
    required this.selectedCount,
    required this.chipBuilder,
  });
  final String title;
  final String? subtitle;
  final List<(K, String)> items;
  final int selectedCount;
  final Widget Function(K key, String label) chipBuilder;

  @override
  State<_ChipSection<K>> createState() => _ChipSectionState<K>();
}

class _ChipSectionState<K> extends State<_ChipSection<K>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    // A search box only earns its space once the list gets long.
    final searchable = widget.items.length > 10;
    final matches = _q.isEmpty
        ? widget.items
        : widget.items.where((e) => e.$2.toLowerCase().contains(_q.toLowerCase())).toList();
    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: Insets.md),
        title: Text(widget.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: widget.selectedCount > 0
            ? Text('${widget.selectedCount} selected', style: TextStyle(color: context.scheme.primary))
            : (widget.subtitle != null ? Text(widget.subtitle!, style: context.text.labelSmall) : null),
        children: [
          if (searchable) ...[
            TextField(
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search ${widget.title.toLowerCase()}…',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: Insets.sm),
          ],
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.xs,
            children: [for (final (key, name) in matches.take(60)) widget.chipBuilder(key, name)],
          ),
          if (matches.length > 60)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text('Refine your search to see more…',
                  style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}
