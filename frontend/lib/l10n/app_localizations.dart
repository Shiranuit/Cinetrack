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

  /// No description provided for @searchYourShows.
  ///
  /// In en, this message translates to:
  /// **'Search your shows'**
  String get searchYourShows;

  /// No description provided for @searchAllShows.
  ///
  /// In en, this message translates to:
  /// **'Search all shows & movies'**
  String get searchAllShows;

  /// No description provided for @libraryNoMatchDiscover.
  ///
  /// In en, this message translates to:
  /// **'Nothing in your library matches. Find new shows in Discover.'**
  String get libraryNoMatchDiscover;

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
  /// **'Time Spent'**
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

  /// No description provided for @rewatchSeries.
  ///
  /// In en, this message translates to:
  /// **'Rewatch series (+1)'**
  String get rewatchSeries;

  /// No description provided for @seriesActions.
  ///
  /// In en, this message translates to:
  /// **'Series actions'**
  String get seriesActions;

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

  /// No description provided for @catWatching.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get catWatching;

  /// No description provided for @catStale.
  ///
  /// In en, this message translates to:
  /// **'Haven\'t watched in a while'**
  String get catStale;

  /// No description provided for @catNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Haven\'t started'**
  String get catNotStarted;

  /// No description provided for @catUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get catUpToDate;

  /// No description provided for @catStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get catStopped;

  /// No description provided for @libSelectKinds.
  ///
  /// In en, this message translates to:
  /// **'Select Series, Anime or Movies\nto view your library.'**
  String get libSelectKinds;

  /// No description provided for @libEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.\nSearch to add shows and movies you watch.'**
  String get libEmpty;

  /// No description provided for @libNoShows.
  ///
  /// In en, this message translates to:
  /// **'No shows.'**
  String get libNoShows;

  /// No description provided for @nothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get nothingHereYet;

  /// No description provided for @filterNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No shows match these filters.'**
  String get filterNoMatch;

  /// No description provided for @noTrackedMovies.
  ///
  /// In en, this message translates to:
  /// **'No tracked movies.'**
  String get noTrackedMovies;

  /// No description provided for @langPriorityHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to set translation priority. The first available translation is used.'**
  String get langPriorityHint;

  /// No description provided for @privacyHint.
  ///
  /// In en, this message translates to:
  /// **'Only accepted followers can see your profile and activity'**
  String get privacyHint;

  /// No description provided for @setNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get setNewPassword;

  /// No description provided for @importTvTime.
  ///
  /// In en, this message translates to:
  /// **'Import TV Time data'**
  String get importTvTime;

  /// No description provided for @importGdprHint.
  ///
  /// In en, this message translates to:
  /// **'Upload your GDPR export (.zip)'**
  String get importGdprHint;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Permanently remove your account and all data'**
  String get deleteAccountHint;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @addLanguage.
  ///
  /// In en, this message translates to:
  /// **'Add a language'**
  String get addLanguage;

  /// No description provided for @primary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get primary;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change profile picture'**
  String get changePhoto;

  /// No description provided for @changeBackground.
  ///
  /// In en, this message translates to:
  /// **'Change background'**
  String get changeBackground;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @unitMonth.
  ///
  /// In en, this message translates to:
  /// **'mo'**
  String get unitMonth;

  /// No description provided for @unitDay.
  ///
  /// In en, this message translates to:
  /// **'d'**
  String get unitDay;

  /// No description provided for @unitHour.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get unitHour;

  /// No description provided for @specials.
  ///
  /// In en, this message translates to:
  /// **'Specials'**
  String get specials;

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String season(int number);

  /// No description provided for @episodesSeen.
  ///
  /// In en, this message translates to:
  /// **'episodes seen'**
  String get episodesSeen;

  /// No description provided for @rateThisShow.
  ///
  /// In en, this message translates to:
  /// **'Rate this show'**
  String get rateThisShow;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get day;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get days;

  /// No description provided for @sortPopular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get sortPopular;

  /// No description provided for @sortTopRated.
  ///
  /// In en, this message translates to:
  /// **'Top rated'**
  String get sortTopRated;

  /// No description provided for @sortReleaseDate.
  ///
  /// In en, this message translates to:
  /// **'Release date'**
  String get sortReleaseDate;

  /// No description provided for @sortLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get sortLastUpdated;

  /// No description provided for @seasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get seasons;

  /// No description provided for @episodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get episodes;

  /// No description provided for @sortLongest.
  ///
  /// In en, this message translates to:
  /// **'Longest'**
  String get sortLongest;

  /// No description provided for @genres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genres;

  /// No description provided for @themes.
  ///
  /// In en, this message translates to:
  /// **'Themes'**
  String get themes;

  /// No description provided for @networks.
  ///
  /// In en, this message translates to:
  /// **'Networks'**
  String get networks;

  /// No description provided for @studios.
  ///
  /// In en, this message translates to:
  /// **'Studios'**
  String get studios;

  /// No description provided for @releaseYear.
  ///
  /// In en, this message translates to:
  /// **'Release year'**
  String get releaseYear;

  /// No description provided for @runtimeLength.
  ///
  /// In en, this message translates to:
  /// **'Episode / runtime length'**
  String get runtimeLength;

  /// No description provided for @filterAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get filterAny;

  /// No description provided for @triStateHint.
  ///
  /// In en, this message translates to:
  /// **'tap: include → exclude → off'**
  String get triStateHint;

  /// No description provided for @statusContinuing.
  ///
  /// In en, this message translates to:
  /// **'Continuing'**
  String get statusContinuing;

  /// No description provided for @statusEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get statusEnded;

  /// No description provided for @statusUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get statusUpcoming;

  /// No description provided for @noFollowingYet.
  ///
  /// In en, this message translates to:
  /// **'You aren\'t following anyone yet.\nSearch above to find people.'**
  String get noFollowingYet;

  /// No description provided for @sortedBy.
  ///
  /// In en, this message translates to:
  /// **'Sorted by {sort}'**
  String sortedBy(String sort);

  /// No description provided for @filteredSummary.
  ///
  /// In en, this message translates to:
  /// **'Filtered · {count} active · {sort}'**
  String filteredSummary(int count, String sort);

  /// No description provided for @showFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get showFollowing;

  /// No description provided for @yourRating.
  ///
  /// In en, this message translates to:
  /// **'Your rating · {rating}/10'**
  String yourRating(int rating);

  /// No description provided for @searchIn.
  ///
  /// In en, this message translates to:
  /// **'Search {name}…'**
  String searchIn(String name);

  /// No description provided for @refineSearch.
  ///
  /// In en, this message translates to:
  /// **'Refine your search to see more…'**
  String get refineSearch;

  /// No description provided for @runtimeUnder30.
  ///
  /// In en, this message translates to:
  /// **'< 30m'**
  String get runtimeUnder30;

  /// No description provided for @runtime30to60.
  ///
  /// In en, this message translates to:
  /// **'30–60m'**
  String get runtime30to60;

  /// No description provided for @runtimeOver60.
  ///
  /// In en, this message translates to:
  /// **'> 60m'**
  String get runtimeOver60;

  /// No description provided for @sortName.
  ///
  /// In en, this message translates to:
  /// **'A–Z'**
  String get sortName;

  /// No description provided for @nSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String nSelected(int count);

  /// No description provided for @calendarEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled.\nFollow airing shows to see them here.'**
  String get calendarEmpty;

  /// No description provided for @seriesFallback.
  ///
  /// In en, this message translates to:
  /// **'Series {id}'**
  String seriesFallback(int id);

  /// No description provided for @discoverEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matches in your catalog yet.\nImport or search shows to fill it, then filter here.'**
  String get discoverEmpty;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found.'**
  String get noUsersFound;

  /// No description provided for @reviewImportMatches.
  ///
  /// In en, this message translates to:
  /// **'Review import matches'**
  String get reviewImportMatches;

  /// No description provided for @nothingToReview.
  ///
  /// In en, this message translates to:
  /// **'Nothing to review.\nAll imported shows are matched.'**
  String get nothingToReview;

  /// No description provided for @importMatchesIntro.
  ///
  /// In en, this message translates to:
  /// **'These shows\' original ids are gone from TheTVDB. We found likely matches — confirm the correct ones, dismiss the rest.'**
  String get importMatchesIntro;

  /// No description provided for @youImported.
  ///
  /// In en, this message translates to:
  /// **'You imported'**
  String get youImported;

  /// No description provided for @likelyMatch.
  ///
  /// In en, this message translates to:
  /// **'likely match'**
  String get likelyMatch;

  /// No description provided for @notIt.
  ///
  /// In en, this message translates to:
  /// **'Not it'**
  String get notIt;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @matchedTo.
  ///
  /// In en, this message translates to:
  /// **'Matched to {name}'**
  String matchedTo(String name);

  /// No description provided for @dismissedImport.
  ///
  /// In en, this message translates to:
  /// **'Dismissed \"{name}\"'**
  String dismissedImport(String name);

  /// No description provided for @seriesWithId.
  ///
  /// In en, this message translates to:
  /// **'series {id}'**
  String seriesWithId(int id);

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @carouselView.
  ///
  /// In en, this message translates to:
  /// **'Carousel view'**
  String get carouselView;

  /// No description provided for @filterLibrary.
  ///
  /// In en, this message translates to:
  /// **'Filter library'**
  String get filterLibrary;

  /// No description provided for @kindMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get kindMovie;

  /// No description provided for @watchedTimes.
  ///
  /// In en, this message translates to:
  /// **'Watched ×{count}'**
  String watchedTimes(int count);

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @unfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get unfavorite;

  /// No description provided for @movie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get movie;

  /// No description provided for @movieNumbered.
  ///
  /// In en, this message translates to:
  /// **'Movie {id}'**
  String movieNumbered(int id);

  /// No description provided for @usersFavorites.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s favorites'**
  String usersFavorites(String name);

  /// No description provided for @usersShows.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s shows'**
  String usersShows(String name);

  /// No description provided for @yourShows.
  ///
  /// In en, this message translates to:
  /// **'Your shows'**
  String get yourShows;

  /// No description provided for @yourMovies.
  ///
  /// In en, this message translates to:
  /// **'Your movies'**
  String get yourMovies;

  /// No description provided for @usersMovies.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s movies'**
  String usersMovies(String name);

  /// No description provided for @importGdprSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported {shows} shows · {watches} watches · {favorites} favorites.\nMatching missing shows in the background — check \"Review import matches\" shortly.'**
  String importGdprSuccess(int shows, int watches, int favorites);

  /// No description provided for @deleteAccountConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and all your data — tracked shows, watch history, favorites and follows. This cannot be undone.'**
  String get deleteAccountConfirmBody;

  /// No description provided for @deleteAnyway.
  ///
  /// In en, this message translates to:
  /// **'Delete anyway'**
  String get deleteAnyway;

  /// No description provided for @keepMyAccount.
  ///
  /// In en, this message translates to:
  /// **'Keep my account'**
  String get keepMyAccount;

  /// No description provided for @nameCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get nameCannotBeEmpty;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get enterValidEmail;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated.'**
  String get profileUpdated;

  /// No description provided for @showsNeedConfirming.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} show needs confirming} other{{count} shows need confirming}}'**
  String showsNeedConfirming(int count);

  /// No description provided for @showFallback.
  ///
  /// In en, this message translates to:
  /// **'Show {id}'**
  String showFallback(int id);

  /// No description provided for @filterAndSort.
  ///
  /// In en, this message translates to:
  /// **'Filter & sort'**
  String get filterAndSort;

  /// No description provided for @movieFallback.
  ///
  /// In en, this message translates to:
  /// **'Movie {id}'**
  String movieFallback(int id);

  /// No description provided for @ratingStars.
  ///
  /// In en, this message translates to:
  /// **'★ {rating}/10'**
  String ratingStars(int rating);

  /// No description provided for @markWatchedAgain.
  ///
  /// In en, this message translates to:
  /// **'Mark watched again'**
  String get markWatchedAgain;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get addedToFavorites;

  /// No description provided for @watchLater.
  ///
  /// In en, this message translates to:
  /// **'Watch later'**
  String get watchLater;

  /// No description provided for @markedForLater.
  ///
  /// In en, this message translates to:
  /// **'Marked for later'**
  String get markedForLater;

  /// No description provided for @stoppedWatching.
  ///
  /// In en, this message translates to:
  /// **'Stopped watching'**
  String get stoppedWatching;

  /// No description provided for @removeFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Remove from library'**
  String get removeFromLibrary;

  /// No description provided for @removed.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get removed;

  /// No description provided for @seriesGeneric.
  ///
  /// In en, this message translates to:
  /// **'series'**
  String get seriesGeneric;

  /// No description provided for @moreDetails.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get moreDetails;

  /// No description provided for @showDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get showDetails;

  /// No description provided for @communityRating.
  ///
  /// In en, this message translates to:
  /// **'Community rating'**
  String get communityRating;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @aired.
  ///
  /// In en, this message translates to:
  /// **'Aired'**
  String get aired;

  /// No description provided for @episodeLength.
  ///
  /// In en, this message translates to:
  /// **'Episode length'**
  String get episodeLength;

  /// No description provided for @alsoKnownAs.
  ///
  /// In en, this message translates to:
  /// **'Also known as'**
  String get alsoKnownAs;

  /// No description provided for @seasonsCount.
  ///
  /// In en, this message translates to:
  /// **'{n} seasons'**
  String seasonsCount(int n);

  /// No description provided for @runtimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'~{n} min'**
  String runtimeMinutes(int n);

  /// No description provided for @episodesCount.
  ///
  /// In en, this message translates to:
  /// **'{n} episodes'**
  String episodesCount(int n);

  /// No description provided for @bulkUpdated.
  ///
  /// In en, this message translates to:
  /// **'{count} updated'**
  String bulkUpdated(int count);

  /// No description provided for @rateHate.
  ///
  /// In en, this message translates to:
  /// **'Hate it'**
  String get rateHate;

  /// No description provided for @rateDislike.
  ///
  /// In en, this message translates to:
  /// **'Dislike it'**
  String get rateDislike;

  /// No description provided for @rateOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get rateOk;

  /// No description provided for @rateLike.
  ///
  /// In en, this message translates to:
  /// **'Like it'**
  String get rateLike;

  /// No description provided for @rateLove.
  ///
  /// In en, this message translates to:
  /// **'Love it'**
  String get rateLove;
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
