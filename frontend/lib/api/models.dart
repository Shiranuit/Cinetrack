// Models parsed from the backend JSON. Each `fromJson` uses Dart 3 map patterns
// to validate the shape/types at the boundary: required fields are matched with
// typed sub-patterns (so a wrong/missing type fails fast with a FormatException),
// while optional fields are destructured with nullable casts. The backend sends
// integers for all id/count fields and strings for text, so these patterns mirror
// the Rust types exactly.

class Me {
  final int id;
  final String screenName;
  final String? email;
  final String? avatarUrl;
  final String? coverUrl;
  final String? bio;
  final bool isPrivate;
  final List<String> profileBlocks;
  const Me({
    required this.id,
    required this.screenName,
    this.email,
    this.avatarUrl,
    this.coverUrl,
    this.bio,
    this.isPrivate = false,
    this.profileBlocks = const ['stats', 'favorites', 'shows'],
  });

  factory Me.fromJson(Map<String, dynamic> j) => switch (j) {
        {'id': final int id, 'screen_name': final String screenName} => Me(
            id: id,
            screenName: screenName,
            email: j['email'] as String?,
            avatarUrl: j['avatar_url'] as String?,
            coverUrl: j['cover_url'] as String?,
            bio: j['bio'] as String?,
            isPrivate: j['is_private'] as bool? ?? false,
            profileBlocks: (j['profile_blocks'] as List?)?.cast<String>() ??
                const ['stats', 'favorites', 'shows'],
          ),
        _ => throw FormatException('Me: bad payload $j'),
      };
}

class Series {
  final int id;
  final String? name;
  final String? overview;
  final String? imageUrl;
  final String? status;
  final int? year;
  const Series({
    required this.id,
    this.name,
    this.overview,
    this.imageUrl,
    this.status,
    this.year,
  });

  factory Series.fromJson(Map<String, dynamic> j) => switch (j) {
        {'id': final int id} => Series(
            id: id,
            name: j['name'] as String?,
            overview: j['overview'] as String?,
            imageUrl: j['image_url'] as String?,
            status: j['status'] as String?,
            year: j['year'] as int?,
          ),
        _ => throw FormatException('Series: missing/invalid id in $j'),
      };
}

class Season {
  final int id;
  final int? number;
  final String? type;
  final String? name;
  const Season({required this.id, this.number, this.type, this.name});

  factory Season.fromJson(Map<String, dynamic> j) => switch (j) {
        {'id': final int id} => Season(
            id: id,
            number: j['number'] as int?,
            type: j['season_type'] as String?,
            name: j['name'] as String?,
          ),
        _ => throw FormatException('Season: missing/invalid id in $j'),
      };
}

class Episode {
  final int id;
  final int? seasonNumber;
  final int? number;
  final String? name;
  final String? overview;
  final String? aired;
  final String? imageUrl;
  const Episode({
    required this.id,
    this.seasonNumber,
    this.number,
    this.name,
    this.overview,
    this.aired,
    this.imageUrl,
  });

  factory Episode.fromJson(Map<String, dynamic> j) => switch (j) {
        {'id': final int id} => Episode(
            id: id,
            seasonNumber: j['season_number'] as int?,
            number: j['number'] as int?,
            name: j['name'] as String?,
            overview: j['overview'] as String?,
            aired: j['aired'] as String?,
            imageUrl: j['image_url'] as String?,
          ),
        _ => throw FormatException('Episode: missing/invalid id in $j'),
      };
}

class UserShow {
  final int seriesId;
  final String? name;
  final String? imageUrl;
  final bool isFollowed;
  final bool isFavorited;
  final String? status;
  final bool archived;
  final int nbEpisodesSeen;
  final int? rating; // 1..10, null = unrated
  const UserShow({
    required this.seriesId,
    this.name,
    this.imageUrl,
    required this.isFollowed,
    required this.isFavorited,
    this.status,
    required this.archived,
    required this.nbEpisodesSeen,
    this.rating,
  });

  factory UserShow.fromJson(Map<String, dynamic> j) => switch (j) {
        {'series_id': final int seriesId} => UserShow(
            seriesId: seriesId,
            name: j['name'] as String?,
            imageUrl: j['image_url'] as String?,
            isFollowed: j['is_followed'] as bool? ?? false,
            isFavorited: j['is_favorited'] as bool? ?? false,
            status: j['status'] as String?,
            archived: j['archived'] as bool? ?? false,
            nbEpisodesSeen: j['nb_episodes_seen'] as int? ?? 0,
            rating: j['rating'] as int?,
          ),
        _ => throw FormatException('UserShow: missing/invalid series_id in $j'),
      };
}

