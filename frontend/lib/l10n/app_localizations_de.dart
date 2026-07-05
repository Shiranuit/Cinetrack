// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Cinetrack';

  @override
  String get navLibrary => 'Bibliothek';

  @override
  String get navDiscover => 'Entdecken';

  @override
  String get navCalendar => 'Kalender';

  @override
  String get navSearch => 'Suche';

  @override
  String get navProfile => 'Profil';

  @override
  String get friends => 'Freunde';

  @override
  String get searchHint => 'Suchen…';

  @override
  String get searchYourShows => 'Deine Serien durchsuchen';

  @override
  String get searchAllShows => 'Alle Serien und Filme suchen';

  @override
  String get libraryNoMatchDiscover =>
      'Nichts in deiner Bibliothek. Finde neue Serien unter Entdecken.';

  @override
  String get typeSeries => 'Serien';

  @override
  String get typeAnime => 'Anime';

  @override
  String get typeMovies => 'Filme';

  @override
  String get typeAll => 'Alle';

  @override
  String get filters => 'Filter';

  @override
  String get loading => 'Lädt…';

  @override
  String get retry => 'Wiederholen';

  @override
  String get noResults => 'Keine Ergebnisse';

  @override
  String get logIn => 'Anmelden';

  @override
  String get signUp => 'Registrieren';

  @override
  String get logOut => 'Abmelden';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get follow => 'Folgen';

  @override
  String get unfollow => 'Entfolgen';

  @override
  String get requested => 'Angefragt';

  @override
  String get requestToFollow => 'Folgen anfragen';

  @override
  String get followers => 'Follower';

  @override
  String get following => 'Folgt';

  @override
  String get statEpisodes => 'Folgen';

  @override
  String get statWatched => 'Verbrachte Zeit';

  @override
  String get statMovies => 'Filme';

  @override
  String get favorites => 'Favoriten';

  @override
  String get shows => 'Serien';

  @override
  String get settings => 'Einstellungen';

  @override
  String get sectionAccount => 'Konto';

  @override
  String get sectionPrivacy => 'Datenschutz';

  @override
  String get sectionAppearance => 'Darstellung';

  @override
  String get sectionLanguages => 'Sprachen';

  @override
  String get sectionData => 'Daten';

  @override
  String get sectionDangerZone => 'Gefahrenzone';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeAuto => 'Automatisch';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldEmail => 'E-Mail';

  @override
  String get changePassword => 'Passwort ändern';

  @override
  String get privateProfile => 'Privates Profil';

  @override
  String get tagline =>
      'Verfolge jede Serie, jeden Film und jedes erneute Ansehen.';

  @override
  String get fieldScreenName => 'Anzeigename';

  @override
  String get fieldPassword => 'Passwort';

  @override
  String get fieldConfirmPassword => 'Passwort bestätigen';

  @override
  String get showPassword => 'Passwort anzeigen';

  @override
  String get hidePassword => 'Passwort verbergen';

  @override
  String get createAccount => 'Konto erstellen';

  @override
  String get haveAccountLogIn => 'Schon ein Konto? Anmelden';

  @override
  String get newHereCreate => 'Neu hier? Konto erstellen';

  @override
  String get pwUppercase => 'Großbuchstabe';

  @override
  String get pwLowercase => 'Kleinbuchstabe';

  @override
  String get pwNumber => 'Zahl';

  @override
  String get pwSpecial => 'Sonderzeichen';

  @override
  String get customizeProfile => 'Profil anpassen';

  @override
  String get accountPrivate => 'Dieses Konto ist privat';

  @override
  String followToSee(String name) {
    return 'Folge $name, um das Profil zu sehen.';
  }

  @override
  String get findPeople => 'Personen finden…';

  @override
  String get followRequests => 'Follow-Anfragen';

  @override
  String get accept => 'Annehmen';

  @override
  String get decline => 'Ablehnen';

  @override
  String get remove => 'Entfernen';

  @override
  String get private => 'Privat';

  @override
  String get status => 'Status';

  @override
  String get forLater => 'Für später';

  @override
  String get stopWatching => 'Nicht mehr ansehen';

  @override
  String get clearStatus => 'Status löschen';

  @override
  String get markAllWatched => 'Alle als gesehen markieren';

  @override
  String get unmarkAll => 'Alle abwählen';

  @override
  String get rewatchSeason => 'Staffel erneut ansehen (+1)';

  @override
  String get rewatchSeries => 'Serie erneut ansehen (+1)';

  @override
  String get seriesActions => 'Serienaktionen';

  @override
  String get seasonActions => 'Staffel-Aktionen';

  @override
  String get markWatched => 'Als gesehen markieren';

  @override
  String get markedWatched => 'Als gesehen markiert';

  @override
  String get removeOneWatch => 'Eine Ansicht entfernen';

  @override
  String get recentlyAired => 'Kürzlich ausgestrahlt';

  @override
  String get upcoming => 'Demnächst';

  @override
  String get openShow => 'Serie öffnen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get clear => 'Löschen';

  @override
  String get favoritesOnly => 'Nur Favoriten';

  @override
  String get sortBy => 'Sortieren nach';

  @override
  String get showResults => 'Ergebnisse anzeigen';

  @override
  String get pw12chars => '12+ Zeichen';

  @override
  String get passwordsDontMatch => 'Passwörter stimmen nicht überein';

  @override
  String get filterOrigLanguage => 'Originalsprache';

  @override
  String get filterOrigCountry => 'Herkunftsland';

  @override
  String get installAndroidBanner => 'Cinetrack läuft als App besser.';

  @override
  String get installAndroidCta => 'Android-App holen';

  @override
  String get forgotPassword => 'Passwort vergessen?';

  @override
  String get resetPassword => 'Passwort zurücksetzen';

  @override
  String get resetLinkSent =>
      'Falls ein Konto für diese Adresse existiert, wurde ein Link zum Zurücksetzen gesendet.';

  @override
  String get passwordUpdated => 'Passwort aktualisiert.';

  @override
  String get newPassword => 'Neues Passwort';

  @override
  String get currentPassword => 'Aktuelles Passwort';

  @override
  String get inviteCode => 'Einladungscode';

  @override
  String get invites => 'Einladungen';

  @override
  String get inviteSent => 'Einladung gesendet.';

  @override
  String get copied => 'In die Zwischenablage kopiert';

  @override
  String get copyLink => 'Link kopieren';

  @override
  String get sendInviteByEmail => 'E-Mail (optional)';

  @override
  String get createInvite => 'Erstellen';

  @override
  String get inviteHelp =>
      'Gib eine E-Mail-Adresse ein, um die Einladung direkt zu senden, oder lass sie leer für einen teilbaren Link.';

  @override
  String get noInvitesYet =>
      'Noch keine Einladungen – erstelle oben eine, um jemanden einzuladen.';

  @override
  String get inviteLink => 'Teilbarer Link';

  @override
  String get expires => 'Läuft ab';

  @override
  String get inviteUsed => 'Verwendet';

  @override
  String get invitePending => 'Ausstehend';

  @override
  String get revoke => 'Widerrufen';

  @override
  String get revokeInviteConfirm =>
      'Diese Einladung widerrufen? Der Link funktioniert dann nicht mehr.';

  @override
  String get inviteRevoked => 'Einladung widerrufen';

  @override
  String get securityActivity => 'Sicherheitsaktivität';

  @override
  String get noActivityYet => 'Noch keine Aktivität.';

  @override
  String get evLoginOk => 'Angemeldet';

  @override
  String get evLoginFail => 'Fehlgeschlagener Anmeldeversuch';

  @override
  String get evPasswordChanged => 'Passwort geändert';

  @override
  String get evResetRequested => 'Passwortzurücksetzung angefordert';

  @override
  String get evResetCompleted => 'Passwortzurücksetzung abgeschlossen';

  @override
  String get evRegistered => 'Konto erstellt';

  @override
  String get evInviteCreated => 'Einladung erstellt';

  @override
  String get evAccountDeleted => 'Konto gelöscht';

  @override
  String get updateAvailable => 'Eine neue Version ist verfügbar';

  @override
  String get update => 'Aktualisieren';

  @override
  String get updateRequired => 'Update erforderlich';

  @override
  String get updateRequiredBody =>
      'Diese Version wird nicht mehr unterstützt. Bitte aktualisiere, um Cinetrack weiter zu nutzen.';

  @override
  String get updateFailed => 'Update fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String get catWatching => 'Wird angesehen';

  @override
  String get catStale => 'Länger nicht gesehen';

  @override
  String get catNotStarted => 'Noch nicht begonnen';

  @override
  String get catUpToDate => 'Aktuell';

  @override
  String get catStopped => 'Gestoppt';

  @override
  String get libSelectKinds =>
      'Wähle Serien, Anime oder Filme,\num deine Bibliothek zu sehen.';

  @override
  String get libEmpty =>
      'Noch nichts hier.\nSuche, um Serien und Filme hinzuzufügen, die du schaust.';

  @override
  String get libNoShows => 'Keine Serien.';

  @override
  String get nothingHereYet => 'Noch nichts hier.';

  @override
  String get filterNoMatch => 'Keine Serien entsprechen diesen Filtern.';

  @override
  String get noTrackedMovies => 'Keine verfolgten Filme.';

  @override
  String get langPriorityHint =>
      'Ziehen, um die Übersetzungspriorität festzulegen. Die erste verfügbare Übersetzung wird verwendet.';

  @override
  String get privacyHint =>
      'Nur akzeptierte Follower können dein Profil und deine Aktivität sehen';

  @override
  String get setNewPassword => 'Neues Passwort festlegen';

  @override
  String get importTvTime => 'TV-Time-Daten importieren';

  @override
  String get importGdprHint => 'Lade deinen DSGVO-Export (.zip) hoch';

  @override
  String get deleteAccount => 'Konto löschen';

  @override
  String get deleteAccountHint => 'Konto und alle Daten dauerhaft entfernen';

  @override
  String get displayName => 'Anzeigename';

  @override
  String get addLanguage => 'Sprache hinzufügen';

  @override
  String get primary => 'Primär';

  @override
  String get statistics => 'Statistiken';

  @override
  String get changePhoto => 'Profilbild ändern';

  @override
  String get changeBackground => 'Hintergrund ändern';

  @override
  String get seeAll => 'Alle ansehen';

  @override
  String get unitMonth => 'Mon.';

  @override
  String get unitDay => 'T';

  @override
  String get unitHour => 'Std.';

  @override
  String get specials => 'Specials';

  @override
  String season(int number) {
    return 'Staffel $number';
  }

  @override
  String get episodesSeen => 'Folgen gesehen';

  @override
  String get rateThisShow => 'Serie bewerten';

  @override
  String get today => 'Heute';

  @override
  String get day => 'Tag';

  @override
  String get days => 'Tage';

  @override
  String get sortPopular => 'Beliebt';

  @override
  String get sortTopRated => 'Am besten bewertet';

  @override
  String get sortReleaseDate => 'Erscheinungsdatum';

  @override
  String get sortLastUpdated => 'Zuletzt aktualisiert';

  @override
  String get seasons => 'Staffeln';

  @override
  String get episodes => 'Folgen';

  @override
  String get sortLongest => 'Längste';

  @override
  String get genres => 'Genres';

  @override
  String get themes => 'Themen';

  @override
  String get networks => 'Sender';

  @override
  String get studios => 'Studios';

  @override
  String get releaseYear => 'Erscheinungsjahr';

  @override
  String get runtimeLength => 'Folgen-/Filmlänge';

  @override
  String get filterAny => 'Alle';

  @override
  String get triStateHint => 'tippen: einschließen → ausschließen → aus';

  @override
  String get statusContinuing => 'Laufend';

  @override
  String get statusEnded => 'Beendet';

  @override
  String get statusUpcoming => 'Demnächst';

  @override
  String get noFollowingYet =>
      'Du folgst noch niemandem.\nSuche oben, um Leute zu finden.';

  @override
  String sortedBy(String sort) {
    return 'Sortiert nach $sort';
  }

  @override
  String filteredSummary(int count, String sort) {
    return 'Gefiltert · $count aktiv · $sort';
  }

  @override
  String get showFollowing => 'Folge ich';

  @override
  String yourRating(int rating) {
    return 'Deine Bewertung · $rating/10';
  }

  @override
  String searchIn(String name) {
    return '$name suchen…';
  }

  @override
  String get refineSearch => 'Verfeinere deine Suche, um mehr zu sehen…';

  @override
  String get runtimeUnder30 => '< 30 Min.';

  @override
  String get runtime30to60 => '30–60 Min.';

  @override
  String get runtimeOver60 => '> 60 Min.';

  @override
  String get sortName => 'A–Z';

  @override
  String nSelected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get calendarEmpty =>
      'Nichts geplant.\nFolge laufenden Serien, um sie hier zu sehen.';

  @override
  String seriesFallback(int id) {
    return 'Serie $id';
  }

  @override
  String get discoverEmpty =>
      'Noch keine Treffer in deinem Katalog.\nImportiere oder suche Serien, um ihn zu füllen, und filtere dann hier.';

  @override
  String get noUsersFound => 'Keine Benutzer gefunden.';

  @override
  String get reviewImportMatches => 'Import-Zuordnungen prüfen';

  @override
  String get nothingToReview =>
      'Nichts zu prüfen.\nAlle importierten Serien sind zugeordnet.';

  @override
  String get importMatchesIntro =>
      'Die ursprünglichen IDs dieser Serien sind bei TheTVDB nicht mehr vorhanden. Wir haben wahrscheinliche Treffer gefunden – bestätige die richtigen und verwirf den Rest.';

  @override
  String get youImported => 'Du hast importiert';

  @override
  String get likelyMatch => 'wahrscheinlicher Treffer';

  @override
  String get notIt => 'Passt nicht';

  @override
  String get confirm => 'Bestätigen';

  @override
  String matchedTo(String name) {
    return 'Zugeordnet zu $name';
  }

  @override
  String dismissedImport(String name) {
    return '„$name“ verworfen';
  }

  @override
  String seriesWithId(int id) {
    return 'Serie $id';
  }

  @override
  String get ok => 'OK';

  @override
  String get gridView => 'Rasteransicht';

  @override
  String get carouselView => 'Karussellansicht';

  @override
  String get filterLibrary => 'Bibliothek filtern';

  @override
  String get kindMovie => 'Film';

  @override
  String watchedTimes(int count) {
    return 'Gesehen ×$count';
  }

  @override
  String get favorite => 'Favorit';

  @override
  String get unfavorite => 'Aus Favoriten entfernen';

  @override
  String get movie => 'Film';

  @override
  String movieNumbered(int id) {
    return 'Film $id';
  }

  @override
  String usersFavorites(String name) {
    return 'Favoriten von $name';
  }

  @override
  String usersShows(String name) {
    return 'Serien von $name';
  }

  @override
  String get yourShows => 'Deine Serien';

  @override
  String get yourMovies => 'Deine Filme';

  @override
  String usersMovies(String name) {
    return 'Filme von $name';
  }

  @override
  String importGdprSuccess(int shows, int watches, int favorites) {
    return '$shows Serien · $watches Ansichten · $favorites Favoriten importiert.\nFehlende Serien werden im Hintergrund abgeglichen — sieh dir in Kürze „Import-Treffer prüfen“ an.';
  }

  @override
  String get deleteAccountConfirmBody =>
      'Dadurch werden dein Konto und alle deine Daten dauerhaft gelöscht — verfolgte Serien, Wiedergabeverlauf, Favoriten und Abonnements. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get deleteAnyway => 'Trotzdem löschen';

  @override
  String get keepMyAccount => 'Konto behalten';

  @override
  String get nameCannotBeEmpty => 'Der Name darf nicht leer sein';

  @override
  String get enterValidEmail => 'Gib eine gültige E-Mail-Adresse ein';

  @override
  String get profileUpdated => 'Profil aktualisiert.';

  @override
  String showsNeedConfirming(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Serien müssen bestätigt werden',
      one: '$count Serie muss bestätigt werden',
    );
    return '$_temp0';
  }

  @override
  String showFallback(int id) {
    return 'Serie $id';
  }

  @override
  String get filterAndSort => 'Filtern & sortieren';

  @override
  String movieFallback(int id) {
    return 'Film $id';
  }

  @override
  String ratingStars(int rating) {
    return '★ $rating/10';
  }

  @override
  String get markWatchedAgain => 'Erneut als gesehen markieren';

  @override
  String get addToFavorites => 'Zu Favoriten hinzufügen';

  @override
  String get addedToFavorites => 'Zu Favoriten hinzugefügt';

  @override
  String get watchLater => 'Später ansehen';

  @override
  String get markedForLater => 'Für später markiert';

  @override
  String get stoppedWatching => 'Ansehen gestoppt';

  @override
  String get removeFromLibrary => 'Aus Bibliothek entfernen';

  @override
  String get removed => 'Entfernt';

  @override
  String get seriesGeneric => 'Serie';
}
