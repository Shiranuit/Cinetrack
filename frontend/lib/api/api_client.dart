import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'filters.dart';
import 'models.dart';
// Web gets a credentialed BrowserClient (sends the httpOnly refresh cookie);
// native gets a plain client.
import 'net_client_io.dart' if (dart.library.js_interop) 'net_client_web.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}

/// Secure-storage key for the refresh token (mobile/desktop only; on web the
/// refresh token lives in an httpOnly cookie the browser manages).
const _refreshKey = 'cinetrack_refresh';

class ApiClient extends ChangeNotifier {
  ApiClient({String? base}) : base = base ?? Config.apiBase;

  final String base;
  final http.Client _client = createNetClient();
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// Short-lived access token, kept only in memory (never persisted on web, so
  /// XSS can't read it; the long-lived refresh token is httpOnly/secure-storage).
  String? _accessToken;

  /// Called when the session is truly dead (refresh failed) so the app returns
  /// to the login screen.
  void Function()? onUnauthorized;

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    final t = _accessToken;
    if (t != null) h['authorization'] = 'Bearer $t';
    // Tell the backend to keep the refresh token in an httpOnly cookie (web).
    if (kIsWeb) h['x-use-cookie'] = '1';
    return h;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('$base$path').replace(
        queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
      );

  Future<dynamic> _decode(http.Response r) async {
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final msg = (body is Map && body['error'] != null) ? body['error'] : 'HTTP ${r.statusCode}';
    throw ApiException(r.statusCode, '$msg');
  }

  /// Run a request; on a 401 for an authenticated call, try to refresh the access
  /// token once and retry. If refresh fails, drop the session.
  Future<dynamic> _request(Future<http.Response> Function() send, {bool auth = true}) async {
    var r = await send();
    if (r.statusCode == 401 && auth) {
      if (await _tryRefresh()) {
        r = await send();
      } else {
        onUnauthorized?.call();
      }
    }
    return _decode(r);
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) =>
      _request(() => _client.get(_uri(path, query), headers: _headers()));

  Future<dynamic> _send(String method, String path, {Object? body, bool auth = true}) async {
    final result = await _request(() async {
      final req = http.Request(method, _uri(path))..headers.addAll(_headers(json: body != null));
      if (body != null) req.body = jsonEncode(body);
      return http.Response.fromStream(await _client.send(req));
    }, auth: auth);
    // An authenticated write (follow / watch / favorite / rate / import / …) can
    // change what tracking screens show. Notify listeners so an open screen (e.g.
    // the Library) refreshes itself instead of needing a manual pull-to-refresh.
    // Auth-flow calls use auth:false and are skipped, so login/logout don't fire.
    if (auth) notifyListeners();
    return result;
  }

  // ---- session / refresh ----

  Future<bool>? _refreshInFlight;

  /// Refresh the access token, de-duplicating concurrent callers.
  Future<bool> _tryRefresh() =>
      _refreshInFlight ??= _doTryRefresh().whenComplete(() => _refreshInFlight = null);

  Future<bool> _doTryRefresh() async {
    try {
      final headers = <String, String>{'content-type': 'application/json'};
      var bodyStr = '{}';
      if (kIsWeb) {
        headers['x-use-cookie'] = '1'; // refresh token comes from the cookie
      } else {
        final stored = await _secure.read(key: _refreshKey);
        if (stored == null) return false;
        bodyStr = jsonEncode({'refresh_token': stored});
      }
      final req = http.Request('POST', _uri('/api/auth/refresh'))
        ..headers.addAll(headers)
        ..body = bodyStr;
      final r = await http.Response.fromStream(await _client.send(req));
      if (r.statusCode < 200 || r.statusCode >= 300) return false;
      await _adoptSession(jsonDecode(r.body) as Map<String, dynamic>);
      return _accessToken != null;
    } catch (_) {
      return false;
    }
  }