class MovieRelation {
  final int movieId;
  final bool isFavorited;
  final bool watched;
  final int watchedCount;
  const MovieRelation({required this.movieId, required this.isFavorited, required this.watched, required this.watchedCount});
  factory MovieRelation.fromJson(Map<String, dynamic> j) => MovieRelation(
        movieId: j['movie_id'] as int,
        isFavorited: j['is_favorited'] as bool? ?? false,
        watched: j['watched'] as bool? ?? false,
        watchedCount: j['watched_count'] as int? ?? 0,
      );
}

class LibraryMovie {
  final int movieId;
  final String? name;
  final String? imageUrl;
  final int? year;
  final bool isFavorited;
  final int watchedCount;
  final int? lastWatched;
  const LibraryMovie({
    required this.movieId,
    this.name,
    this.imageUrl,
    this.year,
    required this.isFavorited,
    required this.watchedCount,
    this.lastWatched,
  });
  factory LibraryMovie.fromJson(Map<String, dynamic> j) => LibraryMovie(
        movieId: j['movie_id'] as int,
        name: j['name'] as String?,
        imageUrl: j['image_url'] as String?,
        year: j['year'] as int?,
        isFavorited: j['is_favorited'] as bool? ?? false,
        watchedCount: j['watched_count'] as int? ?? 0,
        lastWatched: j['last_watched'] as int?,
      );
}

class SearchResult {
  final int? tvdbId;
  final String? kind;
  final String? name;
  final int? year;
  final String? imageUrl;
  const SearchResult({this.tvdbId, this.kind, this.name, this.year, this.imageUrl});

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        tvdbId: j['tvdb_id'] as int?,
        kind: j['kind'] as String?,
        name: j['name'] as String?,
        year: j['year'] as int?,
        imageUrl: j['image_url'] as String?,
      );
}

class LibraryShow {
  final int seriesId;
  final String? name;
  final String? imageUrl;
  final int nbEpisodesSeen;
  final String? status;
  final bool archived;
  final bool isFavorited;
  final int? lastWatched; // unix epoch
  final int totalEpisodes; // aired, non-special
  final int seenEpisodes; // distinct watched, non-special
  final bool isAnime; // original language is Japanese
  const LibraryShow({
    required this.seriesId,
    this.name,
    this.imageUrl,
    required this.nbEpisodesSeen,
    this.status,
    required this.archived,
    required this.isFavorited,
    this.lastWatched,
    this.totalEpisodes = 0,
    this.seenEpisodes = 0,
    this.isAnime = false,
  });

  /// Fraction of the (non-special) aired episodes seen, 0..1.
  double get progress => totalEpisodes > 0 ? (seenEpisodes / totalEpisodes).clamp(0.0, 1.0) : 0.0;

  factory LibraryShow.fromJson(Map<String, dynamic> j) => switch (j) {
        {'series_id': final int id} => LibraryShow(
            seriesId: id,
            name: j['name'] as String?,
            imageUrl: j['image_url'] as String?,
            nbEpisodesSeen: j['nb_episodes_seen'] as int? ?? 0,
            status: j['status'] as String?,
            archived: j['archived'] as bool? ?? false,
            isFavorited: j['is_favorited'] as bool? ?? false,
            lastWatched: j['last_watched'] as int?,
            totalEpisodes: j['total_episodes'] as int? ?? 0,
            seenEpisodes: j['seen_episodes'] as int? ?? 0,
            isAnime: j['is_anime'] as bool? ?? false,
          ),
        _ => throw FormatException('LibraryShow: bad payload $j'),
      };
}

class Library {
  final List<LibraryShow> watching;
  final List<LibraryShow> upToDate;
  final List<LibraryShow> stale;
  final List<LibraryShow> notStarted;
  final List<LibraryShow> stopped;
  const Library({
    required this.watching,
    required this.upToDate,
    required this.stale,
    required this.notStarted,
    required this.stopped,
  });

  static List<LibraryShow> _list(dynamic v) =>
      (v as List? ?? const []).map((e) => LibraryShow.fromJson(e as Map<String, dynamic>)).toList();

  factory Library.fromJson(Map<String, dynamic> j) => Library(
        watching: _list(j['watching']),
        upToDate: _list(j['up_to_date']),
        stale: _list(j['stale']),
        notStarted: _list(j['not_started']),
        stopped: _list(j['stopped']),
      );

  bool get isEmpty =>
      watching.isEmpty && upToDate.isEmpty && stale.isEmpty && notStarted.isEmpty && stopped.isEmpty;
}

