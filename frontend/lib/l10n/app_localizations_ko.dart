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
}
