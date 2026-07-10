// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Cinetrack';

  @override
  String get navLibrary => 'Bibliothèque';

  @override
  String get navDiscover => 'Découvrir';

  @override
  String get navCalendar => 'Calendrier';

  @override
  String get navSearch => 'Rechercher';

  @override
  String get navProfile => 'Profil';

  @override
  String get friends => 'Amis';

  @override
  String get searchHint => 'Rechercher…';

  @override
  String get searchYourShows => 'Rechercher dans votre bibliothèque';

  @override
  String get searchAllShows => 'Rechercher séries et films';

  @override
  String get libraryNoMatchDiscover =>
      'Rien dans votre bibliothèque. Trouvez de nouvelles séries dans Découvrir.';

  @override
  String get typeSeries => 'Séries';

  @override
  String get typeAnime => 'Animés';

  @override
  String get typeMovies => 'Films';

  @override
  String get typeAll => 'Tout';

  @override
  String get filters => 'Filtres';

  @override
  String get inLibrary => 'Dans ma liste';

  @override
  String get loading => 'Chargement…';

  @override
  String get retry => 'Réessayer';

  @override
  String get noResults => 'Aucun résultat';

  @override
  String get logIn => 'Se connecter';

  @override
  String get signUp => 'S\'inscrire';

  @override
  String get logOut => 'Se déconnecter';

  @override
  String get save => 'Enregistrer';

  @override
  String get download => 'Télécharger';

  @override
  String get cancel => 'Annuler';

  @override
  String get follow => 'Suivre';

  @override
  String get unfollow => 'Ne plus suivre';

  @override
  String get requested => 'Demandé';

  @override
  String get requestToFollow => 'Demander à suivre';

  @override
  String get followers => 'Abonnés';

  @override
  String get following => 'Abonnements';

  @override
  String get followingUser => 'Abonné';

  @override
  String get statEpisodes => 'Épisodes';

  @override
  String get statWatched => 'Temps passé';

  @override
  String get statMovies => 'Films';

  @override
  String get favorites => 'Favoris';

  @override
  String get shows => 'Séries';

  @override
  String get settings => 'Paramètres';

  @override
  String get sectionAccount => 'Compte';

  @override
  String get sectionPrivacy => 'Confidentialité';

  @override
  String get sectionAppearance => 'Apparence';

  @override
  String get sectionLanguages => 'Langues';

  @override
  String get sectionData => 'Données';

  @override
  String get sectionDangerZone => 'Zone de danger';

  @override
  String get themeDark => 'Sombre';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeAuto => 'Auto';

  @override
  String get fieldName => 'Nom';

  @override
  String get fieldEmail => 'E-mail';

  @override
  String get changePassword => 'Changer le mot de passe';

  @override
  String get privateProfile => 'Profil privé';

  @override
  String get tagline => 'Suivez chaque série, film et visionnage.';

  @override
  String get fieldScreenName => 'Nom d\'affichage';

  @override
  String get fieldPassword => 'Mot de passe';

  @override
  String get fieldConfirmPassword => 'Confirmer le mot de passe';

  @override
  String get showPassword => 'Afficher le mot de passe';

  @override
  String get hidePassword => 'Masquer le mot de passe';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get haveAccountLogIn => 'Vous avez un compte ? Se connecter';

  @override
  String get newHereCreate => 'Nouveau ici ? Créer un compte';

  @override
  String get pwUppercase => 'Majuscule';

  @override
  String get pwLowercase => 'Minuscule';

  @override
  String get pwNumber => 'Chiffre';

  @override
  String get pwSpecial => 'Caractère spécial';

  @override
  String get customizeProfile => 'Personnaliser le profil';

  @override
  String get accountPrivate => 'Ce compte est privé';

  @override
  String followToSee(String name) {
    return 'Suivez $name pour voir son profil.';
  }

  @override
  String get findPeople => 'Trouver des personnes…';

  @override
  String get followRequests => 'Demandes d\'abonnement';

  @override
  String get accept => 'Accepter';

  @override
  String get decline => 'Refuser';

  @override
  String get remove => 'Retirer';

  @override
  String get private => 'Privé';

  @override
  String get status => 'Statut';

  @override
  String get forLater => 'Pour plus tard';

  @override
  String get stopWatching => 'Arrêter de regarder';

  @override
  String get clearStatus => 'Effacer le statut';

  @override
  String get markAllWatched => 'Tout marquer comme vu';

  @override
  String get unmarkAll => 'Tout démarquer';

  @override
  String get rewatchSeason => 'Revoir la saison (+1)';

  @override
  String get rewatchSeries => 'Revoir la série (+1)';

  @override
  String get removeOneWatch => 'Retirer un visionnage';

  @override
  String get seriesActions => 'Actions sur la série';

  @override
  String get seasonActions => 'Actions sur la saison';

  @override
  String get markWatched => 'Marquer comme vu';

  @override
  String get markedWatched => 'Marqué comme vu';

  @override
  String get recentlyAired => 'Diffusé récemment';

  @override
  String get showOlder => 'Voir plus anciens';

  @override
  String get upcoming => 'À venir';

  @override
  String get openShow => 'Ouvrir la série';

  @override
  String get reset => 'Réinitialiser';

  @override
  String get clear => 'Effacer';

  @override
  String get favoritesOnly => 'Favoris uniquement';

  @override
  String get sortBy => 'Trier par';

  @override
  String get showResults => 'Voir les résultats';

  @override
  String get pw12chars => '12+ caractères';

  @override
  String get passwordsDontMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get filterOrigLanguage => 'Langue originale';

  @override
  String get filterOrigCountry => 'Pays d\'origine';

  @override
  String get installAndroidBanner =>
      'Cinetrack, c\'est encore mieux en application.';

  @override
  String get installAndroidCta => 'Télécharger l\'app Android';

  @override
  String get forgotPassword => 'Mot de passe oublié ?';

  @override
  String get resetPassword => 'Réinitialiser le mot de passe';

  @override
  String get resetLinkSent =>
      'Si un compte existe pour cette adresse, un lien de réinitialisation a été envoyé.';

  @override
  String get passwordUpdated => 'Mot de passe mis à jour.';

  @override
  String get newPassword => 'Nouveau mot de passe';

  @override
  String get currentPassword => 'Mot de passe actuel';

  @override
  String get inviteCode => 'Code d\'invitation';

  @override
  String get invites => 'Invitations';

  @override
  String get inviteSent => 'Invitation envoyée.';

  @override
  String get copied => 'Copié dans le presse-papiers';

  @override
  String get copyLink => 'Copier le lien';

  @override
  String get sendInviteByEmail => 'E-mail (facultatif)';

  @override
  String get createInvite => 'Créer';

  @override
  String get inviteHelp =>
      'Saisissez un e-mail pour envoyer l\'invitation directement, ou laissez vide pour obtenir un lien à partager.';

  @override
  String get noInvitesYet =>
      'Aucune invitation — créez-en une ci-dessus pour inviter quelqu\'un.';

  @override
  String get inviteLink => 'Lien à partager';

  @override
  String get expires => 'Expire';

  @override
  String get inviteUsed => 'Utilisée';

  @override
  String get invitePending => 'En attente';

  @override
  String get revoke => 'Révoquer';

  @override
  String get revokeInviteConfirm =>
      'Révoquer cette invitation ? Le lien cessera de fonctionner.';

  @override
  String get inviteRevoked => 'Invitation révoquée';

  @override
  String get securityActivity => 'Activité de sécurité';

  @override
  String get noActivityYet => 'Aucune activité.';

  @override
  String get evLoginOk => 'Connexion';

  @override
  String get evLoginFail => 'Tentative de connexion échouée';

  @override
  String get evPasswordChanged => 'Mot de passe modifié';

  @override
  String get evResetRequested => 'Réinitialisation demandée';

  @override
  String get evResetCompleted => 'Réinitialisation effectuée';

  @override
  String get evRegistered => 'Compte créé';

  @override
  String get evInviteCreated => 'Invitation créée';

  @override
  String get evAccountDeleted => 'Compte supprimé';

  @override
  String get updateAvailable => 'Une nouvelle version est disponible';

  @override
  String get update => 'Mettre à jour';

  @override
  String get updateRequired => 'Mise à jour requise';

  @override
  String get updateRequiredBody =>
      'Cette version n\'est plus prise en charge. Veuillez mettre à jour pour continuer à utiliser Cinetrack.';

  @override
  String get updateFailed => 'Échec de la mise à jour. Veuillez réessayer.';

  @override
  String get catWatching => 'En cours';

  @override
  String get catStale => 'Pas regardé depuis un moment';

  @override
  String get catNotStarted => 'Pas commencé';

  @override
  String get catUpToDate => 'À jour';

  @override
  String get catStopped => 'Arrêté';

  @override
  String get libSelectKinds =>
      'Sélectionnez Séries, Animés ou Films\npour voir votre bibliothèque.';

  @override
  String get libEmpty =>
      'Rien pour l\'instant.\nRecherchez pour ajouter des séries et films que vous regardez.';

  @override
  String get libNoShows => 'Aucune série.';

  @override
  String get nothingHereYet => 'Rien pour l\'instant.';

  @override
  String get filterNoMatch => 'Aucune série ne correspond à ces filtres.';

  @override
  String get noTrackedMovies => 'Aucun film suivi.';

  @override
  String get langPriorityHint =>
      'Faites glisser pour définir la priorité de traduction. La première traduction disponible est utilisée.';

  @override
  String get privacyHint =>
      'Seuls les abonnés acceptés peuvent voir votre profil et votre activité';

  @override
  String get setNewPassword => 'Définir un nouveau mot de passe';

  @override
  String get importTvTime => 'Importer les données TV Time';

  @override
  String get importGdprHint => 'Importez votre export RGPD (.zip)';

  @override
  String get deleteAccount => 'Supprimer le compte';

  @override
  String get deleteAccountHint =>
      'Supprimer définitivement votre compte et toutes vos données';

  @override
  String get displayName => 'Nom d\'affichage';

  @override
  String get addLanguage => 'Ajouter une langue';

  @override
  String get primary => 'Principale';

  @override
  String get statistics => 'Statistiques';

  @override
  String get changePhoto => 'Changer la photo de profil';

  @override
  String get changeBackground => 'Changer l\'arrière-plan';

  @override
  String get seeAll => 'Voir tout';

  @override
  String get unitMonth => 'mois';

  @override
  String get unitDay => 'j';

  @override
  String get unitHour => 'h';

  @override
  String get specials => 'Épisodes spéciaux';

  @override
  String season(int number) {
    return 'Saison $number';
  }

  @override
  String get episodesSeen => 'épisodes vus';

  @override
  String get rateThisShow => 'Noter cette série';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get day => 'jour';

  @override
  String get days => 'jours';

  @override
  String get sortPopular => 'Populaire';

  @override
  String get sortTopRated => 'Les mieux notés';

  @override
  String get sortReleaseDate => 'Date de sortie';

  @override
  String get sortLastUpdated => 'Dernière mise à jour';

  @override
  String get seasons => 'Saisons';

  @override
  String get episodes => 'Épisodes';

  @override
  String get sortLongest => 'Les plus longs';

  @override
  String get genres => 'Genres';

  @override
  String get themes => 'Thèmes';

  @override
  String get networks => 'Chaînes';

  @override
  String get studios => 'Studios';

  @override
  String get releaseYear => 'Année de sortie';

  @override
  String get runtimeLength => 'Durée épisode / film';

  @override
  String get filterAny => 'Tous';

  @override
  String get triStateHint => 'toucher : inclure → exclure → désactivé';

  @override
  String get statusContinuing => 'En cours';

  @override
  String get statusEnded => 'Terminée';

  @override
  String get statusUpcoming => 'À venir';

  @override
  String get noFollowingYet =>
      'Vous ne suivez personne pour l\'instant.\nRecherchez ci-dessus pour trouver des personnes.';

  @override
  String sortedBy(String sort) {
    return 'Trié par $sort';
  }

  @override
  String filteredSummary(int count, String sort) {
    return 'Filtré · $count actif · $sort';
  }

  @override
  String get showFollowing => 'Suivi';

  @override
  String yourRating(int rating) {
    return 'Votre note · $rating/10';
  }

  @override
  String searchIn(String name) {
    return 'Rechercher $name…';
  }

  @override
  String get refineSearch => 'Affinez votre recherche pour voir plus…';

  @override
  String get runtimeUnder30 => '< 30 min';

  @override
  String get runtime30to60 => '30–60 min';

  @override
  String get runtimeOver60 => '> 60 min';

  @override
  String get sortName => 'A–Z';

  @override
  String nSelected(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String get calendarEmpty =>
      'Rien de prévu.\nSuivez des séries en cours de diffusion pour les voir ici.';

  @override
  String seriesFallback(int id) {
    return 'Série $id';
  }

  @override
  String get discoverEmpty =>
      'Aucune correspondance dans votre catalogue pour l\'instant.\nImportez ou recherchez des séries pour le remplir, puis filtrez ici.';

  @override
  String get noUsersFound => 'Aucun utilisateur trouvé.';

  @override
  String get reviewImportMatches => 'Vérifier les correspondances d\'import';

  @override
  String get nothingToReview =>
      'Rien à vérifier.\nToutes les séries importées sont associées.';

  @override
  String get importMatchesIntro =>
      'Les identifiants d\'origine de ces séries ont disparu de TheTVDB. Nous avons trouvé des correspondances probables — confirmez les bonnes, ignorez les autres.';

  @override
  String get youImported => 'Vous avez importé';

  @override
  String get likelyMatch => 'correspondance probable';

  @override
  String get notIt => 'Ce n\'est pas ça';

  @override
  String get confirm => 'Confirmer';

  @override
  String matchedTo(String name) {
    return 'Associé à $name';
  }

  @override
  String dismissedImport(String name) {
    return '« $name » ignoré';
  }

  @override
  String seriesWithId(int id) {
    return 'série $id';
  }

  @override
  String get ok => 'OK';

  @override
  String get gridView => 'Vue en grille';

  @override
  String get carouselView => 'Vue en carrousel';

  @override
  String get filterLibrary => 'Filtrer la bibliothèque';

  @override
  String get kindMovie => 'Film';

  @override
  String watchedTimes(int count) {
    return 'Vu ×$count';
  }

  @override
  String get favorite => 'Favori';

  @override
  String get unfavorite => 'Retirer des favoris';

  @override
  String get movie => 'Film';

  @override
  String movieNumbered(int id) {
    return 'Film $id';
  }

  @override
  String usersFavorites(String name) {
    return 'Favoris de $name';
  }

  @override
  String usersShows(String name) {
    return 'Séries de $name';
  }

  @override
  String get yourShows => 'Vos séries';

  @override
  String get yourMovies => 'Vos films';

  @override
  String usersMovies(String name) {
    return 'Films de $name';
  }

  @override
  String importGdprSuccess(int shows, int watches, int favorites) {
    return '$shows séries · $watches visionnages · $favorites favoris importés.\nRecherche des séries manquantes en arrière-plan — consultez « Vérifier les correspondances » sous peu.';
  }

  @override
  String get deleteAccountConfirmBody =>
      'Cette action supprime définitivement votre compte et toutes vos données — séries suivies, historique de visionnage, favoris et abonnements. Cette action est irréversible.';

  @override
  String get deleteAnyway => 'Supprimer quand même';

  @override
  String get keepMyAccount => 'Conserver mon compte';

  @override
  String get deleteConfirmKeyword => 'SUPPRIMER';

  @override
  String deleteConfirmPrompt(String word) {
    return 'Saisissez $word pour confirmer';
  }

  @override
  String get nameCannotBeEmpty => 'Le nom ne peut pas être vide';

  @override
  String get enterValidEmail => 'Saisissez une adresse e-mail valide';

  @override
  String get profileUpdated => 'Profil mis à jour.';

  @override
  String showsNeedConfirming(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count séries à confirmer',
      one: '$count série à confirmer',
    );
    return '$_temp0';
  }

  @override
  String showFallback(int id) {
    return 'Série $id';
  }

  @override
  String get filterAndSort => 'Filtrer et trier';

  @override
  String movieFallback(int id) {
    return 'Film $id';
  }

  @override
  String ratingStars(int rating) {
    return '★ $rating/10';
  }

  @override
  String get markWatchedAgain => 'Marquer comme vu à nouveau';

  @override
  String get addToFavorites => 'Ajouter aux favoris';

  @override
  String get addedToFavorites => 'Ajouté aux favoris';

  @override
  String get watchLater => 'Regarder plus tard';

  @override
  String get markedForLater => 'Marqué pour plus tard';

  @override
  String get stoppedWatching => 'Arrêt du visionnage';

  @override
  String get removeFromLibrary => 'Retirer de la bibliothèque';

  @override
  String get removed => 'Retiré';

  @override
  String get seriesGeneric => 'série';

  @override
  String get moreDetails => 'Plus de détails';

  @override
  String get showDetails => 'Détails';

  @override
  String get communityRating => 'Note de la communauté';

  @override
  String get language => 'Langue';

  @override
  String get country => 'Pays';

  @override
  String get aired => 'Diffusion';

  @override
  String get episodeLength => 'Durée d\'un épisode';

  @override
  String get alsoKnownAs => 'Aussi connu sous';

  @override
  String seasonsCount(int n) {
    return '$n saisons';
  }

  @override
  String runtimeMinutes(int n) {
    return '~$n min';
  }

  @override
  String episodesCount(int n) {
    return '$n épisodes';
  }

  @override
  String bulkUpdated(int count) {
    return '$count mis à jour';
  }

  @override
  String get rateHate => 'Je déteste';

  @override
  String get rateDislike => 'Je n\'aime pas';

  @override
  String get rateOk => 'Bof';

  @override
  String get rateLike => 'J\'aime bien';

  @override
  String get rateLove => 'J\'adore';

  @override
  String get updateOpenToInstall =>
      'Téléchargement de la mise à jour. Ouvrez le fichier pour l\'installer.';

  @override
  String get sortMyRating => 'Votre note';

  @override
  String get sortAscending => 'Croissant';

  @override
  String get sortDescending => 'Décroissant';

  @override
  String get inMyLibrary => 'Dans ma bibliothèque';
}