class Genre {
  final int id;
  final String name;
  const Genre({required this.id, required this.name});
  factory Genre.fromJson(Map<String, dynamic> j) => Genre(id: j['id'] as int, name: j['name'] as String? ?? '');
}

class Tag {
  final int id;
  final String name;
  final String? category;
  const Tag({required this.id, required this.name, this.category});
  factory Tag.fromJson(Map<String, dynamic> j) =>
      Tag(id: j['id'] as int, name: j['name'] as String? ?? '', category: j['category'] as String?);
}

class Company {
  final int id;
  final String name;
  const Company({required this.id, required this.name});
  factory Company.fromJson(Map<String, dynamic> j) => Company(id: j['id'] as int, name: j['name'] as String? ?? '');
}

/// The filterable values that exist in the catalog (or the user's library).
class FilterOptions {
  final List<Genre> genres;
  final List<Tag> tags;
  final List<Company> networks;
  final List<Company> studios;
  final List<String> statuses;
  final List<String> languages; // original-language codes, most common first
  final List<String> countries; // origin-country codes, most common first
  const FilterOptions({
    this.genres = const [],
    this.tags = const [],
    this.networks = const [],
    this.studios = const [],
    this.statuses = const [],
    this.languages = const [],
    this.countries = const [],
  });
  static List<T> _l<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      (v as List? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();
  static List<String> _s(dynamic v) => (v as List? ?? const []).map((e) => '$e').toList();
  factory FilterOptions.fromJson(Map<String, dynamic> j) => FilterOptions(
        genres: _l(j['genres'], Genre.fromJson),
        tags: _l(j['tags'], Tag.fromJson),
        networks: _l(j['networks'], Company.fromJson),
        studios: _l(j['studios'], Company.fromJson),
        statuses: _s(j['statuses']),
        languages: _s(j['languages']),
        countries: _s(j['countries']),
      );
}

class CalendarItem {
  final int seriesId;
  final int? episodeId;
  final String? name;
  final String? imageUrl;
  final String? date;
  final String? time;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeName;
  const CalendarItem({
    required this.seriesId,
    this.episodeId,
    this.name,
    this.imageUrl,
    this.date,
    this.time,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeName,
  });
  factory CalendarItem.fromJson(Map<String, dynamic> j) => CalendarItem(
        seriesId: j['series_id'] as int,
        episodeId: j['episode_id'] as int?,
        name: j['name'] as String?,
        imageUrl: j['image_url'] as String?,
        date: j['date'] as String?,
        time: j['time'] as String?,
        seasonNumber: j['season_number'] as int?,
        episodeNumber: j['episode_number'] as int?,
        episodeName: j['episode_name'] as String?,
      );
}

class MatchSuggestion {
  final int id;
  final int deadSeriesId;
  final String importName;
  final int suggestedSeriesId;
  final String? suggestedName;
  final String? imageUrl;
  final int distance;
  const MatchSuggestion({
    required this.id,
    required this.deadSeriesId,
    required this.importName,
    required this.suggestedSeriesId,
    this.suggestedName,
    this.imageUrl,
    required this.distance,
  });
  factory MatchSuggestion.fromJson(Map<String, dynamic> j) => MatchSuggestion(
        id: j['id'] as int,
        deadSeriesId: j['dead_series_id'] as int,
        importName: j['import_name'] as String? ?? '',
        suggestedSeriesId: j['suggested_series_id'] as int,
        suggestedName: j['suggested_name'] as String?,
        imageUrl: j['image_url'] as String?,
        distance: j['distance'] as int? ?? 0,
      );
}

class UserBrief {
  final int id;
  final String screenName;
  final String? avatarUrl;
  final bool isPrivate;
  final bool following;
  final bool requested;
  const UserBrief({
    required this.id,
    required this.screenName,
    this.avatarUrl,
    this.isPrivate = false,
    required this.following,
    this.requested = false,
  });
  factory UserBrief.fromJson(Map<String, dynamic> j) => UserBrief(
        id: j['id'] as int,
        screenName: j['screen_name'] as String? ?? 'user',
        avatarUrl: j['avatar_url'] as String?,
        isPrivate: j['is_private'] as bool? ?? false,
        following: j['following'] as bool? ?? false,
        requested: j['requested'] as bool? ?? false,
      );
}

class UserProfile {
  final int id;
  final String screenName;
  final String? avatarUrl;
  final String? coverUrl;
  final String? bio;
  final bool isPrivate;
  final bool isSelf;
  final bool following;
  final bool requested;
  final bool visible;
  final int followerCount;
  final int followingCount;
  final List<String> profileBlocks;
  const UserProfile({
    required this.id,
    required this.screenName,
    this.avatarUrl,
    this.coverUrl,
    this.bio,
    required this.isPrivate,
    required this.isSelf,
    required this.following,
    required this.requested,
    required this.visible,
    required this.followerCount,
    required this.followingCount,
    this.profileBlocks = const ['stats', 'favorites', 'shows'],
  });
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as int,
        screenName: j['screen_name'] as String? ?? 'user',
        avatarUrl: j['avatar_url'] as String?,
        coverUrl: j['cover_url'] as String?,
        bio: j['bio'] as String?,
        isPrivate: j['is_private'] as bool? ?? false,
        isSelf: j['is_self'] as bool? ?? false,
        following: j['following'] as bool? ?? false,
        requested: j['requested'] as bool? ?? false,
        visible: j['visible'] as bool? ?? false,
        followerCount: j['follower_count'] as int? ?? 0,
        followingCount: j['following_count'] as int? ?? 0,
        profileBlocks: (j['profile_blocks'] as List?)?.cast<String>() ??
            const ['stats', 'favorites', 'shows'],
      );
}

