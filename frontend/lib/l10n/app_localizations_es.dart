// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Cinetrack';

  @override
  String get navLibrary => 'Biblioteca';

  @override
  String get navDiscover => 'Descubrir';

  @override
  String get navCalendar => 'Calendario';

  @override
  String get navSearch => 'Buscar';

  @override
  String get navProfile => 'Perfil';

  @override
  String get friends => 'Amigos';

  @override
  String get searchHint => 'Buscar…';

  @override
  String get searchYourShows => 'Buscar en tus series';

  @override
  String get searchAllShows => 'Buscar series y películas';

  @override
  String get libraryNoMatchDiscover =>
      'Nada en tu biblioteca. Encuentra nuevas series en Descubrir.';

  @override
  String get typeSeries => 'Series';

  @override
  String get typeAnime => 'Anime';

  @override
  String get typeMovies => 'Películas';

  @override
  String get typeAll => 'Todo';

  @override
  String get filters => 'Filtros';

  @override
  String get loading => 'Cargando…';

  @override
  String get retry => 'Reintentar';

  @override
  String get noResults => 'Sin resultados';

  @override
  String get logIn => 'Iniciar sesión';

  @override
  String get signUp => 'Registrarse';

  @override
  String get logOut => 'Cerrar sesión';

  @override
  String get save => 'Guardar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get follow => 'Seguir';

  @override
  String get unfollow => 'Dejar de seguir';

  @override
  String get requested => 'Solicitado';

  @override
  String get requestToFollow => 'Solicitar seguir';

  @override
  String get followers => 'Seguidores';

  @override
  String get following => 'Siguiendo';

  @override
  String get statEpisodes => 'Episodios';

  @override
  String get statWatched => 'Tiempo dedicado';

  @override
  String get statMovies => 'Películas';

  @override
  String get favorites => 'Favoritos';

  @override
  String get shows => 'Series';

  @override
  String get settings => 'Ajustes';

  @override
  String get sectionAccount => 'Cuenta';

  @override
  String get sectionPrivacy => 'Privacidad';

  @override
  String get sectionAppearance => 'Apariencia';

  @override
  String get sectionLanguages => 'Idiomas';

  @override
  String get sectionData => 'Datos';

  @override
  String get sectionDangerZone => 'Zona de peligro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeAuto => 'Automático';

  @override
  String get fieldName => 'Nombre';

  @override
  String get fieldEmail => 'Correo electrónico';

  @override
  String get changePassword => 'Cambiar contraseña';

  @override
  String get privateProfile => 'Perfil privado';

  @override
  String get tagline => 'Sigue cada serie, película y revisionado.';

  @override
  String get fieldScreenName => 'Nombre visible';

  @override
  String get fieldPassword => 'Contraseña';

  @override
  String get fieldConfirmPassword => 'Confirmar contraseña';

  @override
  String get showPassword => 'Mostrar contraseña';

  @override
  String get hidePassword => 'Ocultar contraseña';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get haveAccountLogIn => '¿Ya tienes cuenta? Inicia sesión';

  @override
  String get newHereCreate => '¿Eres nuevo? Crea una cuenta';

  @override
  String get pwUppercase => 'Mayúscula';

  @override
  String get pwLowercase => 'Minúscula';

  @override
  String get pwNumber => 'Número';

  @override
  String get pwSpecial => 'Especial';

  @override
  String get customizeProfile => 'Personalizar perfil';

  @override
  String get accountPrivate => 'Esta cuenta es privada';

  @override
  String followToSee(String name) {
    return 'Sigue a $name para ver su perfil.';
  }

  @override
  String get findPeople => 'Buscar personas…';

  @override
  String get followRequests => 'Solicitudes de seguimiento';

  @override
  String get accept => 'Aceptar';

  @override
  String get decline => 'Rechazar';

  @override
  String get remove => 'Quitar';

  @override
  String get private => 'Privado';

  @override
  String get status => 'Estado';

  @override
  String get forLater => 'Para más tarde';

  @override
  String get stopWatching => 'Dejar de ver';

  @override
  String get clearStatus => 'Borrar estado';

  @override
  String get markAllWatched => 'Marcar todo como visto';

  @override
  String get unmarkAll => 'Desmarcar todo';

  @override
  String get rewatchSeason => 'Volver a ver la temporada (+1)';

  @override
  String get rewatchSeries => 'Volver a ver la serie (+1)';

  @override
  String get seriesActions => 'Acciones de la serie';

  @override
  String get seasonActions => 'Acciones de temporada';

  @override
  String get markWatched => 'Marcar como visto';

  @override
  String get markedWatched => 'Marcado como visto';

  @override
  String get removeOneWatch => 'Quitar una visualización';

  @override
  String get recentlyAired => 'Emitido recientemente';

  @override
  String get upcoming => 'Próximamente';

  @override
  String get openShow => 'Abrir serie';

  @override
  String get reset => 'Restablecer';

  @override
  String get clear => 'Borrar';

  @override
  String get favoritesOnly => 'Solo favoritos';

  @override
  String get sortBy => 'Ordenar por';

  @override
  String get showResults => 'Ver resultados';

  @override
  String get pw12chars => '12+ caracteres';

  @override
  String get passwordsDontMatch => 'Las contraseñas no coinciden';

  @override
  String get filterOrigLanguage => 'Idioma original';

  @override
  String get filterOrigCountry => 'País de origen';

  @override
  String get installAndroidBanner => 'Cinetrack funciona mejor como app.';

  @override
  String get installAndroidCta => 'Obtener la app de Android';

  @override
  String get forgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get resetPassword => 'Restablecer contraseña';

  @override
  String get resetLinkSent =>
      'Si existe una cuenta con esa dirección, se ha enviado un enlace para restablecerla.';

  @override
  String get passwordUpdated => 'Contraseña actualizada.';

  @override
  String get newPassword => 'Nueva contraseña';

  @override
  String get currentPassword => 'Contraseña actual';

  @override
  String get inviteCode => 'Código de invitación';

  @override
  String get invites => 'Invitaciones';

  @override
  String get inviteSent => 'Invitación enviada.';

  @override
  String get copied => 'Copiado al portapapeles';

  @override
  String get copyLink => 'Copiar enlace';

  @override
  String get sendInviteByEmail => 'Correo electrónico (opcional)';

  @override
  String get createInvite => 'Crear';

  @override
  String get inviteHelp =>
      'Introduce un correo para enviar la invitación directamente, o déjalo en blanco para obtener un enlace para compartir.';

  @override
  String get noInvitesYet =>
      'Aún no hay invitaciones: crea una arriba para invitar a alguien.';

  @override
  String get inviteLink => 'Enlace para compartir';

  @override
  String get expires => 'Caduca';

  @override
  String get inviteUsed => 'Usada';

  @override
  String get invitePending => 'Pendiente';

  @override
  String get revoke => 'Revocar';

  @override
  String get revokeInviteConfirm =>
      '¿Revocar esta invitación? El enlace dejará de funcionar.';

  @override
  String get inviteRevoked => 'Invitación revocada';

  @override
  String get securityActivity => 'Actividad de seguridad';

  @override
  String get noActivityYet => 'Aún no hay actividad.';

  @override
  String get evLoginOk => 'Sesión iniciada';

  @override
  String get evLoginFail => 'Intento de inicio de sesión fallido';

  @override
  String get evPasswordChanged => 'Contraseña cambiada';

  @override
  String get evResetRequested => 'Restablecimiento de contraseña solicitado';

  @override
  String get evResetCompleted => 'Restablecimiento de contraseña completado';

  @override
  String get evRegistered => 'Cuenta creada';

  @override
  String get evInviteCreated => 'Invitación creada';

  @override
  String get evAccountDeleted => 'Cuenta eliminada';

  @override
  String get updateAvailable => 'Hay una nueva versión disponible';

  @override
  String get update => 'Actualizar';

  @override
  String get updateRequired => 'Actualización necesaria';

  @override
  String get updateRequiredBody =>
      'Esta versión ya no es compatible. Actualiza para seguir usando Cinetrack.';

  @override
  String get updateFailed => 'La actualización falló. Inténtalo de nuevo.';

  @override
  String get catWatching => 'Viendo';

  @override
  String get catStale => 'Sin ver desde hace tiempo';

  @override
  String get catNotStarted => 'Sin empezar';

  @override
  String get catUpToDate => 'Al día';

  @override
  String get catStopped => 'Detenido';

  @override
  String get libSelectKinds =>
      'Selecciona Series, Anime o Películas\npara ver tu biblioteca.';

  @override
  String get libEmpty =>
      'Todavía no hay nada.\nBusca para añadir series y películas que ves.';

  @override
  String get libNoShows => 'Sin series.';

  @override
  String get nothingHereYet => 'Todavía no hay nada.';

  @override
  String get filterNoMatch => 'Ninguna serie coincide con estos filtros.';

  @override
  String get noTrackedMovies => 'Sin películas seguidas.';

  @override
  String get langPriorityHint =>
      'Arrastra para definir la prioridad de traducción. Se usa la primera traducción disponible.';

  @override
  String get privacyHint =>
      'Solo los seguidores aceptados pueden ver tu perfil y tu actividad';

  @override
  String get setNewPassword => 'Establecer una nueva contraseña';

  @override
  String get importTvTime => 'Importar datos de TV Time';

  @override
  String get importGdprHint => 'Sube tu exportación RGPD (.zip)';

  @override
  String get deleteAccount => 'Eliminar cuenta';

  @override
  String get deleteAccountHint =>
      'Eliminar permanentemente tu cuenta y todos los datos';

  @override
  String get displayName => 'Nombre visible';

  @override
  String get addLanguage => 'Añadir un idioma';

  @override
  String get primary => 'Principal';

  @override
  String get statistics => 'Estadísticas';

  @override
  String get changePhoto => 'Cambiar foto de perfil';

  @override
  String get changeBackground => 'Cambiar fondo';

  @override
  String get seeAll => 'Ver todo';

  @override
  String get unitMonth => 'mes';

  @override
  String get unitDay => 'd';

  @override
  String get unitHour => 'h';

  @override
  String get specials => 'Especiales';

  @override
  String season(int number) {
    return 'Temporada $number';
  }

  @override
  String get episodesSeen => 'episodios vistos';

  @override
  String get rateThisShow => 'Calificar esta serie';

  @override
  String get today => 'Hoy';

  @override
  String get day => 'día';

  @override
  String get days => 'días';

  @override
  String get sortPopular => 'Popular';

  @override
  String get sortTopRated => 'Mejor valorado';

  @override
  String get sortReleaseDate => 'Fecha de estreno';

  @override
  String get sortLastUpdated => 'Última actualización';

  @override
  String get seasons => 'Temporadas';

  @override
  String get episodes => 'Episodios';

  @override
  String get sortLongest => 'Más largos';

  @override
  String get genres => 'Géneros';

  @override
  String get themes => 'Temas';

  @override
  String get networks => 'Cadenas';

  @override
  String get studios => 'Estudios';

  @override
  String get releaseYear => 'Año de estreno';

  @override
  String get runtimeLength => 'Duración episodio / película';

  @override
  String get filterAny => 'Todos';

  @override
  String get triStateHint => 'toca: incluir → excluir → desactivado';

  @override
  String get statusContinuing => 'En emisión';

  @override
  String get statusEnded => 'Finalizada';

  @override
  String get statusUpcoming => 'Próximamente';

  @override
  String get noFollowingYet =>
      'Aún no sigues a nadie.\nBusca arriba para encontrar personas.';

  @override
  String sortedBy(String sort) {
    return 'Ordenado por $sort';
  }

  @override
  String filteredSummary(int count, String sort) {
    return 'Filtrado · $count activos · $sort';
  }

  @override
  String get showFollowing => 'Siguiendo';

  @override
  String yourRating(int rating) {
    return 'Tu valoración · $rating/10';
  }

  @override
  String searchIn(String name) {
    return 'Buscar $name…';
  }

  @override
  String get refineSearch => 'Refina tu búsqueda para ver más…';

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
    return '$count seleccionado(s)';
  }

  @override
  String get calendarEmpty =>
      'Nada programado.\nSigue series en emisión para verlas aquí.';

  @override
  String seriesFallback(int id) {
    return 'Serie $id';
  }

  @override
  String get discoverEmpty =>
      'Aún no hay coincidencias en tu catálogo.\nImporta o busca series para llenarlo y luego filtra aquí.';

  @override
  String get noUsersFound => 'No se encontraron usuarios.';

  @override
  String get reviewImportMatches => 'Revisar coincidencias de importación';

  @override
  String get nothingToReview =>
      'Nada que revisar.\nTodas las series importadas están emparejadas.';

  @override
  String get importMatchesIntro =>
      'Los identificadores originales de estas series ya no están en TheTVDB. Encontramos coincidencias probables: confirma las correctas y descarta el resto.';

  @override
  String get youImported => 'Importaste';

  @override
  String get likelyMatch => 'coincidencia probable';

  @override
  String get notIt => 'No es';

  @override
  String get confirm => 'Confirmar';

  @override
  String matchedTo(String name) {
    return 'Emparejado con $name';
  }

  @override
  String dismissedImport(String name) {
    return 'Se descartó «$name»';
  }

  @override
  String seriesWithId(int id) {
    return 'serie $id';
  }

  @override
  String get ok => 'Aceptar';

  @override
  String get gridView => 'Vista de cuadrícula';

  @override
  String get carouselView => 'Vista de carrusel';

  @override
  String get filterLibrary => 'Filtrar biblioteca';

  @override
  String get kindMovie => 'Película';

  @override
  String watchedTimes(int count) {
    return 'Visto ×$count';
  }

  @override
  String get favorite => 'Favorito';

  @override
  String get unfavorite => 'Quitar de favoritos';

  @override
  String get movie => 'Película';

  @override
  String movieNumbered(int id) {
    return 'Película $id';
  }

  @override
  String usersFavorites(String name) {
    return 'Favoritos de $name';
  }

  @override
  String usersShows(String name) {
    return 'Series de $name';
  }

  @override
  String get yourShows => 'Tus series';

  @override
  String get yourMovies => 'Tus películas';

  @override
  String usersMovies(String name) {
    return 'Películas de $name';
  }

  @override
  String importGdprSuccess(int shows, int watches, int favorites) {
    return '$shows series · $watches visionados · $favorites favoritos importados.\nBuscando series faltantes en segundo plano — revisa «Revisar coincidencias» en breve.';
  }

  @override
  String get deleteAccountConfirmBody =>
      'Esto elimina permanentemente tu cuenta y todos tus datos — series seguidas, historial de reproducción, favoritos y seguimientos. Esta acción no se puede deshacer.';

  @override
  String get deleteAnyway => 'Eliminar de todos modos';

  @override
  String get keepMyAccount => 'Conservar mi cuenta';

  @override
  String get nameCannotBeEmpty => 'El nombre no puede estar vacío';

  @override
  String get enterValidEmail => 'Introduce un correo electrónico válido';

  @override
  String get profileUpdated => 'Perfil actualizado.';

  @override
  String showsNeedConfirming(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count series por confirmar',
      one: '$count serie por confirmar',
    );
    return '$_temp0';
  }

  @override
  String showFallback(int id) {
    return 'Programa $id';
  }

  @override
  String get filterAndSort => 'Filtrar y ordenar';

  @override
  String movieFallback(int id) {
    return 'Película $id';
  }

  @override
  String ratingStars(int rating) {
    return '★ $rating/10';
  }

  @override
  String get markWatchedAgain => 'Marcar como visto de nuevo';

  @override
  String get addToFavorites => 'Añadir a favoritos';

  @override
  String get addedToFavorites => 'Añadido a favoritos';

  @override
  String get watchLater => 'Ver más tarde';

  @override
  String get markedForLater => 'Marcado para más tarde';

  @override
  String get stoppedWatching => 'Dejaste de ver';

  @override
  String get removeFromLibrary => 'Quitar de la biblioteca';

  @override
  String get removed => 'Eliminado';

  @override
  String get seriesGeneric => 'serie';

  @override
  String get moreDetails => 'Más detalles';

  @override
  String get showDetails => 'Detalles';

  @override
  String get communityRating => 'Valoración de la comunidad';

  @override
  String get language => 'Idioma';

  @override
  String get country => 'País';

  @override
  String get aired => 'Emisión';

  @override
  String get episodeLength => 'Duración del episodio';

  @override
  String get alsoKnownAs => 'También conocido como';

  @override
  String seasonsCount(int n) {
    return '$n temporadas';
  }

  @override
  String runtimeMinutes(int n) {
    return '~$n min';
  }

  @override
  String episodesCount(int n) {
    return '$n episodios';
  }

  @override
  String bulkUpdated(int count) {
    return '$count actualizado(s)';
  }

  @override
  String get rateHate => 'Lo odio';

  @override
  String get rateDislike => 'No me gusta';

  @override
  String get rateOk => 'Regular';

  @override
  String get rateLike => 'Me gusta';

  @override
  String get rateLove => 'Me encanta';

  @override
  String get updateOpenToInstall =>
      'Descargando la actualización. Abre el archivo para instalar.';

  @override
  String get sortMyRating => 'Tu valoración';
}
