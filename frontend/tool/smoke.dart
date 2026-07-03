// Integration smoke check: drives the real ApiClient against a running backend.
//   dart run tool/smoke.dart
// ignore_for_file: avoid_print
import 'package:frontend/api/api_client.dart';

Future<void> main() async {
  final api = ApiClient(base: 'http://localhost:8080');

  final (token, uid) = await api.login('redesign@x.com', 'Redesign!2026Xy');
  api.token = token;
  print('login ok: user_id=$uid');

  final me = await api.me();
  print('me: ${me.screenName} <${me.email}>');

  final stats = await api.stats();
  print('stats: eps=${stats.episodesSeen} watches=${stats.episodeWatches} mins=${stats.totalMinutes} fav=${stats.favorites}');

  final lib = await api.library();
  print('library: watching=${lib.watching.length} stale=${lib.stale.length} notStarted=${lib.notStarted.length} stopped=${lib.stopped.length}');

  final shows = await api.shows();
  print('shows: ${shows.length}${shows.isEmpty ? '' : ' (first: ${shows.first.name})'}');

  final rel = await api.showRelation(74796);
  print('relation 74796: followed=${rel.isFollowed} fav=${rel.isFavorited} seen=${rel.nbEpisodesSeen}');

  final s = await api.series(74796);
  print('series: ${s.name} (${s.year})');

  final seasons = await api.seasons(74796);
  print('seasons: ${seasons.length}');

  final eps = await api.episodes(74796);
  print('episodes: ${eps.length} (first: S${eps.first.seasonNumber}E${eps.first.number} ${eps.first.name})');

  final seen = await api.seenCounts(74796);
  print('seen episodes: ${seen.length} counts=$seen');

  final results = await api.search('bleach', type: 'series');
  print('search "bleach": ${results.length} (first: ${results.first.name})');

  print('\nALL OK');
}