class FeedItem {
  final int userId;
  final String screenName;
  final String? avatarUrl;
  final int? seriesId;
  final String? seriesName;
  final String? seriesImage;
  final int? seasonNumber;
  final int? episodeNumber;
  final bool isRewatch;
  final int? watchedAt;
  const FeedItem({
    required this.userId,
    required this.screenName,
    this.avatarUrl,
    this.seriesId,
    this.seriesName,
    this.seriesImage,
    this.seasonNumber,
    this.episodeNumber,
    required this.isRewatch,
    this.watchedAt,
  });
  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
        userId: j['user_id'] as int,
        screenName: j['screen_name'] as String? ?? 'user',
        avatarUrl: j['avatar_url'] as String?,
        seriesId: j['series_id'] as int?,
        seriesName: j['series_name'] as String?,
        seriesImage: j['series_image'] as String?,
        seasonNumber: j['season_number'] as int?,
        episodeNumber: j['episode_number'] as int?,
        isRewatch: j['is_rewatch'] as bool? ?? false,
        watchedAt: j['watched_at'] as int?,
      );
}

class Stats {
  final int episodesSeen;
  final int episodeWatches;
  final int moviesSeen;
  final int totalMinutes;
  final int showsFollowed;
  final int favorites;
  const Stats({
    required this.episodesSeen,
    required this.episodeWatches,
    required this.moviesSeen,
    required this.totalMinutes,
    required this.showsFollowed,
    required this.favorites,
  });

  factory Stats.fromJson(Map<String, dynamic> j) => Stats(
        episodesSeen: j['episodes_seen'] as int? ?? 0,
        episodeWatches: j['episode_watches'] as int? ?? 0,
        moviesSeen: j['movies_seen'] as int? ?? 0,
        totalMinutes: j['total_minutes'] as int? ?? 0,
        showsFollowed: j['shows_followed'] as int? ?? 0,
        favorites: j['favorites'] as int? ?? 0,
      );
}

/// A freshly created invitation — the `code`/`link` are shown once (the server
/// stores only a hash).
class InviteCreated {
  final String code, link, expiresAt;
  final bool emailed;
  InviteCreated({required this.code, required this.link, required this.expiresAt, required this.emailed});
  factory InviteCreated.fromJson(Map<String, dynamic> j) => InviteCreated(
        code: j['code'] as String? ?? '',
        link: j['link'] as String? ?? '',
        expiresAt: j['expires_at'] as String? ?? '',
        emailed: j['emailed'] as bool? ?? false,
      );
}

/// One of my invitations and its status (the code is never returned again).
class InviteInfo {
  final String? email;
  final String createdAt, expiresAt;
  final bool used;
  InviteInfo({this.email, required this.createdAt, required this.expiresAt, required this.used});
  factory InviteInfo.fromJson(Map<String, dynamic> j) => InviteInfo(
        email: j['email'] as String?,
        createdAt: j['created_at'] as String? ?? '',
        expiresAt: j['expires_at'] as String? ?? '',
        used: j['used'] as bool? ?? false,
      );
}

/// One security-audit entry for the account activity screen.
class SecurityEvent {
  final String event;
  final String? ip;
  final String createdAt;
  final Map<String, dynamic>? detail;
  SecurityEvent({required this.event, this.ip, required this.createdAt, this.detail});
  factory SecurityEvent.fromJson(Map<String, dynamic> j) => SecurityEvent(
        event: j['event'] as String? ?? '',
        ip: j['ip'] as String?,
        createdAt: j['created_at'] as String? ?? '',
        detail: j['detail'] is Map<String, dynamic> ? j['detail'] as Map<String, dynamic> : null,
      );
}
