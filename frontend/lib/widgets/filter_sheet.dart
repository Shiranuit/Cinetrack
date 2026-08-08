import 'package:flutter/material.dart';

import '../api/filters.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../util/locale_labels.dart';

/// Sort option ids in display order. Labels resolve via [sortLabel] so they localize.
const kSortKeys = ['popularity', 'rating', 'year', 'updated', 'seasons', 'episodes', 'runtime', 'name'];

/// Sorts that need your watch history, so they only exist over your own library
/// (the backend pulls in the watch-state aggregates for them).
const kLibrarySortKeys = ['last_watched', 'last_aired', 'remaining', 'progress'];

/// Localized label for a sort id. In another user's library, `my_rating` is the
/// OWNER's rating, so it's labelled as such rather than "Your rating".
String sortLabel(AppLocalizations t, String key, {bool othersLibrary = false}) => switch (key) {
      'popularity' => t.sortPopular,
      'rating' => t.sortTopRated,
      'my_rating' => othersLibrary ? t.sortOwnerRating : t.sortMyRating,
      'year' => t.sortReleaseDate,
      'updated' => t.sortLastUpdated,
      'seasons' => t.seasons,
      'episodes' => t.episodes,
      'runtime' => t.sortLongest,
      'name' => t.sortName,
      'last_watched' => t.sortLastWatched,
      'last_aired' => t.sortLastAired,
      'remaining' => t.sortRemaining,
      'progress' => t.sortProgress,
      _ => key,
    };

/// One-line explanation of what a sort actually orders by. The distinctions that
/// matter most: "Episodes left" counts unwatched episodes while "Progress" is the
/// percentage watched (a 200-episode show with 2 left is 99% done but has the same
/// "2 left" as a 4-episode one), and the three date sorts read three different
/// clocks — when you watched, when it aired, when the catalog record changed.
String sortHelp(AppLocalizations t, String key, {bool othersLibrary = false}) => switch (key) {
      'popularity' => t.sortHelpPopular,
      'rating' => t.sortHelpTopRated,
      'my_rating' => othersLibrary ? t.sortHelpOwnerRating : t.sortHelpMyRating,
      'year' => t.sortHelpReleaseDate,
      'updated' => t.sortHelpLastUpdated,
      'seasons' => t.sortHelpSeasons,
      'episodes' => t.sortHelpEpisodes,
      'runtime' => t.sortHelpLongest,
      'name' => t.sortHelpName,
      'last_watched' => t.sortHelpLastWatched,
      'last_aired' => t.sortHelpLastAired,
      'remaining' => t.sortHelpRemaining,
      'progress' => t.sortHelpProgress,
      _ => key,
    };

/// The Library's own categories, usable as a filter facet. Mirrors
/// `tracking::state::STATES` on the server.
const kLibraryStates = ['watching', 'stale', 'not_started', 'for_later', 'up_to_date', 'stopped'];

/// Localized label for a Library category — the same words the rails use.
String libraryStateLabel(AppLocalizations t, String s) => switch (s) {
      'watching' => t.catWatching,
      'stale' => t.catStale,
      'not_started' => t.catNotStarted,
      'for_later' => t.watchLater,
      'up_to_date' => t.catUpToDate,
      'stopped' => t.catStopped,
      _ => s,
    };

/// Localized label for a catalog status value (from the backend).
String statusLabel(AppLocalizations t, String s) => switch (s) {
      'Continuing' => t.statusContinuing,
      'Ended' => t.statusEnded,
      'Upcoming' => t.statusUpcoming,
      _ => s,
    };

// Language/country label helpers moved to util/locale_labels.dart (shared with
// the show-detail metadata view).

