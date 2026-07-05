// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Cinetrack';

  @override
  String get navLibrary => '라이브러리';

  @override
  String get navDiscover => '둘러보기';

  @override
  String get navCalendar => '캘린더';

  @override
  String get navSearch => '검색';

  @override
  String get navProfile => '프로필';

  @override
  String get friends => '친구';

  @override
  String get searchHint => '검색…';

  @override
  String get typeSeries => '시리즈';

  @override
  String get typeAnime => '애니메이션';

  @override
  String get typeMovies => '영화';

  @override
  String get typeAll => '전체';

  @override
  String get filters => '필터';

  @override
  String get loading => '불러오는 중…';

  @override
  String get retry => '다시 시도';

  @override
  String get noResults => '결과 없음';

  @override
  String get logIn => '로그인';

  @override
  String get signUp => '회원가입';

  @override
  String get logOut => '로그아웃';

  @override
  String get save => '저장';

  @override
  String get cancel => '취소';

  @override
  String get follow => '팔로우';

  @override
  String get unfollow => '팔로우 취소';

  @override
  String get requested => '요청됨';

  @override
  String get requestToFollow => '팔로우 요청';

  @override
  String get followers => '팔로워';

  @override
  String get following => '팔로잉';

  @override
  String get statEpisodes => '에피소드';

  @override
  String get statWatched => '시청함';

  @override
  String get statMovies => '영화';

  @override
  String get favorites => '즐겨찾기';

  @override
  String get shows => '프로그램';

  @override
  String get settings => '설정';

  @override
  String get sectionAccount => '계정';

  @override
  String get sectionPrivacy => '개인정보';

  @override
  String get sectionAppearance => '화면';

  @override
  String get sectionLanguages => '언어';

  @override
  String get sectionData => '데이터';

  @override
  String get sectionDangerZone => '위험 구역';

  @override
  String get themeDark => '다크';

  @override
  String get themeLight => '라이트';

  @override
  String get themeAuto => '자동';

  @override
  String get fieldName => '이름';

  @override
  String get fieldEmail => '이메일';

  @override
  String get changePassword => '비밀번호 변경';

  @override
  String get privateProfile => '비공개 프로필';

  @override
  String get tagline => '모든 프로그램, 영화, 다시보기를 기록하세요.';

  @override
  String get fieldScreenName => '표시 이름';

  @override
  String get fieldPassword => '비밀번호';

  @override
  String get fieldConfirmPassword => '비밀번호 확인';

  @override
  String get showPassword => '비밀번호 표시';

  @override
  String get hidePassword => '비밀번호 숨기기';

  @override
  String get createAccount => '계정 만들기';

  @override
  String get haveAccountLogIn => '계정이 있으신가요? 로그인';

  @override
  String get newHereCreate => '처음이신가요? 계정 만들기';

  @override
  String get pwUppercase => '대문자';

  @override
  String get pwLowercase => '소문자';

  @override
  String get pwNumber => '숫자';

  @override
  String get pwSpecial => '특수문자';

  @override
  String get customizeProfile => '프로필 맞춤설정';

  @override
  String get accountPrivate => '이 계정은 비공개입니다';

  @override
  String followToSee(String name) {
    return '$name님을 팔로우하여 프로필 보기.';
  }

  @override
  String get findPeople => '사람 찾기…';

  @override
  String get followRequests => '팔로우 요청';

  @override
  String get accept => '수락';

  @override
  String get decline => '거절';

  @override
  String get remove => '삭제';

  @override
  String get private => '비공개';

  @override
  String get status => '상태';

  @override
  String get forLater => '나중에';

  @override
  String get stopWatching => '그만 보기';

  @override
  String get clearStatus => '상태 지우기';

  @override
  String get markAllWatched => '모두 시청함으로 표시';

  @override
  String get unmarkAll => '모두 표시 해제';

  @override
  String get rewatchSeason => '시즌 다시보기 (+1)';

  @override
  String get seasonActions => '시즌 작업';

  @override
  String get markWatched => '시청함으로 표시';

  @override
  String get markedWatched => '시청함으로 표시됨';

  @override
  String get removeOneWatch => '시청 1회 삭제';

  @override
  String get recentlyAired => '최근 방영';

  @override
  String get upcoming => '예정';

  @override
  String get openShow => '프로그램 열기';

  @override
  String get reset => '재설정';

  @override
  String get clear => '지우기';

  @override
  String get favoritesOnly => '즐겨찾기만';

  @override
  String get sortBy => '정렬 기준';

  @override
  String get showResults => '결과 보기';

  @override
  String get pw12chars => '12자 이상';

  @override
  String get passwordsDontMatch => '비밀번호가 일치하지 않습니다';

  @override
  String get filterOrigLanguage => '원어';

  @override
  String get filterOrigCountry => '제작 국가';

  @override
  String get installAndroidBanner => 'Cinetrack는 앱에서 더 잘 작동합니다.';

  @override
  String get installAndroidCta => 'Android 앱 받기';

  @override
  String get forgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get resetPassword => '비밀번호 재설정';

  @override
  String get resetLinkSent => '해당 주소로 등록된 계정이 있으면 재설정 링크를 보냈습니다.';

  @override
  String get passwordUpdated => '비밀번호가 업데이트되었습니다.';

  @override
  String get newPassword => '새 비밀번호';

  @override
  String get currentPassword => '현재 비밀번호';

  @override
  String get inviteCode => '초대 코드';

  @override
  String get invites => '초대';

  @override
  String get inviteSent => '초대를 보냈습니다.';

  @override
  String get copied => '클립보드에 복사됨';

  @override
  String get copyLink => '링크 복사';

  @override
  String get sendInviteByEmail => '이메일 (선택 사항)';

  @override
  String get createInvite => '만들기';

  @override
  String get inviteHelp => '초대를 바로 보내려면 이메일을 입력하고, 공유 링크를 받으려면 비워 두세요.';

  @override
  String get noInvitesYet => '아직 초대가 없습니다. 위에서 하나 만들어 누군가를 초대하세요.';

  @override
  String get inviteLink => '공유 링크';

  @override
  String get expires => '만료';

  @override
  String get inviteUsed => '사용됨';

  @override
  String get invitePending => '대기 중';

  @override
  String get revoke => '취소';

  @override
  String get revokeInviteConfirm => '이 초대를 취소하시겠습니까? 링크가 작동하지 않게 됩니다.';

  @override
  String get inviteRevoked => '초대가 취소됨';

  @override
  String get securityActivity => '보안 활동';

  @override
  String get noActivityYet => '아직 활동이 없습니다.';

  @override
  String get evLoginOk => '로그인함';

  @override
  String get evLoginFail => '로그인 시도 실패';

  @override
  String get evPasswordChanged => '비밀번호 변경됨';

  @override
  String get evResetRequested => '비밀번호 재설정 요청됨';

  @override
  String get evResetCompleted => '비밀번호 재설정 완료됨';

  @override
  String get evRegistered => '계정 생성됨';

  @override
  String get evInviteCreated => '초대 생성됨';

  @override
  String get evAccountDeleted => '계정 삭제됨';

  @override
  String get updateAvailable => '새 버전을 사용할 수 있습니다';

  @override
  String get update => '업데이트';

  @override
  String get updateRequired => '업데이트가 필요합니다';

  @override
  String get updateRequiredBody =>
      '이 버전은 더 이상 지원되지 않습니다. Cinetrack을 계속 사용하려면 업데이트하세요.';

  @override
  String get updateFailed => '업데이트에 실패했습니다. 다시 시도해 주세요.';

  @override
  String get catWatching => '시청 중';

  @override
  String get catStale => '한동안 보지 않음';

  @override
  String get catNotStarted => '시작 안 함';

  @override
  String get catUpToDate => '최신';

  @override
  String get catStopped => '중단됨';

  @override
  String get libSelectKinds => '시리즈, 애니메이션 또는 영화를 선택하여\n라이브러리를 확인하세요.';

  @override
  String get libEmpty => '아직 아무것도 없습니다.\n시청하는 프로그램과 영화를 검색하여 추가하세요.';

  @override
  String get libNoShows => '프로그램이 없습니다.';

  @override
  String get nothingHereYet => '아직 아무것도 없습니다.';

  @override
  String get filterNoMatch => '이 필터와 일치하는 프로그램이 없습니다.';

  @override
  String get noTrackedMovies => '추적 중인 영화가 없습니다.';

  @override
  String get langPriorityHint => '드래그하여 번역 우선순위를 설정하세요. 사용 가능한 첫 번째 번역이 사용됩니다.';

  @override
  String get privacyHint => '수락된 팔로워만 프로필과 활동을 볼 수 있습니다';

  @override
  String get setNewPassword => '새 비밀번호 설정';

  @override
  String get importTvTime => 'TV Time 데이터 가져오기';

  @override
  String get importGdprHint => 'GDPR 내보내기(.zip) 업로드';

  @override
  String get deleteAccount => '계정 삭제';

  @override
  String get deleteAccountHint => '계정과 모든 데이터를 영구적으로 삭제합니다';

  @override
  String get displayName => '표시 이름';

  @override
  String get addLanguage => '언어 추가';

  @override
  String get primary => '기본';

  @override
  String get statistics => '통계';

  @override
  String get changePhoto => '프로필 사진 변경';

  @override
  String get changeBackground => '배경 변경';

  @override
  String get seeAll => '모두 보기';

  @override
  String get unitMonth => '개월';

  @override
  String get unitDay => '일';

  @override
  String get unitHour => '시간';

  @override
  String get specials => '스페셜';

  @override
  String season(int number) {
    return '시즌 $number';
  }

  @override
  String get episodesSeen => '화 시청함';

  @override
  String get rateThisShow => '이 프로그램 평가';

  @override
  String get today => '오늘';

  @override
  String get day => '일';

  @override
  String get days => '일';

  @override
  String get sortPopular => '인기';

  @override
  String get sortTopRated => '높은 평점';

  @override
  String get sortReleaseDate => '출시일';

  @override
  String get sortLastUpdated => '최근 업데이트';

  @override
  String get seasons => '시즌';

  @override
  String get episodes => '에피소드';

  @override
  String get sortLongest => '긴 순서';

  @override
  String get genres => '장르';

  @override
  String get themes => '테마';

  @override
  String get networks => '방송사';

  @override
  String get studios => '스튜디오';

  @override
  String get releaseYear => '출시 연도';

  @override
  String get runtimeLength => '에피소드/재생 시간';

  @override
  String get filterAny => '전체';

  @override
  String get triStateHint => '탭: 포함 → 제외 → 끄기';

  @override
  String get statusContinuing => '방영 중';

  @override
  String get statusEnded => '종영';

  @override
  String get statusUpcoming => '예정';

  @override
  String get noFollowingYet => '아직 아무도 팔로우하지 않았습니다.\n위에서 검색하여 사람을 찾아보세요.';

  @override
  String sortedBy(String sort) {
    return '$sort(으)로 정렬';
  }

  @override
  String filteredSummary(int count, String sort) {
    return '필터 · $count개 · $sort';
  }

  @override
  String get showFollowing => '팔로우 중';

  @override
  String yourRating(int rating) {
    return '내 평가 · $rating/10';
  }

  @override
  String searchIn(String name) {
    return '$name 검색…';
  }

  @override
  String get refineSearch => '검색을 좁히면 더 많이 표시됩니다…';

  @override
  String get runtimeUnder30 => '30분 미만';

  @override
  String get runtime30to60 => '30~60분';

  @override
  String get runtimeOver60 => '60분 초과';

  @override
  String get sortName => '이름순';

  @override
  String nSelected(int count) {
    return '$count개 선택';
  }

  @override
  String get calendarEmpty => '예정된 항목이 없습니다.\n방영 중인 프로그램을 팔로우하면 여기에 표시됩니다.';

  @override
  String seriesFallback(int id) {
    return '시리즈 $id';
  }

  @override
  String get discoverEmpty =>
      '아직 카탈로그에 일치하는 항목이 없습니다.\n프로그램을 가져오거나 검색해 채운 다음 여기에서 필터링하세요.';

  @override
  String get noUsersFound => '사용자를 찾을 수 없습니다.';

  @override
  String get reviewImportMatches => '가져오기 일치 항목 검토';

  @override
  String get nothingToReview => '검토할 항목이 없습니다.\n가져온 모든 프로그램이 일치되었습니다.';

  @override
  String get importMatchesIntro =>
      '이 프로그램들의 원래 ID가 TheTVDB에서 사라졌습니다. 유력한 일치 항목을 찾았습니다. 올바른 것을 확인하고 나머지는 무시하세요.';

  @override
  String get youImported => '가져온 항목';

  @override
  String get likelyMatch => '유력한 일치';

  @override
  String get notIt => '아니요';

  @override
  String get confirm => '확인';

  @override
  String matchedTo(String name) {
    return '$name에 일치됨';
  }

  @override
  String dismissedImport(String name) {
    return '\"$name\" 무시함';
  }

  @override
  String seriesWithId(int id) {
    return '시리즈 $id';
  }

  @override
  String get ok => '확인';

  @override
  String get gridView => '그리드 보기';

  @override
  String get carouselView => '캐러셀 보기';

  @override
  String get filterLibrary => '라이브러리 필터';

  @override
  String get kindMovie => '영화';

  @override
  String watchedTimes(int count) {
    return '시청함 ×$count';
  }

  @override
  String get favorite => '즐겨찾기';

  @override
  String get unfavorite => '즐겨찾기 해제';

  @override
  String get movie => '영화';

  @override
  String movieNumbered(int id) {
    return '영화 $id';
  }

  @override
  String usersFavorites(String name) {
    return '$name님의 즐겨찾기';
  }

  @override
  String usersShows(String name) {
    return '$name님의 프로그램';
  }

  @override
  String get yourShows => '내 프로그램';

  @override
  String importGdprSuccess(int shows, int watches, int favorites) {
    return '$shows개 프로그램 · $watches개 시청 · $favorites개 즐겨찾기를 가져왔습니다.\n누락된 프로그램을 백그라운드에서 매칭 중입니다 — 잠시 후 \"가져오기 일치 검토\"를 확인하세요.';
  }

  @override
  String get deleteAccountConfirmBody =>
      '계정과 모든 데이터(추적 중인 프로그램, 시청 기록, 즐겨찾기 및 팔로우)가 영구적으로 삭제됩니다. 이 작업은 취소할 수 없습니다.';

  @override
  String get deleteAnyway => '그래도 삭제';

  @override
  String get keepMyAccount => '계정 유지';

  @override
  String get nameCannotBeEmpty => '이름을 비워둘 수 없습니다';

  @override
  String get enterValidEmail => '유효한 이메일을 입력하세요';

  @override
  String get profileUpdated => '프로필이 업데이트되었습니다.';

  @override
  String showsNeedConfirming(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 프로그램을 확인해야 합니다',
    );
    return '$_temp0';
  }

  @override
  String showFallback(int id) {
    return '프로그램 $id';
  }

  @override
  String get filterAndSort => '필터 및 정렬';

  @override
  String movieFallback(int id) {
    return '영화 $id';
  }

  @override
  String ratingStars(int rating) {
    return '★ $rating/10';
  }

  @override
  String get markWatchedAgain => '다시 시청함으로 표시';

  @override
  String get addToFavorites => '즐겨찾기에 추가';

  @override
  String get addedToFavorites => '즐겨찾기에 추가됨';

  @override
  String get watchLater => '나중에 보기';

  @override
  String get markedForLater => '나중에 보기로 표시됨';

  @override
  String get stoppedWatching => '시청 중지됨';

  @override
  String get removeFromLibrary => '라이브러리에서 제거';

  @override
  String get removed => '제거됨';

  @override
  String get seriesGeneric => '시리즈';
}
