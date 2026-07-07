// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Cinetrack';

  @override
  String get navLibrary => 'Biblioteca';

  @override
  String get navDiscover => 'Descobrir';

  @override
  String get navCalendar => 'Calendário';

  @override
  String get navSearch => 'Pesquisar';

  @override
  String get navProfile => 'Perfil';

  @override
  String get friends => 'Amigos';

  @override
  String get searchHint => 'Pesquisar…';

  @override
  String get searchYourShows => 'Buscar nas suas séries';

  @override
  String get searchAllShows => 'Buscar séries e filmes';

  @override
  String get libraryNoMatchDiscover =>
      'Nada na sua biblioteca. Encontre novas séries em Descobrir.';

  @override
  String get typeSeries => 'Séries';

  @override
  String get typeAnime => 'Anime';

  @override
  String get typeMovies => 'Filmes';

  @override
  String get typeAll => 'Tudo';

  @override
  String get filters => 'Filtros';

  @override
  String get loading => 'Carregando…';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get noResults => 'Sem resultados';

  @override
  String get logIn => 'Entrar';

  @override
  String get signUp => 'Cadastrar-se';

  @override
  String get logOut => 'Sair';

  @override
  String get save => 'Salvar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get follow => 'Seguir';

  @override
  String get unfollow => 'Deixar de seguir';

  @override
  String get requested => 'Solicitado';

  @override
  String get requestToFollow => 'Solicitar para seguir';

  @override
  String get followers => 'Seguidores';

  @override
  String get following => 'Seguindo';

  @override
  String get followingUser => 'Seguindo';

  @override
  String get statEpisodes => 'Episódios';

  @override
  String get statWatched => 'Tempo gasto';

  @override
  String get statMovies => 'Filmes';

  @override
  String get favorites => 'Favoritos';

  @override
  String get shows => 'Séries';

  @override
  String get settings => 'Configurações';

  @override
  String get sectionAccount => 'Conta';

  @override
  String get sectionPrivacy => 'Privacidade';

  @override
  String get sectionAppearance => 'Aparência';

  @override
  String get sectionLanguages => 'Idiomas';

  @override
  String get sectionData => 'Dados';

  @override
  String get sectionDangerZone => 'Zona de perigo';

  @override
  String get themeDark => 'Escuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeAuto => 'Automático';

  @override
  String get fieldName => 'Nome';

  @override
  String get fieldEmail => 'E-mail';

  @override
  String get changePassword => 'Alterar senha';

  @override
  String get privateProfile => 'Perfil privado';

  @override
  String get tagline => 'Acompanhe cada série, filme e reprise.';

  @override
  String get fieldScreenName => 'Nome de exibição';

  @override
  String get fieldPassword => 'Senha';

  @override
  String get fieldConfirmPassword => 'Confirmar senha';

  @override
  String get showPassword => 'Mostrar senha';

  @override
  String get hidePassword => 'Ocultar senha';

  @override
  String get createAccount => 'Criar conta';

  @override
  String get haveAccountLogIn => 'Já tem conta? Entrar';

  @override
  String get newHereCreate => 'Novo por aqui? Crie uma conta';

  @override
  String get pwUppercase => 'Maiúscula';

  @override
  String get pwLowercase => 'Minúscula';

  @override
  String get pwNumber => 'Número';

  @override
  String get pwSpecial => 'Especial';

  @override
  String get customizeProfile => 'Personalizar perfil';

  @override
  String get accountPrivate => 'Esta conta é privada';

  @override
  String followToSee(String name) {
    return 'Siga $name para ver o perfil.';
  }

  @override
  String get findPeople => 'Encontrar pessoas…';

  @override
  String get followRequests => 'Solicitações para seguir';

  @override
  String get accept => 'Aceitar';

  @override
  String get decline => 'Recusar';

  @override
  String get remove => 'Remover';

  @override
  String get private => 'Privado';

  @override
  String get status => 'Status';

  @override
  String get forLater => 'Para depois';

  @override
  String get stopWatching => 'Parar de assistir';

  @override
  String get clearStatus => 'Limpar estado';

  @override
  String get markAllWatched => 'Marcar tudo como assistido';

  @override
  String get unmarkAll => 'Desmarcar tudo';

  @override
  String get rewatchSeason => 'Rever temporada (+1)';

  @override
  String get rewatchSeries => 'Rever série (+1)';

  @override
  String get seriesActions => 'Ações da série';

  @override
  String get seasonActions => 'Ações da temporada';

  @override
  String get markWatched => 'Marcar como assistido';

  @override
  String get markedWatched => 'Marcado como assistido';

  @override
  String get removeOneWatch => 'Remover uma visualização';

  @override
  String get recentlyAired => 'Exibido recentemente';

  @override
  String get upcoming => 'Em breve';

  @override
  String get openShow => 'Abrir série';

  @override
  String get reset => 'Redefinir';

  @override
  String get clear => 'Limpar';

  @override
  String get favoritesOnly => 'Apenas favoritos';

  @override
  String get sortBy => 'Ordenar por';

  @override
  String get showResults => 'Ver resultados';

  @override
  String get pw12chars => '12+ caracteres';

  @override
  String get passwordsDontMatch => 'As senhas não coincidem';

  @override
  String get filterOrigLanguage => 'Idioma original';

  @override
  String get filterOrigCountry => 'País de origem';

  @override
  String get installAndroidBanner => 'O Cinetrack funciona melhor como app.';

  @override
  String get installAndroidCta => 'Baixar o app para Android';

  @override
  String get forgotPassword => 'Esqueceu a senha?';

  @override
  String get resetPassword => 'Redefinir senha';

  @override
  String get resetLinkSent =>
      'Se existir uma conta para esse endereço, um link de redefinição foi enviado.';

  @override
  String get passwordUpdated => 'Senha atualizada.';

  @override
  String get newPassword => 'Nova senha';

  @override
  String get currentPassword => 'Senha atual';

  @override
  String get inviteCode => 'Código de convite';

  @override
  String get invites => 'Convites';

  @override
  String get inviteSent => 'Convite enviado.';

  @override
  String get copied => 'Copiado para a área de transferência';

  @override
  String get copyLink => 'Copiar link';

  @override
  String get sendInviteByEmail => 'E-mail (opcional)';

  @override
  String get createInvite => 'Criar';

  @override
  String get inviteHelp =>
      'Digite um e-mail para enviar o convite diretamente, ou deixe em branco para obter um link compartilhável.';

  @override
  String get noInvitesYet =>
      'Ainda não há convites — crie um acima para convidar alguém.';

  @override
  String get inviteLink => 'Link compartilhável';

  @override
  String get expires => 'Expira';

  @override
  String get inviteUsed => 'Usado';

  @override
  String get invitePending => 'Pendente';

  @override
  String get revoke => 'Revogar';

  @override
  String get revokeInviteConfirm =>
      'Revogar este convite? O link deixará de funcionar.';

  @override
  String get inviteRevoked => 'Convite revogado';

  @override
  String get securityActivity => 'Atividade de segurança';

  @override
  String get noActivityYet => 'Ainda não há atividade.';

  @override
  String get evLoginOk => 'Sessão iniciada';

  @override
  String get evLoginFail => 'Tentativa de login malsucedida';

  @override
  String get evPasswordChanged => 'Senha alterada';

  @override
  String get evResetRequested => 'Redefinição de senha solicitada';

  @override
  String get evResetCompleted => 'Redefinição de senha concluída';

  @override
  String get evRegistered => 'Conta criada';

  @override
  String get evInviteCreated => 'Convite criado';

  @override
  String get evAccountDeleted => 'Conta excluída';

  @override
  String get updateAvailable => 'Uma nova versão está disponível';

  @override
  String get update => 'Atualizar';

  @override
  String get updateRequired => 'Atualização necessária';

  @override
  String get updateRequiredBody =>
      'Esta versão não é mais suportada. Atualize para continuar usando o Cinetrack.';

  @override
  String get updateFailed => 'Falha na atualização. Tente novamente.';

  @override
  String get catWatching => 'Assistindo';

  @override
  String get catStale => 'Sem assistir há um tempo';

  @override
  String get catNotStarted => 'Não começados';

  @override
  String get catUpToDate => 'Em dia';

  @override
  String get catStopped => 'Parados';

  @override
  String get libSelectKinds =>
      'Selecione Séries, Anime ou Filmes\npara ver sua biblioteca.';

  @override
  String get libEmpty =>
      'Nada aqui ainda.\nPesquise para adicionar séries e filmes que você assiste.';

  @override
  String get libNoShows => 'Nenhuma série.';

  @override
  String get nothingHereYet => 'Nada aqui ainda.';

  @override
  String get filterNoMatch => 'Nenhuma série corresponde a estes filtros.';

  @override
  String get noTrackedMovies => 'Nenhum filme acompanhado.';

  @override
  String get langPriorityHint =>
      'Arraste para definir a prioridade de tradução. A primeira tradução disponível é usada.';

  @override
  String get privacyHint =>
      'Apenas seguidores aceitos podem ver seu perfil e atividade';

  @override
  String get setNewPassword => 'Definir uma nova senha';

  @override
  String get importTvTime => 'Importar dados do TV Time';

  @override
  String get importGdprHint => 'Envie sua exportação GDPR (.zip)';

  @override
  String get deleteAccount => 'Excluir conta';

  @override
  String get deleteAccountHint =>
      'Remover permanentemente sua conta e todos os dados';

  @override
  String get displayName => 'Nome de exibição';

  @override
  String get addLanguage => 'Adicionar um idioma';

  @override
  String get primary => 'Principal';

  @override
  String get statistics => 'Estatísticas';

  @override
  String get changePhoto => 'Alterar foto do perfil';

  @override
  String get changeBackground => 'Alterar plano de fundo';

  @override
  String get seeAll => 'Ver tudo';

  @override
  String get unitMonth => 'mês';

  @override
  String get unitDay => 'd';

  @override
  String get unitHour => 'h';

  @override
  String get specials => 'Especiais';

  @override
  String season(int number) {
    return 'Temporada $number';
  }

  @override
  String get episodesSeen => 'episódios vistos';

  @override
  String get rateThisShow => 'Avaliar esta série';

  @override
  String get today => 'Hoje';

  @override
  String get day => 'dia';

  @override
  String get days => 'dias';

  @override
  String get sortPopular => 'Popular';

  @override
  String get sortTopRated => 'Mais bem avaliados';

  @override
  String get sortReleaseDate => 'Data de lançamento';

  @override
  String get sortLastUpdated => 'Última atualização';

  @override
  String get seasons => 'Temporadas';

  @override
  String get episodes => 'Episódios';

  @override
  String get sortLongest => 'Mais longos';

  @override
  String get genres => 'Gêneros';

  @override
  String get themes => 'Temas';

  @override
  String get networks => 'Emissoras';

  @override
  String get studios => 'Estúdios';

  @override
  String get releaseYear => 'Ano de lançamento';

  @override
  String get runtimeLength => 'Duração do episódio / filme';

  @override
  String get filterAny => 'Todos';

  @override
  String get triStateHint => 'toque: incluir → excluir → desligado';

  @override
  String get statusContinuing => 'Em exibição';

  @override
  String get statusEnded => 'Encerrada';

  @override
  String get statusUpcoming => 'Em breve';

  @override
  String get noFollowingYet =>
      'Você ainda não segue ninguém.\nPesquise acima para encontrar pessoas.';

  @override
  String sortedBy(String sort) {
    return 'Ordenado por $sort';
  }

  @override
  String filteredSummary(int count, String sort) {
    return 'Filtrado · $count ativos · $sort';
  }

  @override
  String get showFollowing => 'Seguindo';

  @override
  String yourRating(int rating) {
    return 'Sua avaliação · $rating/10';
  }

  @override
  String searchIn(String name) {
    return 'Buscar $name…';
  }

  @override
  String get refineSearch => 'Refine sua busca para ver mais…';

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
    return '$count selecionado(s)';
  }

  @override
  String get calendarEmpty =>
      'Nada agendado.\nSiga séries em exibição para vê-las aqui.';

  @override
  String seriesFallback(int id) {
    return 'Série $id';
  }

  @override
  String get discoverEmpty =>
      'Ainda não há correspondências no seu catálogo.\nImporte ou pesquise séries para preenchê-lo e depois filtre aqui.';

  @override
  String get noUsersFound => 'Nenhum usuário encontrado.';

  @override
  String get reviewImportMatches => 'Rever correspondências de importação';

  @override
  String get nothingToReview =>
      'Nada para rever.\nTodas as séries importadas estão correspondidas.';

  @override
  String get importMatchesIntro =>
      'Os IDs originais destas séries desapareceram do TheTVDB. Encontrámos correspondências prováveis — confirma as corretas e dispensa as restantes.';

  @override
  String get youImported => 'Importaste';

  @override
  String get likelyMatch => 'correspondência provável';

  @override
  String get notIt => 'Não é';

  @override
  String get confirm => 'Confirmar';

  @override
  String matchedTo(String name) {
    return 'Correspondido a $name';
  }

  @override
  String dismissedImport(String name) {
    return '\"$name\" dispensado';
  }

  @override
  String seriesWithId(int id) {
    return 'série $id';
  }

  @override
  String get ok => 'OK';

  @override
  String get gridView => 'Visualização em grade';

  @override
  String get carouselView => 'Visualização em carrossel';

  @override
  String get filterLibrary => 'Filtrar biblioteca';

  @override
  String get kindMovie => 'Filme';

  @override
  String watchedTimes(int count) {
    return 'Assistido ×$count';
  }

  @override
  String get favorite => 'Favorito';

  @override
  String get unfavorite => 'Remover dos favoritos';

  @override
  String get movie => 'Filme';

  @override
  String movieNumbered(int id) {
    return 'Filme $id';
  }

  @override
  String usersFavorites(String name) {
    return 'Favoritos de $name';
  }

  @override
  String usersShows(String name) {
    return 'Séries de $name';
  }

  @override
  String get yourShows => 'Suas séries';

  @override
  String get yourMovies => 'Seus filmes';

  @override
  String usersMovies(String name) {
    return 'Filmes de $name';
  }

  @override
  String importGdprSuccess(int shows, int watches, int favorites) {
    return '$shows séries · $watches visualizações · $favorites favoritos importados.\nBuscando séries ausentes em segundo plano — confira \"Revisar correspondências\" em breve.';
  }

  @override
  String get deleteAccountConfirmBody =>
      'Isto exclui permanentemente sua conta e todos os seus dados — séries acompanhadas, histórico de exibição, favoritos e seguidos. Esta ação não pode ser desfeita.';

  @override
  String get deleteAnyway => 'Excluir mesmo assim';

  @override
  String get keepMyAccount => 'Manter minha conta';

  @override
  String get nameCannotBeEmpty => 'O nome não pode estar vazio';

  @override
  String get enterValidEmail => 'Insira um e-mail válido';

  @override
  String get profileUpdated => 'Perfil atualizado.';

  @override
  String showsNeedConfirming(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count séries a confirmar',
      one: '$count série a confirmar',
    );
    return '$_temp0';
  }

  @override
  String showFallback(int id) {
    return 'Programa $id';
  }

  @override
  String get filterAndSort => 'Filtrar e ordenar';

  @override
  String movieFallback(int id) {
    return 'Filme $id';
  }

  @override
  String ratingStars(int rating) {
    return '★ $rating/10';
  }

  @override
  String get markWatchedAgain => 'Marcar como visto novamente';

  @override
  String get addToFavorites => 'Adicionar aos favoritos';

  @override
  String get addedToFavorites => 'Adicionado aos favoritos';

  @override
  String get watchLater => 'Assistir mais tarde';

  @override
  String get markedForLater => 'Marcado para mais tarde';

  @override
  String get stoppedWatching => 'Parou de assistir';

  @override
  String get removeFromLibrary => 'Remover da biblioteca';

  @override
  String get removed => 'Removido';

  @override
  String get seriesGeneric => 'série';

  @override
  String get moreDetails => 'Mais detalhes';

  @override
  String get showDetails => 'Detalhes';

  @override
  String get communityRating => 'Avaliação da comunidade';

  @override
  String get language => 'Idioma';

  @override
  String get country => 'País';

  @override
  String get aired => 'Exibição';

  @override
  String get episodeLength => 'Duração do episódio';

  @override
  String get alsoKnownAs => 'Também conhecido como';

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
    return '$n episódios';
  }

  @override
  String bulkUpdated(int count) {
    return '$count atualizado(s)';
  }

  @override
  String get rateHate => 'Detestei';

  @override
  String get rateDislike => 'Não gostei';

  @override
  String get rateOk => 'Ok';

  @override
  String get rateLike => 'Gostei';

  @override
  String get rateLove => 'Adorei';

  @override
  String get updateOpenToInstall =>
      'Baixando a atualização. Abra o arquivo para instalar.';

  @override
  String get sortMyRating => 'Sua avaliação';

  @override
  String get sortAscending => 'Crescente';

  @override
  String get sortDescending => 'Decrescente';

  @override
  String get inMyLibrary => 'Na minha biblioteca';
}
