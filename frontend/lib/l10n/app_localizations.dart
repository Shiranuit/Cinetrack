import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Cinetrack'**
  String get appTitle;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get navDiscover;

  /// No description provided for @navCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get navCalendar;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friends;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get searchHint;

  /// No description provided for @typeSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get typeSeries;

  /// No description provided for @typeAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get typeAnime;

  /// No description provided for @typeMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get typeMovies;

  /// No description provided for @typeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get typeAll;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get logIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUp;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @unfollow.
  ///
  /// In en, this message translates to:
  /// **'Unfollow'**
  String get unfollow;

  /// No description provided for @requested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get requested;

  /// No description provided for @requestToFollow.
  ///
  /// In en, this message translates to:
  /// **'Request to follow'**
  String get requestToFollow;

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followers;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @statEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get statEpisodes;

  /// No description provided for @statWatched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get statWatched;

  /// No description provided for @statMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get statMovies;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @shows.
  ///
  /// In en, this message translates to:
  /// **'Shows'**
  String get shows;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @sectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get sectionAccount;

  /// No description provided for @sectionPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get sectionPrivacy;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get sectionAppearance;

  /// No description provided for @sectionLanguages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get sectionLanguages;

  /// No description provided for @sectionData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get sectionData;

  /// No description provided for @sectionDangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get sectionDangerZone;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get themeAuto;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @privateProfile.
  ///
  /// In en, this message translates to:
  /// **'Private profile'**
  String get privateProfile;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Track every show, film and rewatch.'**
  String get tagline;

  /// No description provided for @fieldScreenName.
  ///
  /// In en, this message translates to:
  /// **'Screen name'**
  String get fieldScreenName;

  /// No description provided for @fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// No description provided for @fieldConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get fieldConfirmPassword;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @haveAccountLogIn.
  ///
  /// In en, this message translates to:
  /// **'Have an account? Log in'**
  String get haveAccountLogIn;

  /// No description provided for @newHereCreate.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get newHereCreate;

  /// No description provided for @pwUppercase.
  ///
  /// In en, this message translates to:
  /// **'Uppercase'**
  String get pwUppercase;

  /// No description provided for @pwLowercase.
  ///
  /// In en, this message translates to:
  /// **'Lowercase'**
  String get pwLowercase;

  /// No description provided for @pwNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get pwNumber;

  /// No description provided for @pwSpecial.
  ///
  /// In en, this message translates to:
  /// **'Special'**
  String get pwSpecial;

  /// No description provided for @customizeProfile.
  ///
  /// In en, this message translates to:
  /// **'Customize profile'**
  String get customizeProfile;

  /// No description provided for @accountPrivate.
  ///
  /// In en, this message translates to:
  /// **'This account is private'**
  String get accountPrivate;

  /// No description provided for @followToSee.
  ///
  /// In en, this message translates to:
  /// **'Follow {name} to see their profile.'**
  String followToSee(String name);

  /// No description provided for @findPeople.
  ///
  /// In en, this message translates to:
  /// **'Find people…'**
  String get findPeople;

  /// No description provided for @followRequests.
  ///
  /// In en, this message translates to:
  /// **'Follow requests'**
  String get followRequests;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @private.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get private;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @forLater.
  ///
  /// In en, this message translates to:
  /// **'For later'**
  String get forLater;

  /// No description provided for @stopWatching.
  ///
  /// In en, this message translates to:
  /// **'Stop watching'**
  String get stopWatching;

  /// No description provided for @clearStatus.
  ///
  /// In en, this message translates to:
  /// **'Clear status'**
  String get clearStatus;

  /// No description provided for @markAllWatched.
  ///
  /// In en, this message translates to:
  /// **'Mark all watched'**
  String get markAllWatched;

  /// No description provided for @unmarkAll.
  ///
  /// In en, this message translates to:
  /// **'Unmark all'**
  String get unmarkAll;

  /// No description provided for @rewatchSeason.
  ///
  /// In en, this message translates to:
  /// **'Rewatch season (+1)'**
  String get rewatchSeason;

  /// No description provided for @seasonActions.
  ///
  /// In en, this message translates to:
  /// **'Season actions'**
  String get seasonActions;

  /// No description provided for @markWatched.
  ///
  /// In en, this message translates to:
  /// **'Mark watched'**
  String get markWatched;

  /// No description provided for @markedWatched.
  ///
  /// In en, this message translates to:
  /// **'Marked watched'**
  String get markedWatched;

  /// No description provided for @removeOneWatch.
  ///
  /// In en, this message translates to:
  /// **'Remove one watch'**
  String get removeOneWatch;

  /// No description provided for @recentlyAired.
  ///
  /// In en, this message translates to:
  /// **'Recently aired'**
  String get recentlyAired;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @openShow.
  ///
  /// In en, this message translates to:
  /// **'Open show'**
  String get openShow;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @favoritesOnly.
  ///
  /// In en, this message translates to:
  /// **'Favorites only'**
  String get favoritesOnly;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @showResults.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get showResults;

  /// No description provided for @pw12chars.
  ///
  /// In en, this message translates to:
  /// **'12+ characters'**
  String get pw12chars;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get passwordsDontMatch;

  /// No description provided for @filterOrigLanguage.
  ///
  /// In en, this message translates to:
  /// **'Original language'**
  String get filterOrigLanguage;

  /// No description provided for @filterOrigCountry.
  ///
  /// In en, this message translates to:
  /// **'Origin country'**
  String get filterOrigCountry;

  /// No description provided for @installAndroidBanner.
  ///
  /// In en, this message translates to:
  /// **'Cinetrack runs better as an app.'**
  String get installAndroidBanner;

  /// No description provided for @installAndroidCta.
  ///
  /// In en, this message translates to:
  /// **'Get the Android app'**
  String get installAndroidCta;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetPassword;

  /// No description provided for @resetLinkSent.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for that address, a reset link has been sent.'**
  String get resetLinkSent;

  /// No description provided for @passwordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated.'**
  String get passwordUpdated;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @inviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCode;

  /// No description provided for @invites.
  ///
  /// In en, this message translates to:
  /// **'Invitations'**
  String get invites;

  /// No description provided for @inviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent.'**
  String get inviteSent;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @sendInviteByEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get sendInviteByEmail;

  /// No description provided for @createInvite.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createInvite;

  /// No description provided for @inviteHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter an email to send the invite directly, or leave it blank to get a shareable link.'**
  String get inviteHelp;

  /// No description provided for @noInvitesYet.
  ///
  /// In en, this message translates to:
  /// **'No invitations yet — create one above to invite someone.'**
  String get noInvitesYet;

  /// No description provided for @inviteLink.
  ///
  /// In en, this message translates to:
  /// **'Shareable link'**
  String get inviteLink;

  /// No description provided for @expires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get expires;

  /// No description provided for @inviteUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get inviteUsed;

  /// No description provided for @invitePending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get invitePending;

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @revokeInviteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Revoke this invitation? The link will stop working.'**
  String get revokeInviteConfirm;

  /// No description provided for @inviteRevoked.
  ///
  /// In en, this message translates to:
  /// **'Invitation revoked'**
  String get inviteRevoked;

  /// No description provided for @securityActivity.
  ///
  /// In en, this message translates to:
  /// **'Security activity'**
  String get securityActivity;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet.'**
  String get noActivityYet;

  /// No description provided for @evLoginOk.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get evLoginOk;

  /// No description provided for @evLoginFail.
  ///
  /// In en, this message translates to:
  /// **'Failed sign-in attempt'**
  String get evLoginFail;

  /// No description provided for @evPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get evPasswordChanged;

  /// No description provided for @evResetRequested.
  ///
  /// In en, this message translates to:
  /// **'Password reset requested'**
  String get evResetRequested;

  /// No description provided for @evResetCompleted.
  ///
  /// In en, this message translates to:
  /// **'Password reset completed'**
  String get evResetCompleted;

  /// No description provided for @evRegistered.
  ///
  /// In en, this message translates to:
  /// **'Account created'**
  String get evRegistered;

  /// No description provided for @evInviteCreated.
  ///
  /// In en, this message translates to:
  /// **'Invitation created'**
  String get evInviteCreated;

  /// No description provided for @evAccountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get evAccountDeleted;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'A new version is available'**
  String get updateAvailable;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @updateRequired.
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get updateRequired;

  /// No description provided for @updateRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'This version is no longer supported. Please update to keep using Cinetrack.'**
  String get updateRequiredBody;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed. Please try again.'**
  String get updateFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'pt',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pt':
      return AppLocalizationsPt();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