  /// Adopt an access token (memory) and, on native, persist the rotated refresh
  /// token to secure storage.
  Future<void> _adoptSession(Map<String, dynamic> j) async {
    _accessToken = (j['access_token'] ?? j['token']) as String?;
    if (!kIsWeb && j['refresh_token'] != null) {
      await _secure.write(key: _refreshKey, value: j['refresh_token'] as String);
    }
  }

  /// Restore a session on startup (web: cookie; native: stored refresh token).
  Future<bool> tryRestore() => _tryRefresh();

  Future<void> logout() async {
    // Revoke server-side by refresh token: cookie on web, body on mobile — works
    // even if the access token has expired. Best-effort.
    try {
      Object? body;
      if (!kIsWeb) {
        final rt = await _secure.read(key: _refreshKey);
        if (rt != null) body = {'refresh_token': rt};
      }
      await _send('POST', '/api/auth/logout', body: body, auth: false);
    } catch (_) {}
    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    _accessToken = null;
    _refreshInFlight = null;
    if (!kIsWeb) await _secure.delete(key: _refreshKey);
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

  /// Public server feature flags (no auth). Falls through to defaults on the caller
  /// side if this throws (e.g. backend unreachable).
  Future<ServerConfig> serverConfig() async {
    final j = await _request(() => _client.get(_uri('/api/config'), headers: _headers()), auth: false);
    return ServerConfig.fromJson(j as Map<String, dynamic>);
  }

  // ---- auth ---- (login/register/forgot/reset are unauthenticated: a 401 means
  // bad credentials, not an expired token, so they don't trigger a refresh.)
  Future<String> login(String email, String password) async {
    final j = await _send('POST', '/api/auth/login',
        body: {'email': email, 'password': password}, auth: false) as Map<String, dynamic>;
    await _adoptSession(j);
    return j['user_id'] as String; // UUID
  }

  Future<String> register(String email, String password, String screenName, {String? inviteCode}) async {
    final j = await _send('POST', '/api/auth/register', body: {
      'email': email,
      'password': password,
      'screen_name': screenName,
      if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
    }, auth: false) as Map<String, dynamic>;
    await _adoptSession(j);
    return j['user_id'] as String; // UUID
  }

  Future<void> forgotPassword(String email) =>
      _send('POST', '/api/auth/forgot', body: {'email': email}, auth: false);

  Future<void> resetPassword(String token, String newPassword) =>
      _send('POST', '/api/auth/reset', body: {'token': token, 'new_password': newPassword}, auth: false);

  Future<InviteCreated> createInvite({String? email}) async {
    final j = await _send('POST', '/api/invites',
        body: {if (email != null && email.isNotEmpty) 'email': email});
    return InviteCreated.fromJson(j as Map<String, dynamic>);
  }

  Future<List<InviteInfo>> listInvites() async => _list(await _get('/api/invites'), InviteInfo.fromJson);
  Future<void> revokeInvite(String id) => _send('DELETE', '/api/invites/$id');

  Future<List<SecurityEvent>> securityLog() async =>
      _list(await _get('/api/me/security-log'), SecurityEvent.fromJson);

  Future<Me> me() async => Me.fromJson(await _get('/api/me'));

  /// Update display name and/or email (only the provided fields change).
  Future<Me> updateProfile({String? screenName, String? email}) async =>
      Me.fromJson(await _send('PUT', '/api/me', body: {
        'screen_name': ?screenName,
        'email': ?email,
      }));

  /// Change password. Requires the current one; returns a FRESH token (other
  /// sessions are invalidated server-side, so the caller must adopt this token).
  /// Change password (requires the current one). The current session stays valid
  /// server-side; other sessions are revoked.
  Future<void> changePassword(String currentPassword, String newPassword) =>
      _send('PUT', '/api/me/password',
          body: {'current_password': currentPassword, 'new_password': newPassword});

  // ---- catalog / browse ----
  Future<Series> series(int id, {String? langs}) async =>
      Series.fromJson(await _get('/api/series/$id', {'langs': ?langs}));

  Future<Series> movie(int id, {String? langs}) async =>
      Series.fromJson(await _get('/api/movies/$id', {'langs': ?langs}));

  // ---- movie tracking ----
  Future<List<LibraryMovie>> movies({String? langs, String? sort, String? dir}) async =>
      _list(await _get('/api/movies', {'langs': ?langs, 'sort': ?sort, 'dir': ?dir}), LibraryMovie.fromJson);
  Future<MovieRelation> movieRelation(int id) async =>
      MovieRelation.fromJson(await _get('/api/movies/$id/relation'));
  Future<MovieRelation> watchMovie(int id) async =>
      MovieRelation.fromJson(await _send('POST', '/api/movies/$id/watch'));
  Future<MovieRelation> unwatchMovie(int id) async =>
      MovieRelation.fromJson(await _send('DELETE', '/api/movies/$id/watch'));
  Future<MovieRelation> favoriteMovie(int id, bool value) async =>
      MovieRelation.fromJson(await _send(value ? 'POST' : 'DELETE', '/api/movies/$id/favorite'));
  Future<MovieRelation> watchlistMovie(int id, bool value) async =>
      MovieRelation.fromJson(await _send(value ? 'POST' : 'DELETE', '/api/movies/$id/watchlist'));

  /// Set (1..5) or clear (null) your rating for a movie.
  Future<MovieRelation> rateMovie(int id, int? rating) async =>
      MovieRelation.fromJson(await _send('PUT', '/api/movies/$id/rating', body: {'rating': rating}));

  Future<List<Season>> seasons(int id) async =>
      _list(await _get('/api/series/$id/seasons'), Season.fromJson);

  /// All artworks for a show / movie (best-scored first), for the artwork gallery.
  Future<List<Artwork>> seriesArtworks(int id) async =>
      _list(await _get('/api/series/$id/artworks'), Artwork.fromJson);
  Future<List<Artwork>> movieArtworks(int id) async =>
      _list(await _get('/api/movies/$id/artworks'), Artwork.fromJson);

  Future<List<Episode>> episodes(int id, {String? langs}) async =>
      _list(await _get('/api/series/$id/episodes', {'langs': ?langs}), Episode.fromJson);

  // ---- tracking ----
  Future<List<UserShow>> shows({String? langs}) async =>
      _list(await _get('/api/shows', {'langs': ?langs}), UserShow.fromJson);

  Future<Library> library({String? langs, String? sort, String? dir}) async =>
      Library.fromJson(await _get('/api/library', {'langs': ?langs, 'sort': ?sort, 'dir': ?dir}));

  Future<Stats> stats() async => Stats.fromJson(await _get('/api/stats'));

  // ---- discover / calendar / social ----
  Future<List<SearchResult>> discover({
    String? q,
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
          'q': ?q,
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
  Future<void> confirmSuggestion(int id, {String type = 'series'}) =>
      _send('POST', '/api/import/suggestions/$id/confirm?type=$type');
  Future<void> rejectSuggestion(int id, {String type = 'series'}) =>
      _send('POST', '/api/import/suggestions/$id/reject?type=$type');

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
  Future<void> followUser(String userId, bool value) =>
      _send(value ? 'POST' : 'DELETE', '/api/users/$userId/follow');

  Future<UserProfile> userProfile(String id) async => UserProfile.fromJson(await _get('/api/users/$id'));
  Future<Stats> userStats(String id) async => Stats.fromJson(await _get('/api/users/$id/stats'));
  Future<List<UserShow>> userShows(String id, {String? langs}) async =>
      _list(await _get('/api/users/$id/shows', {'langs': ?langs}), UserShow.fromJson);
  Future<Library> userLibrary(String id, {String? langs}) async =>
      Library.fromJson(await _get('/api/users/$id/library', {'langs': ?langs}));
  Future<List<SearchResult>> userFilteredShows(String id, AdvancedFilters f, {String? langs}) async =>
      _list(await _get('/api/users/$id/filter', {...f.toQuery(), 'limit': '200', 'langs': ?langs}), SearchResult.fromJson);
  Future<List<LibraryMovie>> userMovies(String id, {String? langs}) async =>
      _list(await _get('/api/users/$id/movies', {'langs': ?langs}), LibraryMovie.fromJson);
  Future<List<UserBrief>> followRequests() async =>
      _list(await _get('/api/users/requests'), UserBrief.fromJson);
  Future<List<UserBrief>> followers() async => _list(await _get('/api/users/followers'), UserBrief.fromJson);
  Future<void> removeFollower(String followerId) => _send('DELETE', '/api/users/followers/$followerId');
  Future<void> acceptRequest(String followerId) => _send('POST', '/api/users/requests/$followerId/accept');
  Future<void> rejectRequest(String followerId) => _send('POST', '/api/users/requests/$followerId/reject');
  Future<void> setPrivacy(bool isPrivate) => _send('PUT', '/api/me/privacy', body: {'is_private': isPrivate});
  Future<void> setProfileBlocks(List<String> blocks) => _send('PUT', '/api/me/profile-blocks', body: {'blocks': blocks});
  Future<void> setLanguages(List<String> languages) => _send('PUT', '/api/me/languages', body: {'languages': languages});

  Future<UserShow> showRelation(int seriesId, {String? langs}) async =>
      UserShow.fromJson(await _get('/api/shows/$seriesId', {'langs': ?langs}));

  Future<SeriesDetails> seriesDetails(int id) async =>
      SeriesDetails.fromJson(await _get('/api/series/$id/details'));

  Future<void> removeShow(int seriesId) => _send('DELETE', '/api/shows/$seriesId');

  Future<void> watchSeason(int seriesId, int season) =>
      _send('POST', '/api/series/$seriesId/seasons/$season/watch');

  /// Add a watch to every episode of the season (increment each ×N).
  Future<void> rewatchSeason(int seriesId, int season) =>
      _send('POST', '/api/series/$seriesId/seasons/$season/watch?rewatch=true');

  Future<void> unwatchSeason(int seriesId, int season) =>
      _send('DELETE', '/api/series/$seriesId/seasons/$season/watch');

  /// Remove one watch from every watched episode of the season (decrement each ×N).
  Future<void> decrementSeason(int seriesId, int season) =>
      _send('DELETE', '/api/series/$seriesId/seasons/$season/watch?decrement=true');

  /// Mark every episode of every season watched.
  Future<void> watchSeries(int seriesId) => _send('POST', '/api/series/$seriesId/watch');

  /// Add a watch to every episode of the whole series (increment each ×N).
  Future<void> rewatchSeries(int seriesId) => _send('POST', '/api/series/$seriesId/watch?rewatch=true');

  Future<void> unwatchSeries(int seriesId) => _send('DELETE', '/api/series/$seriesId/watch');

  /// Remove one watch from every watched episode of the whole series (decrement each ×N).
  Future<void> decrementSeries(int seriesId) => _send('DELETE', '/api/series/$seriesId/watch?decrement=true');

  Future<void> setFollow(int seriesId, bool value) =>
      _send(value ? 'POST' : 'DELETE', '/api/shows/$seriesId/follow');

  Future<void> setFavorite(int seriesId, bool value) =>
      _send(value ? 'POST' : 'DELETE', '/api/shows/$seriesId/favorite');

  Future<void> setStatus(int seriesId, String? status) =>
      _send('PUT', '/api/shows/$seriesId/status', body: {'status': status});

  /// Set (1..5) or clear (null) your rating for a show.
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
  Future<dynamic> _upload(String path, List<int> bytes, String filename) =>
      _request(() async {
        final req = http.MultipartRequest('POST', _uri(path))
          ..headers.addAll(_headers())
          ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
        return http.Response.fromStream(await _client.send(req));
      });

  Future<void> uploadAvatar(List<int> bytes, String filename) => _upload('/api/me/avatar', bytes, filename);
  Future<void> uploadCover(List<int> bytes, String filename) => _upload('/api/me/cover', bytes, filename);

  /// Import a TV Time GDPR export zip into the current account; returns the summary map.
  Future<Map<String, dynamic>> importGdpr(List<int> bytes, String filename) async =>
      (await _upload('/api/import', bytes, filename)) as Map<String, dynamic>;
}