/// Advanced-filter bottom sheet, shared by Discover and the Library filter.
/// Mutates [filters] in place; the caller reloads results on dismiss.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.filters,
    required this.options,
    this.showFavorites = false,
    this.othersLibrary = false,
  });
  final AdvancedFilters filters;
  final FilterOptions options;
  /// Whether to offer the "Favorites only" toggle (library filter only).
  final bool showFavorites;

  /// Viewing another user's library: `my_rating` means the OWNER's rating, so its
  /// sort chip is labelled accordingly.
  final bool othersLibrary;

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
    final t = AppLocalizations.of(context);
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
              Text(t.filters, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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

          // Discover only: also include shows already in your library (Discover
          // hides tracked shows by default).
          if (!widget.showFavorites)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: FilterChip(
                avatar: Icon(Icons.video_library_rounded, size: 18, color: f.includeLibrary ? context.scheme.primary : null),
                label: Text(t.inMyLibrary),
                selected: f.includeLibrary,
                onSelected: (v) => setState(() => f.includeLibrary = v),
              ),
            ),

          // "Sort by" header with an ascending/descending toggle on the right.
          Padding(
            padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.sm),
            child: Row(
              children: [
                Text(t.sortBy, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                ActionChip(
                  avatar: Icon(f.sortDesc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 18),
                  label: Text(f.sortDesc ? t.sortDescending : t.sortAscending),
                  onPressed: () => setState(() => f.sortDesc = !f.sortDesc),
                ),
              ],
            ),
          ),
          Wrap(spacing: Insets.sm, children: [
            // "Your rating" (my_rating) is offered only in the Library: Discover
            // hides your tracked shows, and you can only rate what you track, so
            // it would be empty there. Slot it right after "Top rated".
            for (final key in [
              for (final k in kSortKeys) ...[k, if (k == 'rating' && widget.showFavorites) 'my_rating'],
              // Library scope only — these read your watch history.
              if (widget.showFavorites) ...kLibrarySortKeys,
            ])
              // Several sorts are easy to confuse — "Episodes left" is a count and
              // "Progress" a percentage, and three different clocks look alike.
              // Hover (desktop/web) or long-press (touch) explains each one.
              Tooltip(
                message: sortHelp(t, key, othersLibrary: widget.othersLibrary),
                child: ChoiceChip(
                label: Text(sortLabel(t, key, othersLibrary: widget.othersLibrary)),
                selected: f.sort == key,
                // Default each sort to its natural direction (names A->Z, everything
                // else high/new first); the toggle above can flip it.
                onSelected: (_) => setState(() {
                  f.sort = key;
                  f.sortDesc = key != 'name';
                }),
              )),
          ]),

          // Every option facet is a collapsible section (see [_ChipSection]).
          if (o.genres.isNotEmpty)
            _triSection(t.genres, [for (final g in o.genres) (g.id, g.name)], f.genresInc, f.genresExc),
          // Library scope only: the Library's own categories as a facet, which is
          // what a duplicated built-in category filters on.
          if (widget.showFavorites)
            _multiSection<String>(
              t.libraryStatus,
              [for (final st in kLibraryStates) (st, libraryStateLabel(t, st))],
              f.states,
            ),
          if (o.statuses.isNotEmpty)
            _multiSection<String>(t.status, [for (final s in o.statuses) (s, statusLabel(t, s))], f.statuses),
          if (o.languages.isNotEmpty)
            _multiSection<String>(AppLocalizations.of(context).filterOrigLanguage,
                [for (final c in o.languages) (c, langName(context, c))], f.originalLanguages),
          if (o.countries.isNotEmpty)
            _multiSection<String>(AppLocalizations.of(context).filterOrigCountry,
                [for (final c in o.countries) (c, countryName(context, c))], f.originalCountries),

          if (o.tags.isNotEmpty)
            _triSection(t.themes, [for (final tag in o.tags) (tag.id, tag.name)], f.tagsInc, f.tagsExc),
          if (o.networks.isNotEmpty)
            _multiSection<int>(t.networks, [for (final c in o.networks) (c.id, c.name)], f.networks),
          if (o.studios.isNotEmpty)
            _multiSection<int>(t.studios, [for (final c in o.studios) (c.id, c.name)], f.studios),

          // Typed bounds rather than sliders: these domains are long-tailed (episode
          // counts reach 11,863, season counts 713), so a track either squashes the
          // useful range into nothing or can't reach the tail. Leaving a field empty
          // is what makes a range half-open.
          _minMaxSection(context, t.releaseYear, f.yearMin, f.yearMax, (lo, hi) {
            setState(() {
              f.yearMin = lo;
              f.yearMax = hi;
            });
          }, hint: '1950 – $thisYear'),
          _minMaxSection(context, t.seasons, f.seasonsMin, f.seasonsMax, (lo, hi) {
            setState(() {
              f.seasonsMin = lo;
              f.seasonsMax = hi;
            });
          }),
          _minMaxSection(context, t.episodes, f.episodesMin, f.episodesMax, (lo, hi) {
            setState(() {
              f.episodesMin = lo;
              f.episodesMax = hi;
            });
          }),

          // ---- library scope only: facets that read your watch history ----
          if (widget.showFavorites) ...[
            _minMaxSection(context, t.filterWatchedDays, f.watchedDaysMin, f.watchedDaysMax, (lo, hi) {
              setState(() {
                f.watchedDaysMin = lo;
                f.watchedDaysMax = hi;
              });
            }),
            _minMaxSection(context, t.filterAiredDays, f.airedDaysMin, f.airedDaysMax, (lo, hi) {
              setState(() {
                f.airedDaysMin = lo;
                f.airedDaysMax = hi;
              });
            }),
            _minMaxSection(context, t.filterRemaining, f.remainingMin, f.remainingMax, (lo, hi) {
              setState(() {
                f.remainingMin = lo;
                f.remainingMax = hi;
              });
            }),
            _minMaxSection(context, t.filterProgress, f.progressMin?.round(), f.progressMax?.round(), (lo, hi) {
              setState(() {
                f.progressMin = lo?.toDouble();
                f.progressMax = hi?.toDouble();
              });
            }, hint: '0 – 100'),
            _triStateSection(context, t.filterCaughtUp, f.caughtUp, (v) => setState(() => f.caughtUp = v)),
            _triStateSection(context, t.filterHasUpcoming, f.hasUpcoming, (v) => setState(() => f.hasUpcoming = v)),
          ],

          // Runtime is the same min/max pair, so it gets the same section — but the
          // three buckets cover almost every real use, so they stay as a quick path
          // inside it. They write the same two fields, which is why the section has
          // to reflect changes made from outside it.
          _minMaxSection(context, t.runtimeLength, f.runtimeMin, f.runtimeMax, (lo, hi) {
            setState(() {
              f.runtimeMin = lo;
              f.runtimeMax = hi;
            });
          }, presets: Wrap(spacing: Insets.sm, children: [
            for (final b in _runtimeBuckets)
              ChoiceChip(
                label: Text(switch (b.$1) {
                  'Any' => t.filterAny,
                  '< 30m' => t.runtimeUnder30,
                  '30–60m' => t.runtime30to60,
                  '> 60m' => t.runtimeOver60,
                  _ => b.$1,
                }),
                selected: _isRuntime(b.$2, b.$3),
                onSelected: (_) => setState(() {
                  f.runtimeMin = b.$2;
                  f.runtimeMax = b.$3;
                }),
              ),
          ])),

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

  /// A collapsed min/max pair. Replaces the range slider for domains a slider can't
  /// serve: episode counts run to 11,863 and season counts to 713, so a linear
  /// track squashes the region anyone actually filters on into a few pixels, and
  /// its far end can't express "and above" at all.
  ///
  /// Either field may be left empty, which is what makes the range half-open —
  /// "≥ 1000" is just a min with no max.
  Widget _minMaxSection(
    BuildContext context,
    String title,
    int? lo,
    int? hi,
    void Function(int? lo, int? hi) onChange, {
    String? hint,
    Widget? presets,
  }) {
    final t = AppLocalizations.of(context);
    final summary = switch ((lo, hi)) {
      (null, null) => null,
      (final l?, null) => '≥ $l',
      (null, final h?) => '≤ $h',
      (final l?, final h?) => '$l–$h',
    };
    return _MinMaxSection(
      key: ValueKey(title),
      title: title,
      hint: hint,
      // The summary sits on the collapsed header, so an applied bound is visible
      // without expanding — the reason a slider was legible at a glance.
      summary: summary,
      anyLabel: t.filterAny,
      minLabel: t.filterMin,
      maxLabel: t.filterMax,
      lo: lo,
      hi: hi,
      onChange: onChange,
      presets: presets,
    );
  }

  /// Yes / No / no-constraint. A plain Switch can't express "don't care", which is
  /// the default and a different thing from "must be false".
  Widget _triStateSection(BuildContext context, String title, bool? value, void Function(bool?) onChange) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, title),
          Wrap(spacing: Insets.sm, children: [
            for (final (label, v) in [(t.filterAny, null), (t.yes, true), (t.no, false)])
              ChoiceChip(
                label: Text(label),
                selected: value == v,
                onSelected: (_) => onChange(v),
              ),
          ]),
        ],
      ),
    );
  }

  /// Collapsible section of include/exclude chips: genres and themes.
  Widget _triSection(String title, List<(int, String)> items, Set<int> inc, Set<int> exc) =>
      _ChipSection<int>(
        title: title,
        subtitle: AppLocalizations.of(context).triStateHint,
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
            ? Text(AppLocalizations.of(context).nSelected(widget.selectedCount), style: TextStyle(color: context.scheme.primary))
            : (widget.subtitle != null ? Text(widget.subtitle!, style: context.text.labelSmall) : null),
        children: [
          if (searchable) ...[
            TextField(
              decoration: InputDecoration(
                isDense: true,
                hintText: AppLocalizations.of(context).searchIn(widget.title.toLowerCase()),
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
              child: Text(AppLocalizations.of(context).refineSearch,
                  style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// One collapsible numeric range: a header carrying its current bound, and two
/// optional fields. Stateful because the text controllers must survive rebuilds —
/// recreating them on every keystroke would move the caret to the start.
class _MinMaxSection extends StatefulWidget {
  const _MinMaxSection({
    super.key,
    required this.title,
    required this.summary,
    required this.anyLabel,
    required this.minLabel,
    required this.maxLabel,
    required this.lo,
    required this.hi,
    required this.onChange,
    this.hint,
    this.presets,
  });
  final String title;
  final String? summary;
  final String anyLabel, minLabel, maxLabel;
  final String? hint;
  final int? lo, hi;
  final void Function(int? lo, int? hi) onChange;

  /// Optional quick-select chips shown above the fields, writing the same bounds.
  final Widget? presets;

  @override
  State<_MinMaxSection> createState() => _MinMaxSectionState();
}

class _MinMaxSectionState extends State<_MinMaxSection> {
  late final TextEditingController _lo = TextEditingController(text: widget.lo?.toString() ?? '');
  late final TextEditingController _hi = TextEditingController(text: widget.hi?.toString() ?? '');

  @override
  void didUpdateWidget(covariant _MinMaxSection old) {
    super.didUpdateWidget(old);
    // The bounds can change from OUTSIDE these fields — a preset chip, or the
    // sheet's Reset button. Without this the model would move on while the text
    // stayed put, showing a filter that is no longer applied.
    _sync(_lo, widget.lo);
    _sync(_hi, widget.hi);
  }

  /// Only rewrite the field when it doesn't already represent the value, so typing
  /// never fights the caret (setting `.text` moves the cursor to the end).
  void _sync(TextEditingController c, int? value) {
    if (int.tryParse(c.text.trim()) == value) return;
    c.text = value?.toString() ?? '';
  }

  @override
  void dispose() {
    _lo.dispose();
    _hi.dispose();
    super.dispose();
  }

  /// An empty (or unparseable) field means "no bound", not zero — typing then
  /// clearing a value must restore "any" rather than pin the filter to 0.
  void _emit() => widget.onChange(int.tryParse(_lo.text.trim()), int.tryParse(_hi.text.trim()));

  Widget _field(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
          decoration: InputDecoration(labelText: label, isDense: true, hintText: widget.anyLabel),
          onChanged: (_) => _emit(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final active = widget.summary != null;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: Insets.md),
        title: Text(widget.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(
          widget.summary ?? widget.anyLabel,
          style: active
              ? context.text.labelMedium?.copyWith(color: context.scheme.primary)
              : context.text.labelSmall,
        ),
        // Opened by default when a bound is set, so a saved filter shows its values
        // instead of hiding them behind a tap.
        initiallyExpanded: active,
        children: [
          if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.hint!,
                    style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant)),
              ),
            ),
          if (widget.presets != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: Align(alignment: Alignment.centerLeft, child: widget.presets!),
            ),
          Row(children: [
            _field(_lo, widget.minLabel),
            const SizedBox(width: Insets.md),
            _field(_hi, widget.maxLabel),
            if (active)
              IconButton(
                tooltip: AppLocalizations.of(context).clear,
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _lo.clear();
                  _hi.clear();
                  _emit();
                },
              ),
          ]),
        ],
      ),
    );
  }
}
