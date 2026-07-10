// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Cinetrack';

  @override
  String get navLibrary => '媒体库';

  @override
  String get navDiscover => '发现';

  @override
  String get navCalendar => '日历';

  @override
  String get navSearch => '搜索';

  @override
  String get navProfile => '个人资料';

  @override
  String get friends => '好友';

  @override
  String get searchHint => '搜索…';

  @override
  String get searchYourShows => '搜索你的作品';

  @override
  String get searchAllShows => '搜索所有剧集和电影';

  @override
  String get libraryNoMatchDiscover => '库中没有匹配项。在“发现”中查找新作品。';

  @override
  String get typeSeries => '剧集';

  @override
  String get typeAnime => '动漫';

  @override
  String get typeMovies => '电影';

  @override
  String get typeAll => '全部';

  @override
  String get filters => '筛选';

  @override
  String get inLibrary => 'In library';

  @override
  String get loading => '加载中…';

  @override
  String get retry => '重试';

  @override
  String get noResults => '无结果';

  @override
  String get logIn => '登录';

  @override
  String get signUp => '注册';

  @override
  String get logOut => '退出登录';

  @override
  String get save => '保存';

  @override
  String get download => '下载';

  @override
  String get cancel => '取消';

  @override
  String get follow => '关注';

  @override
  String get unfollow => '取消关注';

  @override
  String get requested => '已请求';

  @override
  String get requestToFollow => '请求关注';

  @override
  String get followers => '粉丝';

  @override
  String get following => '关注中';

  @override
  String get followingUser => '已关注';

  @override
  String get statEpisodes => '集数';

  @override
  String get statWatched => '观看时长';

  @override
  String get statMovies => '电影';

  @override
  String get favorites => '收藏';

  @override
  String get shows => '剧集';

  @override
  String get settings => '设置';

  @override
  String get sectionAccount => '账户';

  @override
  String get sectionPrivacy => '隐私';

  @override
  String get sectionAppearance => '外观';

  @override
  String get sectionLanguages => '语言';

  @override
  String get sectionData => '数据';

  @override
  String get sectionDangerZone => '危险区域';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';

  @override
  String get themeAuto => '自动';

  @override
  String get fieldName => '名称';

  @override
  String get fieldEmail => '邮箱';

  @override
  String get changePassword => '修改密码';

  @override
  String get privateProfile => '私密资料';

  @override
  String get tagline => '记录每一部剧集、电影和重温。';

  @override
  String get fieldScreenName => '昵称';

  @override
  String get fieldPassword => '密码';

  @override
  String get fieldConfirmPassword => '确认密码';

  @override
  String get showPassword => '显示密码';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get createAccount => '创建账户';

  @override
  String get haveAccountLogIn => '已有账户？登录';

  @override
  String get newHereCreate => '新用户？创建账户';

  @override
  String get pwUppercase => '大写字母';

  @override
  String get pwLowercase => '小写字母';

  @override
  String get pwNumber => '数字';

  @override
  String get pwSpecial => '特殊字符';

  @override
  String get customizeProfile => '自定义资料';

  @override
  String get accountPrivate => '此账户为私密';

  @override
  String followToSee(String name) {
    return '关注 $name 以查看其资料。';
  }

  @override
  String get findPeople => '查找用户…';

  @override
  String get followRequests => '关注请求';

  @override
  String get accept => '接受';

  @override
  String get decline => '拒绝';

  @override
  String get remove => '移除';

  @override
  String get private => '私密';

  @override
  String get status => '状态';

  @override
  String get forLater => '稍后观看';

  @override
  String get stopWatching => '停止观看';

  @override
  String get clearStatus => '清除状态';

  @override
  String get markAllWatched => '全部标记为已看';

  @override
  String get unmarkAll => '全部取消标记';

  @override
  String get rewatchSeason => '重温本季 (+1)';

  @override
  String get rewatchSeries => '重看剧集 (+1)';

  @override
  String get removeOneWatch => '移除一次观看';

  @override
  String get seriesActions => '剧集操作';

  @override
  String get seasonActions => '本季操作';

  @override
  String get markWatched => '标记为已看';

  @override
  String get markedWatched => '已标记为已看';

  @override
  String get recentlyAired => '最近播出';

  @override
  String get showOlder => '显示更早';

  @override
  String get upcoming => '即将播出';

  @override
  String get openShow => '打开剧集';

  @override
  String get reset => '重置';

  @override
  String get clear => '清除';

  @override
  String get favoritesOnly => '仅收藏';

  @override
  String get sortBy => '排序方式';

  @override
  String get showResults => '显示结果';

  @override
  String get pw12chars => '12个以上字符';

  @override
  String get passwordsDontMatch => '密码不一致';

  @override
  String get filterOrigLanguage => '原始语言';

  @override
  String get filterOrigCountry => '出品国家';

  @override
  String get installAndroidBanner => 'Cinetrack 作为应用运行更流畅。';

  @override
  String get installAndroidCta => '获取 Android 应用';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get resetPassword => '重置密码';

  @override
  String get resetLinkSent => '如果该地址存在账户，我们已发送重置链接。';

  @override
  String get passwordUpdated => '密码已更新。';

  @override
  String get newPassword => '新密码';

  @override
  String get currentPassword => '当前密码';

  @override
  String get inviteCode => '邀请码';

  @override
  String get invites => '邀请';

  @override
  String get inviteSent => '邀请已发送。';

  @override
  String get copied => '已复制到剪贴板';

  @override
  String get copyLink => '复制链接';

  @override
  String get sendInviteByEmail => '电子邮件（可选）';

  @override
  String get createInvite => '创建';

  @override
  String get inviteHelp => '输入电子邮件以直接发送邀请，或留空以获取可分享的链接。';

  @override
  String get noInvitesYet => '还没有邀请——在上方创建一个来邀请他人。';

  @override
  String get inviteLink => '可分享链接';

  @override
  String get expires => '到期';

  @override
  String get inviteUsed => '已使用';

  @override
  String get invitePending => '待处理';

  @override
  String get revoke => '撤销';

  @override
  String get revokeInviteConfirm => '撤销此邀请？该链接将失效。';

  @override
  String get inviteRevoked => '邀请已撤销';

  @override
  String get securityActivity => '安全活动';

  @override
  String get noActivityYet => '暂无活动。';

  @override
  String get evLoginOk => '已登录';

  @override
  String get evLoginFail => '登录尝试失败';

  @override
  String get evPasswordChanged => '密码已更改';

  @override
  String get evResetRequested => '已请求重置密码';

  @override
  String get evResetCompleted => '密码重置已完成';

  @override
  String get evRegistered => '账户已创建';

  @override
  String get evInviteCreated => '邀请已创建';

  @override
  String get evAccountDeleted => '账户已删除';

  @override
  String get updateAvailable => '有新版本可用';

  @override
  String get update => '更新';

  @override
  String get updateRequired => '需要更新';

  @override
  String get updateRequiredBody => '此版本已不再受支持。请更新以继续使用 Cinetrack。';

  @override
  String get updateFailed => '更新失败。请重试。';

  @override
  String get catWatching => '观看中';

  @override
  String get catStale => '有段时间没看了';

  @override
  String get catNotStarted => '未开始';

  @override
  String get catUpToDate => '已看完最新';

  @override
  String get catStopped => '已停止';

  @override
  String get libSelectKinds => '选择剧集、动画或电影\n以查看你的库。';

  @override
  String get libEmpty => '这里还没有内容。\n搜索以添加你观看的剧集和电影。';

  @override
  String get libNoShows => '没有剧集。';

  @override
  String get nothingHereYet => '这里还没有内容。';

  @override
  String get filterNoMatch => '没有符合这些筛选条件的剧集。';

  @override
  String get noTrackedMovies => '没有追踪的电影。';

  @override
  String get langPriorityHint => '拖动以设置翻译优先级。将使用第一个可用的翻译。';

  @override
  String get privacyHint => '只有已接受的关注者才能查看你的个人资料和动态';

  @override
  String get setNewPassword => '设置新密码';

  @override
  String get importTvTime => '导入 TV Time 数据';

  @override
  String get importGdprHint => '上传你的 GDPR 导出文件（.zip）';

  @override
  String get deleteAccount => '删除账户';

  @override
  String get deleteAccountHint => '永久删除你的账户和所有数据';

  @override
  String get displayName => '显示名称';

  @override
  String get addLanguage => '添加语言';

  @override
  String get primary => '主要';

  @override
  String get statistics => '统计';

  @override
  String get changePhoto => '更换头像';

  @override
  String get changeBackground => '更换背景';

  @override
  String get seeAll => '查看全部';

  @override
  String get unitMonth => '个月';

  @override
  String get unitDay => '天';

  @override
  String get unitHour => '小时';

  @override
  String get specials => '特别篇';

  @override
  String season(int number) {
    return '第 $number 季';
  }

  @override
  String get episodesSeen => '集已观看';

  @override
  String get rateThisShow => '评价此剧';

  @override
  String get today => '今天';

  @override
  String get day => '天';

  @override
  String get days => '天';

  @override
  String get sortPopular => '热门';

  @override
  String get sortTopRated => '高评分';

  @override
  String get sortReleaseDate => '发布日期';

  @override
  String get sortLastUpdated => '最近更新';

  @override
  String get seasons => '季数';

  @override
  String get episodes => '集数';

  @override
  String get sortLongest => '最长';

  @override
  String get genres => '类型';

  @override
  String get themes => '主题';

  @override
  String get networks => '电视网';

  @override
  String get studios => '工作室';

  @override
  String get releaseYear => '发行年份';

  @override
  String get runtimeLength => '单集/片长';

  @override
  String get filterAny => '全部';

  @override
  String get triStateHint => '点击：包含 → 排除 → 关闭';

  @override
  String get statusContinuing => '连载中';

  @override
  String get statusEnded => '已完结';

  @override
  String get statusUpcoming => '即将播出';

  @override
  String get noFollowingYet => '你还没有关注任何人。\n在上方搜索以查找用户。';

  @override
  String sortedBy(String sort) {
    return '按$sort排序';
  }

  @override
  String filteredSummary(int count, String sort) {
    return '已筛选 · $count 项 · $sort';
  }

  @override
  String get showFollowing => '已关注';

  @override
  String yourRating(int rating) {
    return '你的评分 · $rating/10';
  }

  @override
  String searchIn(String name) {
    return '搜索$name…';
  }

  @override
  String get refineSearch => '细化搜索以查看更多…';

  @override
  String get runtimeUnder30 => '30 分钟以下';

  @override
  String get runtime30to60 => '30–60 分钟';

  @override
  String get runtimeOver60 => '60 分钟以上';

  @override
  String get sortName => '名称';

  @override
  String nSelected(int count) {
    return '已选择$count个';
  }

  @override
  String get calendarEmpty => '暂无排期。\n关注正在播出的剧集即可在此查看。';

  @override
  String seriesFallback(int id) {
    return '剧集 $id';
  }

  @override
  String get discoverEmpty => '您的目录中还没有匹配项。\n导入或搜索节目来填充它，然后在此处筛选。';

  @override
  String get noUsersFound => '未找到用户。';

  @override
  String get reviewImportMatches => '查看导入匹配';

  @override
  String get nothingToReview => '没有需要查看的内容。\n所有导入的节目均已匹配。';

  @override
  String get importMatchesIntro =>
      '这些节目的原始 ID 已从 TheTVDB 中消失。我们找到了可能的匹配项——确认正确的，其余的忽略。';

  @override
  String get youImported => '你导入了';

  @override
  String get likelyMatch => '可能匹配';

  @override
  String get notIt => '不是';

  @override
  String get confirm => '确认';

  @override
  String matchedTo(String name) {
    return '已匹配到 $name';
  }

  @override
  String dismissedImport(String name) {
    return '已忽略\"$name\"';
  }

  @override
  String seriesWithId(int id) {
    return '剧集 $id';
  }

  @override
  String get ok => '确定';

  @override
  String get gridView => '网格视图';

  @override
  String get carouselView => '轮播视图';

  @override
  String get filterLibrary => '筛选媒体库';

  @override
  String get kindMovie => '电影';

  @override
  String watchedTimes(int count) {
    return '已观看 ×$count';
  }

  @override
  String get favorite => '收藏';

  @override
  String get unfavorite => '取消收藏';

  @override
  String get movie => '电影';

  @override
  String movieNumbered(int id) {
    return '电影 $id';
  }

  @override
  String usersFavorites(String name) {
    return '$name的收藏';
  }

  @override
  String usersShows(String name) {
    return '$name的剧集';
  }

  @override
  String get yourShows => '你的剧集';

  @override
  String get yourMovies => '我的电影';

  @override
  String usersMovies(String name) {
    return '$name 的电影';
  }

  @override
  String importGdprSuccess(int shows, int watches, int favorites) {
    return '已导入 $shows 部剧集 · $watches 次观看 · $favorites 个收藏。\n正在后台匹配缺失的剧集 — 请稍后查看“查看导入匹配”。';
  }

  @override
  String get deleteAccountConfirmBody =>
      '这将永久删除您的账户及所有数据 — 追踪的剧集、观看记录、收藏和关注。此操作无法撤销。';

  @override
  String get deleteAnyway => '仍然删除';

  @override
  String get keepMyAccount => '保留我的账户';

  @override
  String get deleteConfirmKeyword => '删除';

  @override
  String deleteConfirmPrompt(String word) {
    return '输入 $word 以确认';
  }

  @override
  String get nameCannotBeEmpty => '名称不能为空';

  @override
  String get enterValidEmail => '请输入有效的电子邮箱';

  @override
  String get profileUpdated => '个人资料已更新。';

  @override
  String showsNeedConfirming(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 部剧集需要确认',
    );
    return '$_temp0';
  }

  @override
  String showFallback(int id) {
    return '节目 $id';
  }

  @override
  String get filterAndSort => '筛选和排序';

  @override
  String movieFallback(int id) {
    return '电影 $id';
  }

  @override
  String ratingStars(int rating) {
    return '★ $rating/10';
  }

  @override
  String get markWatchedAgain => '再次标记为已观看';

  @override
  String get addToFavorites => '添加到收藏';

  @override
  String get addedToFavorites => '已添加到收藏';

  @override
  String get watchLater => '稍后观看';

  @override
  String get markedForLater => '已标记为稍后观看';

  @override
  String get stoppedWatching => '已停止观看';

  @override
  String get removeFromLibrary => '从库中移除';

  @override
  String get removed => '已移除';

  @override
  String get seriesGeneric => '剧集';

  @override
  String get moreDetails => '更多详情';

  @override
  String get showDetails => '详情';

  @override
  String get communityRating => '社区评分';

  @override
  String get language => '语言';

  @override
  String get country => '国家/地区';

  @override
  String get aired => '播出';

  @override
  String get episodeLength => '单集时长';

  @override
  String get alsoKnownAs => '又名';

  @override
  String seasonsCount(int n) {
    return '$n 季';
  }

  @override
  String runtimeMinutes(int n) {
    return '约$n分钟';
  }

  @override
  String episodesCount(int n) {
    return '$n 集';
  }

  @override
  String bulkUpdated(int count) {
    return '已更新$count个';
  }

  @override
  String get rateHate => '讨厌';

  @override
  String get rateDislike => '不喜欢';

  @override
  String get rateOk => '一般';

  @override
  String get rateLike => '喜欢';

  @override
  String get rateLove => '超爱';

  @override
  String get updateOpenToInstall => '正在下载更新。打开文件进行安装。';

  @override
  String get sortMyRating => '你的评分';

  @override
  String get sortOwnerRating => '该用户的评分';

  @override
  String get sortAscending => '升序';

  @override
  String get sortDescending => '降序';

  @override
  String get inMyLibrary => '在我的库中';
}
