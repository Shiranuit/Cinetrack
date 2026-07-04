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
  String get installAndroidBanner => 'Cinetrack runs better as an app.';

  @override
  String get installAndroidCta => 'Get the Android app';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get resetLinkSent =>
      'If an account exists for that address, a reset link has been sent.';

  @override
  String get passwordUpdated => 'Password updated.';

  @override
  String get newPassword => 'New password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get inviteCode => 'Invite code';

  @override
  String get invites => 'Invitations';

  @override
  String get inviteSent => 'Invitation sent.';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String get copyLink => 'Copy link';

  @override
  String get sendInviteByEmail => 'Email (optional)';

  @override
  String get createInvite => 'Create';

  @override
  String get noInvitesYet => 'No invitations yet.';

  @override
  String get inviteLink => 'Shareable link';

  @override
  String get expires => 'Expires';

  @override
  String get inviteUsed => 'Used';

  @override
  String get invitePending => 'Pending';

  @override
  String get securityActivity => 'Security activity';

  @override
  String get noActivityYet => 'No activity yet.';

  @override
  String get evLoginOk => 'Signed in';

  @override
  String get evLoginFail => 'Failed sign-in attempt';

  @override
  String get evPasswordChanged => 'Password changed';

  @override
  String get evResetRequested => 'Password reset requested';

  @override
  String get evResetCompleted => 'Password reset completed';

  @override
  String get evRegistered => 'Account created';

  @override
  String get evInviteCreated => 'Invitation created';

  @override
  String get evAccountDeleted => 'Account deleted';
}
