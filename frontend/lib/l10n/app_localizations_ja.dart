// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Cinetrack';

  @override
  String get navLibrary => 'ライブラリ';

  @override
  String get navDiscover => '見つける';

  @override
  String get navCalendar => 'カレンダー';

  @override
  String get navSearch => '検索';

  @override
  String get navProfile => 'プロフィール';

  @override
  String get friends => 'フレンド';

  @override
  String get searchHint => '検索…';

  @override
  String get typeSeries => 'シリーズ';

  @override
  String get typeAnime => 'アニメ';

  @override
  String get typeMovies => '映画';

  @override
  String get typeAll => 'すべて';

  @override
  String get filters => 'フィルター';

  @override
  String get loading => '読み込み中…';

  @override
  String get retry => '再試行';

  @override
  String get noResults => '結果なし';

  @override
  String get logIn => 'ログイン';

  @override
  String get signUp => '新規登録';

  @override
  String get logOut => 'ログアウト';

  @override
  String get save => '保存';

  @override
  String get cancel => 'キャンセル';

  @override
  String get follow => 'フォロー';

  @override
  String get unfollow => 'フォロー解除';

  @override
  String get requested => 'リクエスト済み';

  @override
  String get requestToFollow => 'フォローをリクエスト';

  @override
  String get followers => 'フォロワー';

  @override
  String get following => 'フォロー中';

  @override
  String get statEpisodes => 'エピソード';

  @override
  String get statWatched => '視聴済み';

  @override
  String get statMovies => '映画';

  @override
  String get favorites => 'お気に入り';

  @override
  String get shows => '番組';

  @override
  String get settings => '設定';

  @override
  String get sectionAccount => 'アカウント';

  @override
  String get sectionPrivacy => 'プライバシー';

  @override
  String get sectionAppearance => '外観';

  @override
  String get sectionLanguages => '言語';

  @override
  String get sectionData => 'データ';

  @override
  String get sectionDangerZone => '危険ゾーン';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeAuto => '自動';

  @override
  String get fieldName => '名前';

  @override
  String get fieldEmail => 'メール';

  @override
  String get changePassword => 'パスワードを変更';

  @override
  String get privateProfile => '非公開プロフィール';

  @override
  String get tagline => 'すべての番組、映画、再視聴を記録。';

  @override
  String get fieldScreenName => '表示名';

  @override
  String get fieldPassword => 'パスワード';

  @override
  String get fieldConfirmPassword => 'パスワードを確認';

  @override
  String get showPassword => 'パスワードを表示';

  @override
  String get hidePassword => 'パスワードを非表示';

  @override
  String get createAccount => 'アカウントを作成';

  @override
  String get haveAccountLogIn => 'アカウントをお持ちですか？ログイン';

  @override
  String get newHereCreate => '初めてですか？アカウントを作成';

  @override
  String get pwUppercase => '大文字';

  @override
  String get pwLowercase => '小文字';

  @override
  String get pwNumber => '数字';

  @override
  String get pwSpecial => '記号';

  @override
  String get customizeProfile => 'プロフィールをカスタマイズ';

  @override
  String get accountPrivate => 'このアカウントは非公開です';

  @override
  String followToSee(String name) {
    return '$name をフォローしてプロフィールを表示。';
  }

  @override
  String get findPeople => 'ユーザーを探す…';

  @override
  String get followRequests => 'フォローリクエスト';

  @override
  String get accept => '承認';

  @override
  String get decline => '拒否';

  @override
  String get remove => '削除';

  @override
  String get private => '非公開';

  @override
  String get status => 'ステータス';

  @override
  String get forLater => 'あとで';

  @override
  String get stopWatching => '視聴をやめる';

  @override
  String get clearStatus => 'ステータスを消去';

  @override
  String get markAllWatched => 'すべて視聴済みにする';

  @override
  String get unmarkAll => 'すべて解除';

  @override
  String get rewatchSeason => 'シーズンを再視聴 (+1)';

  @override
  String get seasonActions => 'シーズンの操作';

  @override
  String get markWatched => '視聴済みにする';

  @override
  String get markedWatched => '視聴済みにしました';

  @override
  String get removeOneWatch => '視聴を1回削除';

  @override
  String get recentlyAired => '最近放送';

  @override
  String get upcoming => '近日放送';

  @override
  String get openShow => '番組を開く';

  @override
  String get reset => 'リセット';

  @override
  String get clear => 'クリア';

  @override
  String get favoritesOnly => 'お気に入りのみ';

  @override
  String get sortBy => '並べ替え';

  @override
  String get showResults => '結果を表示';

  @override
  String get pw12chars => '12文字以上';

  @override
  String get passwordsDontMatch => 'パスワードが一致しません';

  @override
  String get filterOrigLanguage => '原語';

  @override
  String get filterOrigCountry => '制作国';

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
  String get inviteHelp =>
      'Enter an email to send the invite directly, or leave it blank to get a shareable link.';

  @override
  String get noInvitesYet =>
      'No invitations yet — create one above to invite someone.';

  @override
  String get inviteLink => 'Shareable link';

  @override
  String get expires => 'Expires';

  @override
  String get inviteUsed => 'Used';

  @override
  String get invitePending => 'Pending';

  @override
  String get revoke => 'Revoke';

  @override
  String get revokeInviteConfirm =>
      'Revoke this invitation? The link will stop working.';

  @override
  String get inviteRevoked => 'Invitation revoked';

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
