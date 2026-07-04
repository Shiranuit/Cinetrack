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
  String get installAndroidBanner => 'Cinetrack はアプリの方が快適に動作します。';

  @override
  String get installAndroidCta => 'Android アプリを入手';

  @override
  String get forgotPassword => 'パスワードをお忘れですか？';

  @override
  String get resetPassword => 'パスワードをリセット';

  @override
  String get resetLinkSent => 'そのアドレスのアカウントが存在する場合、リセットリンクを送信しました。';

  @override
  String get passwordUpdated => 'パスワードを更新しました。';

  @override
  String get newPassword => '新しいパスワード';

  @override
  String get currentPassword => '現在のパスワード';

  @override
  String get inviteCode => '招待コード';

  @override
  String get invites => '招待';

  @override
  String get inviteSent => '招待を送信しました。';

  @override
  String get copied => 'クリップボードにコピーしました';

  @override
  String get copyLink => 'リンクをコピー';

  @override
  String get sendInviteByEmail => 'メール（任意）';

  @override
  String get createInvite => '作成';

  @override
  String get inviteHelp => '招待を直接送るにはメールアドレスを入力し、共有リンクを取得するには空欄のままにします。';

  @override
  String get noInvitesYet => '招待はまだありません。上で作成して誰かを招待しましょう。';

  @override
  String get inviteLink => '共有リンク';

  @override
  String get expires => '有効期限';

  @override
  String get inviteUsed => '使用済み';

  @override
  String get invitePending => '保留中';

  @override
  String get revoke => '取り消し';

  @override
  String get revokeInviteConfirm => 'この招待を取り消しますか？リンクは無効になります。';

  @override
  String get inviteRevoked => '招待を取り消しました';

  @override
  String get securityActivity => 'セキュリティアクティビティ';

  @override
  String get noActivityYet => 'アクティビティはまだありません。';

  @override
  String get evLoginOk => 'サインインしました';

  @override
  String get evLoginFail => 'サインインの試行に失敗しました';

  @override
  String get evPasswordChanged => 'パスワードを変更しました';

  @override
  String get evResetRequested => 'パスワードのリセットを要求しました';

  @override
  String get evResetCompleted => 'パスワードのリセットが完了しました';

  @override
  String get evRegistered => 'アカウントを作成しました';

  @override
  String get evInviteCreated => '招待を作成しました';

  @override
  String get evAccountDeleted => 'アカウントを削除しました';

  @override
  String get updateAvailable => '新しいバージョンが利用可能です';

  @override
  String get update => '更新';

  @override
  String get updateRequired => 'アップデートが必要です';

  @override
  String get updateRequiredBody =>
      'このバージョンはサポートされていません。Cinetrack を使い続けるには更新してください。';

  @override
  String get updateFailed => 'アップデートに失敗しました。もう一度お試しください。';

  @override
  String get catWatching => '視聴中';

  @override
  String get catStale => 'しばらく視聴していません';

  @override
  String get catNotStarted => '未開始';

  @override
  String get catUpToDate => '最新まで視聴済み';

  @override
  String get catStopped => '視聴停止';

  @override
  String get libSelectKinds => 'シリーズ、アニメ、映画のいずれかを選択して\nライブラリを表示します。';

  @override
  String get libEmpty => 'まだ何もありません。\n視聴する番組や映画を検索して追加しましょう。';

  @override
  String get libNoShows => '番組がありません。';

  @override
  String get nothingHereYet => 'まだ何もありません。';

  @override
  String get filterNoMatch => 'これらのフィルターに一致する番組はありません。';

  @override
  String get noTrackedMovies => '追跡中の映画はありません。';
}
