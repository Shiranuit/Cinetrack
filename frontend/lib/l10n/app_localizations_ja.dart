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

  @override
  String get langPriorityHint => 'ドラッグして翻訳の優先順位を設定します。最初に利用可能な翻訳が使用されます。';

  @override
  String get privacyHint => '承認されたフォロワーのみがあなたのプロフィールとアクティビティを閲覧できます';

  @override
  String get setNewPassword => '新しいパスワードを設定';

  @override
  String get importTvTime => 'TV Time のデータをインポート';

  @override
  String get importGdprHint => 'GDPR エクスポート（.zip）をアップロード';

  @override
  String get deleteAccount => 'アカウントを削除';

  @override
  String get deleteAccountHint => 'アカウントとすべてのデータを完全に削除します';

  @override
  String get displayName => '表示名';

  @override
  String get addLanguage => '言語を追加';

  @override
  String get primary => '優先';

  @override
  String get statistics => '統計';

  @override
  String get changePhoto => 'プロフィール写真を変更';

  @override
  String get changeBackground => '背景を変更';

  @override
  String get seeAll => 'すべて表示';

  @override
  String get unitMonth => 'か月';

  @override
  String get unitDay => '日';

  @override
  String get unitHour => '時間';

  @override
  String get specials => '特別編';

  @override
  String season(int number) {
    return 'シーズン$number';
  }

  @override
  String get episodesSeen => '話視聴済み';

  @override
  String get rateThisShow => 'この番組を評価';

  @override
  String get today => '今日';

  @override
  String get day => '日';

  @override
  String get days => '日';

  @override
  String get sortPopular => '人気';

  @override
  String get sortTopRated => '高評価';

  @override
  String get sortReleaseDate => '公開日';

  @override
  String get sortLastUpdated => '最終更新';

  @override
  String get seasons => 'シーズン数';

  @override
  String get episodes => 'エピソード';

  @override
  String get sortLongest => '長い順';

  @override
  String get genres => 'ジャンル';

  @override
  String get themes => 'テーマ';

  @override
  String get networks => '放送局';

  @override
  String get studios => 'スタジオ';

  @override
  String get releaseYear => '公開年';

  @override
  String get runtimeLength => 'エピソード／再生時間';

  @override
  String get filterAny => 'すべて';

  @override
  String get triStateHint => 'タップ：含める → 除外 → オフ';

  @override
  String get statusContinuing => '放送中';

  @override
  String get statusEnded => '終了';

  @override
  String get statusUpcoming => '近日公開';

  @override
  String get noFollowingYet => 'まだ誰もフォローしていません。\n上で検索して人を見つけましょう。';

  @override
  String sortedBy(String sort) {
    return '$sortで並べ替え';
  }

  @override
  String filteredSummary(int count, String sort) {
    return 'フィルター · $count件 · $sort';
  }

  @override
  String get showFollowing => 'フォロー中';

  @override
  String yourRating(int rating) {
    return 'あなたの評価 · $rating/10';
  }

  @override
  String searchIn(String name) {
    return '$nameを検索…';
  }

  @override
  String get refineSearch => '検索を絞り込むと、さらに表示されます…';

  @override
  String get runtimeUnder30 => '30分未満';

  @override
  String get runtime30to60 => '30〜60分';

  @override
  String get runtimeOver60 => '60分以上';

  @override
  String get sortName => '名前順';

  @override
  String nSelected(int count) {
    return '$count件選択';
  }

  @override
  String get calendarEmpty => '予定はありません。\n放送中の番組をフォローするとここに表示されます。';

  @override
  String seriesFallback(int id) {
    return 'シリーズ $id';
  }

  @override
  String get discoverEmpty =>
      'カタログにまだ一致するものがありません。\nインポートまたは検索して番組を追加してから、ここで絞り込んでください。';

  @override
  String get noUsersFound => 'ユーザーが見つかりません。';

  @override
  String get reviewImportMatches => 'インポートの一致を確認';

  @override
  String get nothingToReview => '確認する項目はありません。\nインポートしたすべての番組が一致しています。';

  @override
  String get importMatchesIntro =>
      'これらの番組の元のIDはTheTVDBから消えています。可能性の高い一致を見つけました。正しいものを確認し、残りは破棄してください。';

  @override
  String get youImported => 'インポートしたもの';

  @override
  String get likelyMatch => '可能性の高い一致';

  @override
  String get notIt => '違う';

  @override
  String get confirm => '確認';

  @override
  String matchedTo(String name) {
    return '$name に一致';
  }

  @override
  String dismissedImport(String name) {
    return '「$name」を破棄しました';
  }

  @override
  String seriesWithId(int id) {
    return 'シリーズ $id';
  }

  @override
  String get ok => 'OK';

  @override
  String get gridView => 'グリッド表示';

  @override
  String get carouselView => 'カルーセル表示';

  @override
  String get filterLibrary => 'ライブラリを絞り込む';

  @override
  String get kindMovie => '映画';

  @override
  String watchedTimes(int count) {
    return '視聴済み ×$count';
  }

  @override
  String get favorite => 'お気に入り';

  @override
  String get unfavorite => 'お気に入りから削除';

  @override
  String get movie => '映画';

  @override
  String movieNumbered(int id) {
    return '映画 $id';
  }

  @override
  String usersFavorites(String name) {
    return '$nameのお気に入り';
  }

  @override
  String usersShows(String name) {
    return '$nameの番組';
  }

  @override
  String get yourShows => 'あなたの番組';

  @override
  String importGdprSuccess(int shows, int watches, int favorites) {
    return '$shows件の番組・$watches件の視聴・$favorites件のお気に入りをインポートしました。\n不足している番組をバックグラウンドで照合中です。まもなく「インポートの一致を確認」をご確認ください。';
  }

  @override
  String get deleteAccountConfirmBody =>
      'これによりアカウントとすべてのデータ（追跡中の番組、視聴履歴、お気に入り、フォロー）が完全に削除されます。この操作は取り消せません。';

  @override
  String get deleteAnyway => 'それでも削除';

  @override
  String get keepMyAccount => 'アカウントを保持';

  @override
  String get nameCannotBeEmpty => '名前を入力してください';

  @override
  String get enterValidEmail => '有効なメールアドレスを入力してください';

  @override
  String get profileUpdated => 'プロフィールを更新しました。';

  @override
  String showsNeedConfirming(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の番組を確認する必要があります',
    );
    return '$_temp0';
  }

  @override
  String showFallback(int id) {
    return '番組 $id';
  }

  @override
  String get filterAndSort => 'フィルターと並べ替え';

  @override
  String movieFallback(int id) {
    return '映画 $id';
  }

  @override
  String ratingStars(int rating) {
    return '★ $rating/10';
  }

  @override
  String get markWatchedAgain => '再び視聴済みにする';

  @override
  String get addToFavorites => 'お気に入りに追加';

  @override
  String get addedToFavorites => 'お気に入りに追加しました';

  @override
  String get watchLater => '後で見る';

  @override
  String get markedForLater => '後で見るに設定しました';

  @override
  String get stoppedWatching => '視聴を停止しました';

  @override
  String get removeFromLibrary => 'ライブラリから削除';

  @override
  String get removed => '削除しました';

  @override
  String get seriesGeneric => 'シリーズ';
}
