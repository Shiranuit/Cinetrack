import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'filters.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}

class ApiClient {
  ApiClient({String? base}) : base = base ?? Config.apiBase;

  final String base;
  String? token;

  /// Called when an authenticated request comes back 401 (e.g. the account was
  /// deleted or the token expired) so the app can drop the dead session.
  void Function()? onUnauthorized;

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    final t = token;
    if (t != null) h['authorization'] = 'Bearer $t';
    return h;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('$base$path').replace(
        queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
      );

  Future<dynamic> _decode(http.Response r) async {
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    // A 401 on a request we sent a token with means the session is dead — drop it.
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    final msg = (body is Map && body['error'] != null) ? body['error'] : 'HTTP ${r.statusCode}';
    throw ApiException(r.statusCode, '$msg');
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async =>
      _decode(await http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final req = http.Request(method, _uri(path))
      ..headers.addAll(_headers(json: body != null));
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send();
    return _decode(await http.Response.fromStream(streamed));
  }

  /// Decode a JSON array into a typed list, validating each element is an object
  /// via a map pattern (fails fast with a clear error otherwise).
  List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) parse) => switch (data) {
        final List items => [
            for (final e in items)
              switch (e) {
                final Map<String, dynamic> m => parse(m),
                _ => throw ApiException(500, 'expected object in list, got $e'),
              }
          ],
        _ => throw ApiException(500, 'expected a list, got $data'),
      };

  // ---- auth ----
  Future<(String, int)> login(String email, String password) async {
    final j = await _send('POST', '/api/auth/login', body: {'email': email, 'password': password});
    return switch (j) {
      {'token': final String token, 'user_id': final int id} => (token, id),
      _ => throw ApiException(500, 'unexpected auth response: $j'),
    };
  }

  Future<(String, int)> register(String email, String password, String screenName) async {
    final j = await _send('POST', '/api/auth/register',
        body: {'email': email, 'password': password, 'screen_name': screenName});
    return switch (j) {
      {'token': final String token, 'user_id': final int id} => (token, id),
      _ => throw ApiException(500, 'unexpected auth response: $j'),
    };
  }

  Future<Me> me() async => Me.fromJson(await _get('/api/me'));

  /// Update display name and/or email (only the provided fields change).
  Future<Me> updateProfile({String? screenName, String? email}) async =>
      Me.fromJson(await _send('PUT', '/api/me', body: {
        'screen_name': ?screenName,
        'email': ?email,
      }));

  /// Set a new password (no current password required — there's no recovery flow).
  Future<void> updatePassword(String newPassword) =>
      _send('PUT', '/api/me/password', body: {'new_password': newPassword});

  // ---- catalog / browse ----
  Future<Series> series(int id, {String lang = 'eng'}) async =>
      Series.fromJson(await _get('/api/series/$id', {'lang': lang}));

  Future<Series> movie(int id, {String lang = 'eng'}) async =>
      Series.fromJson(await _get('/api/movies/$id', {'lang': lang}));

  // ---- movie tracking ----
  Future<List<LibraryMovie>> movies({String? langs}) async =>
      _list(await _get('/api/movies', {'langs': ?langs}), LibraryMovie.fromJson);
  Future<MovieRelation> movieRelation(int id) async =>
      MovieRelation.fromJson(await _get('/api/movies/$id/relation'));
  Future<MovieRelation> watchMovie(int id) async =>
      MovieRelation.fromJson(await _send('POST', '/api/movies/$id/watch'));
  Future<MovieRelation> unwatchMovie(int id) async =>
      MovieRelation.fromJson(await _send('DELETE', '/api/movies/$id/watch'));
  Future<MovieRelation> favoriteMovie(int id, bool value) async =>
      MovieRelation.fromJson(await _send(value ? 'POST' : 'DELETE', '/api/movies/$id/favorite'));

  Future<List<Season>> seasons(int id) async =>
      _list(await _get('/api/series/$id/seasons'), Season.fromJson);

  Future<List<Episode>> episodes(int id, {String lang = 'eng'}) async =>
      _list(await _get('/api/series/$id/episodes', {'lang': lang}), Episode.fromJson);

  Future<List<SearchResult>> search(String q, {String? type, String? langs}) async =>
      _list(await _get('/api/search', {'q': q, 'type': ?type, 'langs': ?langs}), SearchResult.fromJson);

  // ---- tracking ----
  Future<List<UserShow>> shows({String? langs}) async =>
      _list(await _get('/api/shows', {'langs': ?langs}), UserShow.fromJson);

  Future<Library> library({String? langs}) async =>
      Library.fromJson(await _get('/api/library', {'langs': ?langs}));

  Future<Stats> stats() async => Stats.fromJson(await _get('/api/stats'));

  // ---- discover / calendar / social ----
  Future<List<SearchResult>> discover({
    String type = 'series',
    String sort = 'popularity',
    List<int> genres = const [],
    List<int> exclude = const [],
    int? yearMin,
    int? yearMax,
    int? runtimeMin,
    int? runtimeMax,
    String? langs,
  }) async =>
      _list(
        await _get('/api/discover', {
          'type': type,
          'sort': sort,
          'genres': ?(genres.isEmpty ? null : genres.join(',')),
          'exclude': ?(exclude.isEmpty ? null : exclude.join(',')),
          'year_min': ?yearMin?.toString(),
          'year_max': ?yearMax?.toString(),
          'runtime_min': ?runtimeMin?.toString(),
          'runtime_max': ?runtimeMax?.toString(),
          'langs': ?langs,
        }),
        SearchResult.fromJson,
      );

  Future<List<Genre>> genres() async => _list(await _get('/api/genres'), Genre.fromJson);

  /// Advanced filtered search — Discover (`library: false`) or the user's Library.
  Future<List<SearchResult>> filteredSearch(AdvancedFilters f,
      {bool library = false, String? langs, String? type, int limit = 60, int offset = 0}) async {
    final path = library ? '/api/library/filter' : '/api/discover';
    // `type` overrides f.type so callers can fan out over several kinds.
    final q = {
      ...f.toQuery(),
      'type': ?type,
      'limit': '$limit',
      'offset': '$offset',
      'langs': ?langs,
    };
    return _list(await _get(path, q), SearchResult.fromJson);
  }

  /// Filter options present in the catalog (or the library when `library: true`).
  Future<FilterOptions> filterOptions({bool library = false}) async =>
      FilterOptions.fromJson(await _get('/api/filters', {'library': '$library'}));

  Future<void> deleteAccount() => _send('DELETE', '/api/me');

  // ---- import match suggestions ----
  Future<List<MatchSuggestion>> importSuggestions({String? langs}) async =>
      _list(await _get('/api/import/suggestions', {'langs': ?langs}), MatchSuggestion.fromJson);
  Future<void> confirmSuggestion(int id) => _send('POST', '/api/import/suggestions/$id/confirm');
  Future<void> rejectSuggestion(int id) => _send('POST', '/api/import/suggestions/$id/reject');

  Future<(List<CalendarItem>, List<CalendarItem>)> calendar({String? langs}) async {
    final j = await _get('/api/calendar', {'langs': ?langs});
    List<CalendarItem> parse(dynamic v) =>
        (v as List? ?? const []).map((e) => CalendarItem.fromJson(e as Map<String, dynamic>)).toList();
    return (parse(j['upcoming']), parse(j['recent']));
  }

  Future<List<FeedItem>> feed() async => _list(await _get('/api/feed'), FeedItem.fromJson);
  Future<List<UserBrief>> searchUsers(String q) async =>
      _list(await _get('/api/users/search', {'q': q}), UserBrief.fromJson);
  Future<List<UserBrief>> following() async => _list(await _get('/api/users/following'), UserBrief.fromJson);
  Future<void> followUser(int userId, bool value) =>
      _send(value ? 'POST' : 'DELETE', '/api/users/$userId/follow');

  Future<UserProfile> userProfile(int id) async => UserProfile.fromJson(await _get('/api/users/$id'));
  Future<Stats> userStats(int id) async => Stats.fromJson(await _get('/api/users/$id/stats'));
  Future<List<UserShow>> userShows(int id, {String? langs}) async =>
      _list(await _get('/api/users/$id/shows', {'langs': ?langs}), UserShow.fromJson);
  Future<Library> userLibrary(int id, {String? langs}) async =>
      Library.fromJson(await _get('/api/users/$id/library', {'langs': ?langs}));
  Future<List<SearchResult>> userFilteredShows(int id, AdvancedFilters f, {String? langs}) async =>
      _list(await _get('/api/users/$id/filter', {...f.toQuery(), 'limit': '200', 'langs': ?langs}), SearchResult.fromJson);
  Future<List<LibraryMovie>> userMovies(int id, {String? langs}) async =>
      _list(await _get('/api/users/$id/movies', {'langs': ?langs}), LibraryMovie.fromJson);
  Future<List<UserBrief>> followRequests() async =>
      _list(await _get('/api/users/requests'), UserBrief.fromJson);
  Future<List<UserBrief>> followers() async => _list(await _get('/api/users/followers'), UserBrief.fromJson);
  Future<void> removeFollower(int followerId) => _send('DELETE', '/api/users/followers/$followerId');
  Future<void> acceptRequest(int followerId) => _send('POST', '/api/users/requests/$followerId/accept');
  Future<void> rejectRequest(int followerId) => _send('POST', '/api/users/requests/$followerId/reject');
  Future<void> setPrivacy(bool isPrivate) => _send('PUT', '/api/me/privacy', body: {'is_private': isPrivate});
  Future<void> setProfileBlocks(List<String> blocks) => _send('PUT', '/api/me/profile-blocks', body: {'blocks': blocks});

  Future<UserShow> showRelation(int seriesId, {String? langs}) async =>
      UserShow.fromJson(await _get('/api/shows/$seriesId', {'langs': ?langs}));

  Future<void> removeShow(int seriesId) => _send('DELETE', '/api/shows/$seriesId');

  Future<void> watchSeason(int seriesId, int season) =>
      _send('POST', '/api/series/$seriesId/seasons/$season/watch');

  /// Add a watch to every episode of the season (increment each ×N).
  Future<void> rewatchSeason(int seriesId, int season) =>
      _send('POST', '/api/series/$seriesId/seasons/$season/watch?rewatch=true');

  Future<void> unwatchSeason(int seriesId, int season) =>
      _send('DELETE', '/api/series/$seriesId/seasons/$season/watch');

  Future<void> setFollow(int seriesId, bool value) =>
      _send(value ? 'POST' : 'DELETE', '/api/shows/$seriesId/follow');

  Future<void> setFavorite(int seriesId, bool value) =>
      _send(value ? 'POST' : 'DELETE', '/api/shows/$seriesId/favorite');

  Future<void> setStatus(int seriesId, String? status) =>
      _send('PUT', '/api/shows/$seriesId/status', body: {'status': status});

  /// Set (1..10) or clear (null) your rating for a show.
  Future<void> rateShow(int seriesId, int? rating) =>
      _send('PUT', '/api/shows/$seriesId/rating', body: {'rating': rating});

  /// Map of episode_id → times watched (a ×N rewatch count).
  Future<Map<int, int>> seenCounts(int seriesId) async {
    final j = await _get('/api/shows/$seriesId/seen');
    return switch (j) {
      {'counts': final Map<String, dynamic> counts} => {
          for (final e in counts.entries) int.parse(e.key): e.value as int,
        },
      _ => throw ApiException(500, 'unexpected seen response: $j'),
    };
  }

  Future<void> watch(int episodeId) => _send('POST', '/api/episodes/$episodeId/watch');
  Future<void> unwatch(int episodeId) => _send('DELETE', '/api/episodes/$episodeId/watch');

  // ---- uploads ----
  Future<dynamic> _upload(String path, List<int> bytes, String filename) async {
    final req = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers())
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    return _decode(await http.Response.fromStream(await req.send()));
  }

  Future<void> uploadAvatar(List<int> bytes, String filename) => _upload('/api/me/avatar', bytes, filename);
  Future<void> uploadCover(List<int> bytes, String filename) => _upload('/api/me/cover', bytes, filename);

  /// Import a TV Time GDPR export zip into the current account; returns the summary map.
  Future<Map<String, dynamic>> importGdpr(List<int> bytes, String filename) async =>
      (await _upload('/api/import', bytes, filename)) as Map<String, dynamic>;
}
