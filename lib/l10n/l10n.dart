// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'intl/messages_all.dart';

// **************************************************************************
// Generator: Flutter Intl IDE plugin
// Made by Localizely
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars
// ignore_for_file: join_return_with_assignment, prefer_final_in_for_each
// ignore_for_file: avoid_redundant_argument_values, avoid_escaping_inner_quotes

class AppLocalizations {
  AppLocalizations();

  static AppLocalizations? _current;

  static AppLocalizations get current {
    assert(
      _current != null,
      'No instance of AppLocalizations was loaded. Try to initialize the AppLocalizations delegate before accessing AppLocalizations.current.',
    );
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<AppLocalizations> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = AppLocalizations();
      AppLocalizations._current = instance;

      return instance;
    });
  }

  static AppLocalizations of(BuildContext context) {
    final instance = AppLocalizations.maybeOf(context);
    assert(
      instance != null,
      'No instance of AppLocalizations present in the widget tree. Did you add AppLocalizations.delegate in localizationsDelegates?',
    );
    return instance!;
  }

  static AppLocalizations? maybeOf(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  /// `Rule`
  String get rule {
    return Intl.message('Rule', name: 'rule', desc: '', args: []);
  }

  /// `Global`
  String get global {
    return Intl.message('Global', name: 'global', desc: '', args: []);
  }

  /// `Direct`
  String get direct {
    return Intl.message('Direct', name: 'direct', desc: '', args: []);
  }

  /// `Dashboard`
  String get dashboard {
    return Intl.message('Dashboard', name: 'dashboard', desc: '', args: []);
  }

  /// `Proxies`
  String get proxies {
    return Intl.message('Proxies', name: 'proxies', desc: '', args: []);
  }

  /// `Profile`
  String get profile {
    return Intl.message('Profile', name: 'profile', desc: '', args: []);
  }

  /// `Profiles`
  String get profiles {
    return Intl.message('Profiles', name: 'profiles', desc: '', args: []);
  }

  /// `Tools`
  String get tools {
    return Intl.message('Tools', name: 'tools', desc: '', args: []);
  }

  /// `Logs`
  String get logs {
    return Intl.message('Logs', name: 'logs', desc: '', args: []);
  }

  /// `Log capture records`
  String get logsDesc {
    return Intl.message(
      'Log capture records',
      name: 'logsDesc',
      desc: '',
      args: [],
    );
  }

  /// `Resources`
  String get resources {
    return Intl.message('Resources', name: 'resources', desc: '', args: []);
  }

  /// `External resource related info`
  String get resourcesDesc {
    return Intl.message(
      'External resource related info',
      name: 'resourcesDesc',
      desc: '',
      args: [],
    );
  }

  /// `Traffic usage`
  String get trafficUsage {
    return Intl.message(
      'Traffic usage',
      name: 'trafficUsage',
      desc: '',
      args: [],
    );
  }

  /// `Network speed`
  String get networkSpeed {
    return Intl.message(
      'Network speed',
      name: 'networkSpeed',
      desc: '',
      args: [],
    );
  }

  /// `Outbound mode`
  String get outboundMode {
    return Intl.message(
      'Outbound mode',
      name: 'outboundMode',
      desc: '',
      args: [],
    );
  }

  /// `Network detection`
  String get networkDetection {
    return Intl.message(
      'Network detection',
      name: 'networkDetection',
      desc: '',
      args: [],
    );
  }

  /// `Upload`
  String get upload {
    return Intl.message('Upload', name: 'upload', desc: '', args: []);
  }

  /// `Download`
  String get download {
    return Intl.message('Download', name: 'download', desc: '', args: []);
  }

  /// `No profile, Please add a profile`
  String get nullProfileDesc {
    return Intl.message(
      'No profile, Please add a profile',
      name: 'nullProfileDesc',
      desc: '',
      args: [],
    );
  }

  /// `Settings`
  String get settings {
    return Intl.message('Settings', name: 'settings', desc: '', args: []);
  }

  /// `Language`
  String get language {
    return Intl.message('Language', name: 'language', desc: '', args: []);
  }

  /// `Default`
  String get defaultText {
    return Intl.message('Default', name: 'defaultText', desc: '', args: []);
  }

  /// `Log in`
  String get login {
    return Intl.message('Log in', name: 'login', desc: '', args: []);
  }

  /// `Logging in…`
  String get loggingIn {
    return Intl.message('Logging in…', name: 'loggingIn', desc: '', args: []);
  }

  /// `Login failed. Please try again later`
  String get loginFailed {
    return Intl.message(
      'Login failed. Please try again later',
      name: 'loginFailed',
      desc: '',
      args: [],
    );
  }

  /// `Welcome back, please log in to your account`
  String get loginWelcome {
    return Intl.message(
      'Welcome back, please log in to your account',
      name: 'loginWelcome',
      desc: '',
      args: [],
    );
  }

  /// `Email`
  String get email {
    return Intl.message('Email', name: 'email', desc: '', args: []);
  }

  /// `Enter your email`
  String get enterEmail {
    return Intl.message(
      'Enter your email',
      name: 'enterEmail',
      desc: '',
      args: [],
    );
  }

  /// `Enter a valid email address`
  String get invalidEmail {
    return Intl.message(
      'Enter a valid email address',
      name: 'invalidEmail',
      desc: '',
      args: [],
    );
  }

  /// `Enter your password`
  String get enterPassword {
    return Intl.message(
      'Enter your password',
      name: 'enterPassword',
      desc: '',
      args: [],
    );
  }

  /// `Confirm password`
  String get confirmPassword {
    return Intl.message(
      'Confirm password',
      name: 'confirmPassword',
      desc: '',
      args: [],
    );
  }

  /// `Enter your password again`
  String get enterConfirmPassword {
    return Intl.message(
      'Enter your password again',
      name: 'enterConfirmPassword',
      desc: '',
      args: [],
    );
  }

  /// `Password must be at least 8 characters`
  String get passwordTooShort {
    return Intl.message(
      'Password must be at least 8 characters',
      name: 'passwordTooShort',
      desc: '',
      args: [],
    );
  }

  /// `The passwords do not match`
  String get passwordsDoNotMatch {
    return Intl.message(
      'The passwords do not match',
      name: 'passwordsDoNotMatch',
      desc: '',
      args: [],
    );
  }

  /// `Remember me`
  String get rememberMe {
    return Intl.message('Remember me', name: 'rememberMe', desc: '', args: []);
  }

  /// `Log in automatically`
  String get automaticLogin {
    return Intl.message(
      'Log in automatically',
      name: 'automaticLogin',
      desc: '',
      args: [],
    );
  }

  /// `Checking login status...`
  String get checkingLoginStatus {
    return Intl.message(
      'Checking login status...',
      name: 'checkingLoginStatus',
      desc: '',
      args: [],
    );
  }

  /// `Your login session has expired. Please log in again`
  String get loginSessionExpired {
    return Intl.message(
      'Your login session has expired. Please log in again',
      name: 'loginSessionExpired',
      desc: '',
      args: [],
    );
  }

  /// `Automatic login is temporarily unavailable. Log in manually or try again later`
  String get automaticLoginUnavailable {
    return Intl.message(
      'Automatic login is temporarily unavailable. Log in manually or try again later',
      name: 'automaticLoginUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `Failed to load subscription nodes. Check your network and try again`
  String get subscriptionImportFailed {
    return Intl.message(
      'Failed to load subscription nodes. Check your network and try again',
      name: 'subscriptionImportFailed',
      desc: '',
      args: [],
    );
  }

  /// `Create account`
  String get registerAccount {
    return Intl.message(
      'Create account',
      name: 'registerAccount',
      desc: '',
      args: [],
    );
  }

  /// `Create account`
  String get createAccountTitle {
    return Intl.message(
      'Create account',
      name: 'createAccountTitle',
      desc: '',
      args: [],
    );
  }

  /// `Register`
  String get registerAction {
    return Intl.message('Register', name: 'registerAction', desc: '', args: []);
  }

  /// `Join us and start managing your network`
  String get createAccountSubtitle {
    return Intl.message(
      'Join us and start managing your network',
      name: 'createAccountSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Invitation code (optional)`
  String get invitationCodeOptional {
    return Intl.message(
      'Invitation code (optional)',
      name: 'invitationCodeOptional',
      desc: '',
      args: [],
    );
  }

  /// `Invitation code`
  String get invitationCode {
    return Intl.message(
      'Invitation code',
      name: 'invitationCode',
      desc: '',
      args: [],
    );
  }

  /// `Enter your invitation code`
  String get invitationCodeRequired {
    return Intl.message(
      'Enter your invitation code',
      name: 'invitationCodeRequired',
      desc: '',
      args: [],
    );
  }

  /// `Enter an invitation code (if any)`
  String get enterInvitationCode {
    return Intl.message(
      'Enter an invitation code (if any)',
      name: 'enterInvitationCode',
      desc: '',
      args: [],
    );
  }

  /// `Email verification code`
  String get emailVerificationCode {
    return Intl.message(
      'Email verification code',
      name: 'emailVerificationCode',
      desc: '',
      args: [],
    );
  }

  /// `Enter the verification code`
  String get enterVerificationCode {
    return Intl.message(
      'Enter the verification code',
      name: 'enterVerificationCode',
      desc: '',
      args: [],
    );
  }

  /// `Send`
  String get sendVerificationCode {
    return Intl.message(
      'Send',
      name: 'sendVerificationCode',
      desc: '',
      args: [],
    );
  }

  /// `Sending...`
  String get sendingVerificationCode {
    return Intl.message(
      'Sending...',
      name: 'sendingVerificationCode',
      desc: '',
      args: [],
    );
  }

  /// `Already have an account?`
  String get alreadyHaveAccount {
    return Intl.message(
      'Already have an account?',
      name: 'alreadyHaveAccount',
      desc: '',
      args: [],
    );
  }

  /// `Back to login`
  String get backToLogin {
    return Intl.message(
      'Back to login',
      name: 'backToLogin',
      desc: '',
      args: [],
    );
  }

  /// `Registration API is not connected yet`
  String get registrationApiPending {
    return Intl.message(
      'Registration API is not connected yet',
      name: 'registrationApiPending',
      desc: '',
      args: [],
    );
  }

  /// `Registration successful`
  String get registrationSuccess {
    return Intl.message(
      'Registration successful',
      name: 'registrationSuccess',
      desc: '',
      args: [],
    );
  }

  /// `Registration failed. Please try again later`
  String get registrationFailed {
    return Intl.message(
      'Registration failed. Please try again later',
      name: 'registrationFailed',
      desc: '',
      args: [],
    );
  }

  /// `Verification API is not connected yet`
  String get verificationApiPending {
    return Intl.message(
      'Verification API is not connected yet',
      name: 'verificationApiPending',
      desc: '',
      args: [],
    );
  }

  /// `Verification code sent. Check your spam folder if it does not arrive`
  String get verificationEmailSent {
    return Intl.message(
      'Verification code sent. Check your spam folder if it does not arrive',
      name: 'verificationEmailSent',
      desc: '',
      args: [],
    );
  }

  /// `Enter a valid email account`
  String get invalidEmailAccount {
    return Intl.message(
      'Enter a valid email account',
      name: 'invalidEmailAccount',
      desc: '',
      args: [],
    );
  }

  /// `Forgot password`
  String get forgotPassword {
    return Intl.message(
      'Forgot password',
      name: 'forgotPassword',
      desc: '',
      args: [],
    );
  }

  /// `Recover password`
  String get forgotPasswordTitle {
    return Intl.message(
      'Recover password',
      name: 'forgotPasswordTitle',
      desc: '',
      args: [],
    );
  }

  /// `Reset your password and restore account access`
  String get forgotPasswordSubtitle {
    return Intl.message(
      'Reset your password and restore account access',
      name: 'forgotPasswordSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Enter your email address`
  String get enterEmailAddress {
    return Intl.message(
      'Enter your email address',
      name: 'enterEmailAddress',
      desc: '',
      args: [],
    );
  }

  /// `New password`
  String get newPassword {
    return Intl.message(
      'New password',
      name: 'newPassword',
      desc: '',
      args: [],
    );
  }

  /// `Enter a new password`
  String get enterNewPassword {
    return Intl.message(
      'Enter a new password',
      name: 'enterNewPassword',
      desc: '',
      args: [],
    );
  }

  /// `Reset password`
  String get resetPasswordAction {
    return Intl.message(
      'Reset password',
      name: 'resetPasswordAction',
      desc: '',
      args: [],
    );
  }

  /// `Resetting…`
  String get resettingPassword {
    return Intl.message(
      'Resetting…',
      name: 'resettingPassword',
      desc: '',
      args: [],
    );
  }

  /// `Remembered your password?`
  String get rememberedPassword {
    return Intl.message(
      'Remembered your password?',
      name: 'rememberedPassword',
      desc: '',
      args: [],
    );
  }

  /// `Password reset successfully. Log in with your new password`
  String get passwordResetSuccess {
    return Intl.message(
      'Password reset successfully. Log in with your new password',
      name: 'passwordResetSuccess',
      desc: '',
      args: [],
    );
  }

  /// `Password reset failed. Please try again later`
  String get passwordResetFailed {
    return Intl.message(
      'Password reset failed. Please try again later',
      name: 'passwordResetFailed',
      desc: '',
      args: [],
    );
  }

  /// `Support`
  String get onlineSupport {
    return Intl.message('Support', name: 'onlineSupport', desc: '', args: []);
  }

  /// `Show password`
  String get showPassword {
    return Intl.message(
      'Show password',
      name: 'showPassword',
      desc: '',
      args: [],
    );
  }

  /// `Hide password`
  String get hidePassword {
    return Intl.message(
      'Hide password',
      name: 'hidePassword',
      desc: '',
      args: [],
    );
  }

  /// `This feature will be available after the server is connected`
  String get featureComingSoon {
    return Intl.message(
      'This feature will be available after the server is connected',
      name: 'featureComingSoon',
      desc: '',
      args: [],
    );
  }

  /// `API status`
  String get apiStatus {
    return Intl.message('API status', name: 'apiStatus', desc: '', args: []);
  }

  /// `Checking API connectivity...`
  String get checkingApiStatus {
    return Intl.message(
      'Checking API connectivity...',
      name: 'checkingApiStatus',
      desc: '',
      args: [],
    );
  }

  /// `Refresh API status`
  String get refreshApiStatus {
    return Intl.message(
      'Refresh API status',
      name: 'refreshApiStatus',
      desc: '',
      args: [],
    );
  }

  /// `API status is unavailable`
  String get apiStatusUnavailable {
    return Intl.message(
      'API status is unavailable',
      name: 'apiStatusUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `{reachable}/{total} API endpoints available`
  String apiEndpointsAvailable(Object reachable, Object total) {
    return Intl.message(
      '$reachable/$total API endpoints available',
      name: 'apiEndpointsAvailable',
      desc: '',
      args: [reachable, total],
    );
  }

  /// `API endpoint {index}`
  String apiEndpointLabel(Object index) {
    return Intl.message(
      'API endpoint $index',
      name: 'apiEndpointLabel',
      desc: '',
      args: [index],
    );
  }

  /// `Reachable`
  String get reachable {
    return Intl.message('Reachable', name: 'reachable', desc: '', args: []);
  }

  /// `Unreachable`
  String get unreachable {
    return Intl.message('Unreachable', name: 'unreachable', desc: '', args: []);
  }

  /// `More`
  String get more {
    return Intl.message('More', name: 'more', desc: '', args: []);
  }

  /// `Other`
  String get other {
    return Intl.message('Other', name: 'other', desc: '', args: []);
  }

  /// `About`
  String get about {
    return Intl.message('About', name: 'about', desc: '', args: []);
  }

  /// `English`
  String get en {
    return Intl.message('English', name: 'en', desc: '', args: []);
  }

  /// `Japanese`
  String get ja {
    return Intl.message('Japanese', name: 'ja', desc: '', args: []);
  }

  /// `Russian`
  String get ru {
    return Intl.message('Russian', name: 'ru', desc: '', args: []);
  }

  /// `Simplified Chinese`
  String get zh_CN {
    return Intl.message(
      'Simplified Chinese',
      name: 'zh_CN',
      desc: '',
      args: [],
    );
  }

  /// `Theme`
  String get theme {
    return Intl.message('Theme', name: 'theme', desc: '', args: []);
  }

  /// `Set dark mode,adjust the color`
  String get themeDesc {
    return Intl.message(
      'Set dark mode,adjust the color',
      name: 'themeDesc',
      desc: '',
      args: [],
    );
  }

  /// `Override`
  String get override {
    return Intl.message('Override', name: 'override', desc: '', args: []);
  }

  /// `AllowLan`
  String get allowLan {
    return Intl.message('AllowLan', name: 'allowLan', desc: '', args: []);
  }

  /// `Allow access proxy through the LAN`
  String get allowLanDesc {
    return Intl.message(
      'Allow access proxy through the LAN',
      name: 'allowLanDesc',
      desc: '',
      args: [],
    );
  }

  /// `TUN`
  String get tun {
    return Intl.message('TUN', name: 'tun', desc: '', args: []);
  }

  /// `only effective in administrator mode`
  String get tunDesc {
    return Intl.message(
      'only effective in administrator mode',
      name: 'tunDesc',
      desc: '',
      args: [],
    );
  }

  /// `Minimize on exit`
  String get minimizeOnExit {
    return Intl.message(
      'Minimize on exit',
      name: 'minimizeOnExit',
      desc: '',
      args: [],
    );
  }

  /// `Modify the default system exit event`
  String get minimizeOnExitDesc {
    return Intl.message(
      'Modify the default system exit event',
      name: 'minimizeOnExitDesc',
      desc: '',
      args: [],
    );
  }

  /// `Auto launch`
  String get autoLaunch {
    return Intl.message('Auto launch', name: 'autoLaunch', desc: '', args: []);
  }

  /// `Follow the system self startup`
  String get autoLaunchDesc {
    return Intl.message(
      'Follow the system self startup',
      name: 'autoLaunchDesc',
      desc: '',
      args: [],
    );
  }

  /// `SilentLaunch`
  String get silentLaunch {
    return Intl.message(
      'SilentLaunch',
      name: 'silentLaunch',
      desc: '',
      args: [],
    );
  }

  /// `Start in the background`
  String get silentLaunchDesc {
    return Intl.message(
      'Start in the background',
      name: 'silentLaunchDesc',
      desc: '',
      args: [],
    );
  }

  /// `AutoRun`
  String get autoRun {
    return Intl.message('AutoRun', name: 'autoRun', desc: '', args: []);
  }

  /// `Auto run when the application is opened`
  String get autoRunDesc {
    return Intl.message(
      'Auto run when the application is opened',
      name: 'autoRunDesc',
      desc: '',
      args: [],
    );
  }

  /// `Logcat`
  String get logcat {
    return Intl.message('Logcat', name: 'logcat', desc: '', args: []);
  }

  /// `Disabling will hide the log entry`
  String get logcatDesc {
    return Intl.message(
      'Disabling will hide the log entry',
      name: 'logcatDesc',
      desc: '',
      args: [],
    );
  }

  /// `Auto check updates`
  String get autoCheckUpdate {
    return Intl.message(
      'Auto check updates',
      name: 'autoCheckUpdate',
      desc: '',
      args: [],
    );
  }

  /// `Auto check for updates when the app starts`
  String get autoCheckUpdateDesc {
    return Intl.message(
      'Auto check for updates when the app starts',
      name: 'autoCheckUpdateDesc',
      desc: '',
      args: [],
    );
  }

  /// `AccessControl`
  String get accessControl {
    return Intl.message(
      'AccessControl',
      name: 'accessControl',
      desc: '',
      args: [],
    );
  }

  /// `Configure application access proxy`
  String get accessControlDesc {
    return Intl.message(
      'Configure application access proxy',
      name: 'accessControlDesc',
      desc: '',
      args: [],
    );
  }

  /// `Application`
  String get application {
    return Intl.message('Application', name: 'application', desc: '', args: []);
  }

  /// `Modify application related settings`
  String get applicationDesc {
    return Intl.message(
      'Modify application related settings',
      name: 'applicationDesc',
      desc: '',
      args: [],
    );
  }

  /// `Edit`
  String get edit {
    return Intl.message('Edit', name: 'edit', desc: '', args: []);
  }

  /// `Confirm`
  String get confirm {
    return Intl.message('Confirm', name: 'confirm', desc: '', args: []);
  }

  /// `Update`
  String get update {
    return Intl.message('Update', name: 'update', desc: '', args: []);
  }

  /// `Add`
  String get add {
    return Intl.message('Add', name: 'add', desc: '', args: []);
  }

  /// `Save`
  String get save {
    return Intl.message('Save', name: 'save', desc: '', args: []);
  }

  /// `Delete`
  String get delete {
    return Intl.message('Delete', name: 'delete', desc: '', args: []);
  }

  /// `Seconds`
  String get seconds {
    return Intl.message('Seconds', name: 'seconds', desc: '', args: []);
  }

  /// `QR code`
  String get qrcode {
    return Intl.message('QR code', name: 'qrcode', desc: '', args: []);
  }

  /// `Scan QR code to obtain profile`
  String get qrcodeDesc {
    return Intl.message(
      'Scan QR code to obtain profile',
      name: 'qrcodeDesc',
      desc: '',
      args: [],
    );
  }

  /// `URL`
  String get url {
    return Intl.message('URL', name: 'url', desc: '', args: []);
  }

  /// `Obtain profile through URL`
  String get urlDesc {
    return Intl.message(
      'Obtain profile through URL',
      name: 'urlDesc',
      desc: '',
      args: [],
    );
  }

  /// `File`
  String get file {
    return Intl.message('File', name: 'file', desc: '', args: []);
  }

  /// `Directly upload profile`
  String get fileDesc {
    return Intl.message(
      'Directly upload profile',
      name: 'fileDesc',
      desc: '',
      args: [],
    );
  }

  /// `Name`
  String get name {
    return Intl.message('Name', name: 'name', desc: '', args: []);
  }

  /// `Please input the profile name`
  String get profileNameNullValidationDesc {
    return Intl.message(
      'Please input the profile name',
      name: 'profileNameNullValidationDesc',
      desc: '',
      args: [],
    );
  }

  /// `Please input the profile URL`
  String get profileUrlNullValidationDesc {
    return Intl.message(
      'Please input the profile URL',
      name: 'profileUrlNullValidationDesc',
      desc: '',
      args: [],
    );
  }

  /// `Please input a valid profile URL`
  String get profileUrlInvalidValidationDesc {
    return Intl.message(
      'Please input a valid profile URL',
      name: 'profileUrlInvalidValidationDesc',
      desc: '',
      args: [],
    );
  }

  /// `Auto update`
  String get autoUpdate {
    return Intl.message('Auto update', name: 'autoUpdate', desc: '', args: []);
  }

  /// `Auto update interval (minutes)`
  String get autoUpdateInterval {
    return Intl.message(
      'Auto update interval (minutes)',
      name: 'autoUpdateInterval',
      desc: '',
      args: [],
    );
  }

  /// `Please enter the auto update interval time`
  String get profileAutoUpdateIntervalNullValidationDesc {
    return Intl.message(
      'Please enter the auto update interval time',
      name: 'profileAutoUpdateIntervalNullValidationDesc',
      desc: '',
      args: [],
    );
  }

  /// `Please input a valid interval time format`
  String get profileAutoUpdateIntervalInvalidValidationDesc {
    return Intl.message(
      'Please input a valid interval time format',
      name: 'profileAutoUpdateIntervalInvalidValidationDesc',
      desc: '',
      args: [],
    );
  }

  /// `Theme mode`
  String get themeMode {
    return Intl.message('Theme mode', name: 'themeMode', desc: '', args: []);
  }

  /// `Theme color`
  String get themeColor {
    return Intl.message('Theme color', name: 'themeColor', desc: '', args: []);
  }

  /// `Preview`
  String get preview {
    return Intl.message('Preview', name: 'preview', desc: '', args: []);
  }

  /// `Auto`
  String get auto {
    return Intl.message('Auto', name: 'auto', desc: '', args: []);
  }

  /// `Light`
  String get light {
    return Intl.message('Light', name: 'light', desc: '', args: []);
  }

  /// `Dark`
  String get dark {
    return Intl.message('Dark', name: 'dark', desc: '', args: []);
  }

  /// `Import from URL`
  String get importFromURL {
    return Intl.message(
      'Import from URL',
      name: 'importFromURL',
      desc: '',
      args: [],
    );
  }

  /// `Submit`
  String get submit {
    return Intl.message('Submit', name: 'submit', desc: '', args: []);
  }

  /// `Do you want to pass`
  String get doYouWantToPass {
    return Intl.message(
      'Do you want to pass',
      name: 'doYouWantToPass',
      desc: '',
      args: [],
    );
  }

  /// `Create`
  String get create {
    return Intl.message('Create', name: 'create', desc: '', args: []);
  }

  /// `Please upload a valid QR code`
  String get pleaseUploadValidQrcode {
    return Intl.message(
      'Please upload a valid QR code',
      name: 'pleaseUploadValidQrcode',
      desc: '',
      args: [],
    );
  }

  /// `Blacklist mode`
  String get blacklistMode {
    return Intl.message(
      'Blacklist mode',
      name: 'blacklistMode',
      desc: '',
      args: [],
    );
  }

  /// `Whitelist mode`
  String get whitelistMode {
    return Intl.message(
      'Whitelist mode',
      name: 'whitelistMode',
      desc: '',
      args: [],
    );
  }

  /// `Select all`
  String get selectAll {
    return Intl.message('Select all', name: 'selectAll', desc: '', args: []);
  }

  /// `Cancel select all`
  String get cancelSelectAll {
    return Intl.message(
      'Cancel select all',
      name: 'cancelSelectAll',
      desc: '',
      args: [],
    );
  }

  /// `App access control`
  String get appAccessControl {
    return Intl.message(
      'App access control',
      name: 'appAccessControl',
      desc: '',
      args: [],
    );
  }

  /// `Only allow selected app to enter VPN`
  String get accessControlAllowDesc {
    return Intl.message(
      'Only allow selected app to enter VPN',
      name: 'accessControlAllowDesc',
      desc: '',
      args: [],
    );
  }

  /// `The selected application will be excluded from VPN`
  String get accessControlNotAllowDesc {
    return Intl.message(
      'The selected application will be excluded from VPN',
      name: 'accessControlNotAllowDesc',
      desc: '',
      args: [],
    );
  }

  /// `Selected`
  String get selected {
    return Intl.message('Selected', name: 'selected', desc: '', args: []);
  }

  /// `ProxyPort`
  String get proxyPort {
    return Intl.message('ProxyPort', name: 'proxyPort', desc: '', args: []);
  }

  /// `Port`
  String get port {
    return Intl.message('Port', name: 'port', desc: '', args: []);
  }

  /// `LogLevel`
  String get logLevel {
    return Intl.message('LogLevel', name: 'logLevel', desc: '', args: []);
  }

  /// `Show`
  String get show {
    return Intl.message('Show', name: 'show', desc: '', args: []);
  }

  /// `Exit`
  String get exit {
    return Intl.message('Exit', name: 'exit', desc: '', args: []);
  }

  /// `System proxy`
  String get systemProxy {
    return Intl.message(
      'System proxy',
      name: 'systemProxy',
      desc: '',
      args: [],
    );
  }

  /// `Project`
  String get project {
    return Intl.message('Project', name: 'project', desc: '', args: []);
  }

  /// `Core`
  String get core {
    return Intl.message('Core', name: 'core', desc: '', args: []);
  }

  /// `Tab animation`
  String get tabAnimation {
    return Intl.message(
      'Tab animation',
      name: 'tabAnimation',
      desc: '',
      args: [],
    );
  }

  /// `A multi-platform proxy client based on ClashMeta, simple and easy to use, open-source and ad-free.`
  String get desc {
    return Intl.message(
      'A multi-platform proxy client based on ClashMeta, simple and easy to use, open-source and ad-free.',
      name: 'desc',
      desc: '',
      args: [],
    );
  }

  /// `Starting VPN...`
  String get startVpn {
    return Intl.message(
      'Starting VPN...',
      name: 'startVpn',
      desc: '',
      args: [],
    );
  }

  /// `Stopping VPN...`
  String get stopVpn {
    return Intl.message('Stopping VPN...', name: 'stopVpn', desc: '', args: []);
  }

  /// `Compatibility mode`
  String get compatible {
    return Intl.message(
      'Compatibility mode',
      name: 'compatible',
      desc: '',
      args: [],
    );
  }

  /// `The current proxy group cannot be selected.`
  String get notSelectedTip {
    return Intl.message(
      'The current proxy group cannot be selected.',
      name: 'notSelectedTip',
      desc: '',
      args: [],
    );
  }

  /// `tip`
  String get tip {
    return Intl.message('tip', name: 'tip', desc: '', args: []);
  }

  /// `Account`
  String get account {
    return Intl.message('Account', name: 'account', desc: '', args: []);
  }

  /// `Backup`
  String get backup {
    return Intl.message('Backup', name: 'backup', desc: '', args: []);
  }

  /// `Backup success`
  String get backupSuccess {
    return Intl.message(
      'Backup success',
      name: 'backupSuccess',
      desc: '',
      args: [],
    );
  }

  /// `No info`
  String get noInfo {
    return Intl.message('No info', name: 'noInfo', desc: '', args: []);
  }

  /// `Please bind WebDAV`
  String get pleaseBindWebDAV {
    return Intl.message(
      'Please bind WebDAV',
      name: 'pleaseBindWebDAV',
      desc: '',
      args: [],
    );
  }

  /// `Bind`
  String get bind {
    return Intl.message('Bind', name: 'bind', desc: '', args: []);
  }

  /// `Connectivity：`
  String get connectivity {
    return Intl.message(
      'Connectivity：',
      name: 'connectivity',
      desc: '',
      args: [],
    );
  }

  /// `WebDAV configuration`
  String get webDAVConfiguration {
    return Intl.message(
      'WebDAV configuration',
      name: 'webDAVConfiguration',
      desc: '',
      args: [],
    );
  }

  /// `Address`
  String get address {
    return Intl.message('Address', name: 'address', desc: '', args: []);
  }

  /// `WebDAV server address`
  String get addressHelp {
    return Intl.message(
      'WebDAV server address',
      name: 'addressHelp',
      desc: '',
      args: [],
    );
  }

  /// `Please enter a valid WebDAV address`
  String get addressTip {
    return Intl.message(
      'Please enter a valid WebDAV address',
      name: 'addressTip',
      desc: '',
      args: [],
    );
  }

  /// `Password`
  String get password {
    return Intl.message('Password', name: 'password', desc: '', args: []);
  }

  /// `Check for updates`
  String get checkUpdate {
    return Intl.message(
      'Check for updates',
      name: 'checkUpdate',
      desc: '',
      args: [],
    );
  }

  /// `Discover the new version`
  String get discoverNewVersion {
    return Intl.message(
      'Discover the new version',
      name: 'discoverNewVersion',
      desc: '',
      args: [],
    );
  }

  /// `The current application is already the latest version`
  String get checkUpdateError {
    return Intl.message(
      'The current application is already the latest version',
      name: 'checkUpdateError',
      desc: '',
      args: [],
    );
  }

  /// `Go to download`
  String get goDownload {
    return Intl.message(
      'Go to download',
      name: 'goDownload',
      desc: '',
      args: [],
    );
  }

  /// `Unknown`
  String get unknown {
    return Intl.message('Unknown', name: 'unknown', desc: '', args: []);
  }

  /// `Country`
  String get country {
    return Intl.message('Country', name: 'country', desc: '', args: []);
  }

  /// `Search`
  String get search {
    return Intl.message('Search', name: 'search', desc: '', args: []);
  }

  /// `Allow applications to bypass VPN`
  String get allowBypass {
    return Intl.message(
      'Allow applications to bypass VPN',
      name: 'allowBypass',
      desc: '',
      args: [],
    );
  }

  /// `Some apps can bypass VPN when turned on`
  String get allowBypassDesc {
    return Intl.message(
      'Some apps can bypass VPN when turned on',
      name: 'allowBypassDesc',
      desc: '',
      args: [],
    );
  }

  /// `ExternalController`
  String get externalController {
    return Intl.message(
      'ExternalController',
      name: 'externalController',
      desc: '',
      args: [],
    );
  }

  /// `Once enabled, the Clash kernel can be controlled on port 9090`
  String get externalControllerDesc {
    return Intl.message(
      'Once enabled, the Clash kernel can be controlled on port 9090',
      name: 'externalControllerDesc',
      desc: '',
      args: [],
    );
  }

  /// `When turned on it will be able to receive IPv6 traffic`
  String get ipv6Desc {
    return Intl.message(
      'When turned on it will be able to receive IPv6 traffic',
      name: 'ipv6Desc',
      desc: '',
      args: [],
    );
  }

  /// `App`
  String get app {
    return Intl.message('App', name: 'app', desc: '', args: []);
  }

  /// `General`
  String get general {
    return Intl.message('General', name: 'general', desc: '', args: []);
  }

  /// `Attach HTTP proxy to VpnService`
  String get systemProxyDesc {
    return Intl.message(
      'Attach HTTP proxy to VpnService',
      name: 'systemProxyDesc',
      desc: '',
      args: [],
    );
  }

  /// `Could not enable the system proxy ({code}). The switch was reverted. Export logs for diagnosis`
  String systemProxyApplyFailed(Object code) {
    return Intl.message(
      'Could not enable the system proxy ($code). The switch was reverted. Export logs for diagnosis',
      name: 'systemProxyApplyFailed',
      desc: '',
      args: [code],
    );
  }

  /// `Could not disable the system proxy ({code}). Disable it manually in Windows Settings`
  String systemProxyDisableFailed(Object code) {
    return Intl.message(
      'Could not disable the system proxy ($code). Disable it manually in Windows Settings',
      name: 'systemProxyDisableFailed',
      desc: '',
      args: [code],
    );
  }

  /// `The system proxy left by the previous abnormal exit was cleared`
  String get systemProxyStaleCleaned {
    return Intl.message(
      'The system proxy left by the previous abnormal exit was cleared',
      name: 'systemProxyStaleCleaned',
      desc: '',
      args: [],
    );
  }

  /// `Run network diagnostics`
  String get runNetworkDiagnostics {
    return Intl.message(
      'Run network diagnostics',
      name: 'runNetworkDiagnostics',
      desc: '',
      args: [],
    );
  }

  /// `No subscription profile is available. Log in again or refresh the subscription`
  String get networkDiagnosticNoProfile {
    return Intl.message(
      'No subscription profile is available. Log in again or refresh the subscription',
      name: 'networkDiagnosticNoProfile',
      desc: '',
      args: [],
    );
  }

  /// `Configuration domains`
  String get networkDiagnosticConfigDomains {
    return Intl.message(
      'Configuration domains',
      name: 'networkDiagnosticConfigDomains',
      desc: '',
      args: [],
    );
  }

  /// `{reachable}/{total} resolvable`
  String networkDiagnosticConfigDomainsResult(Object reachable, Object total) {
    return Intl.message(
      '$reachable/$total resolvable',
      name: 'networkDiagnosticConfigDomainsResult',
      desc: '',
      args: [reachable, total],
    );
  }

  /// `The proxy core is not running`
  String get networkDiagnosticCoreNotRunning {
    return Intl.message(
      'The proxy core is not running',
      name: 'networkDiagnosticCoreNotRunning',
      desc: '',
      args: [],
    );
  }

  /// `Local proxy port`
  String get networkDiagnosticLocalProxyPort {
    return Intl.message(
      'Local proxy port',
      name: 'networkDiagnosticLocalProxyPort',
      desc: '',
      args: [],
    );
  }

  /// `{address} is listening`
  String networkDiagnosticPortListening(Object address) {
    return Intl.message(
      '$address is listening',
      name: 'networkDiagnosticPortListening',
      desc: '',
      args: [address],
    );
  }

  /// `Cannot connect to {address}`
  String networkDiagnosticPortUnavailable(Object address) {
    return Intl.message(
      'Cannot connect to $address',
      name: 'networkDiagnosticPortUnavailable',
      desc: '',
      args: [address],
    );
  }

  /// `The core is running, but the local proxy port is not listening`
  String get networkDiagnosticPortNotListening {
    return Intl.message(
      'The core is running, but the local proxy port is not listening',
      name: 'networkDiagnosticPortNotListening',
      desc: '',
      args: [],
    );
  }

  /// `Windows system proxy`
  String get networkDiagnosticWindowsSystemProxy {
    return Intl.message(
      'Windows system proxy',
      name: 'networkDiagnosticWindowsSystemProxy',
      desc: '',
      args: [],
    );
  }

  /// `Readback verified {address}`
  String networkDiagnosticProxyVerified(Object address) {
    return Intl.message(
      'Readback verified $address',
      name: 'networkDiagnosticProxyVerified',
      desc: '',
      args: [address],
    );
  }

  /// `{code} / {stage}{error}`
  String networkDiagnosticProxyFailure(
    Object code,
    Object stage,
    Object error,
  ) {
    return Intl.message(
      '$code / $stage$error',
      name: 'networkDiagnosticProxyFailure',
      desc: '',
      args: [code, stage, error],
    );
  }

  /// `The Windows system proxy is not configured correctly`
  String get networkDiagnosticSystemProxyInvalid {
    return Intl.message(
      'The Windows system proxy is not configured correctly',
      name: 'networkDiagnosticSystemProxyInvalid',
      desc: '',
      args: [],
    );
  }

  /// `Node internet access`
  String get networkDiagnosticNodeInternet {
    return Intl.message(
      'Node internet access',
      name: 'networkDiagnosticNodeInternet',
      desc: '',
      args: [],
    );
  }

  /// `Internet access through the local proxy succeeded`
  String get networkDiagnosticInternetSuccess {
    return Intl.message(
      'Internet access through the local proxy succeeded',
      name: 'networkDiagnosticInternetSuccess',
      desc: '',
      args: [],
    );
  }

  /// `Internet access through the local proxy failed`
  String get networkDiagnosticInternetFailed {
    return Intl.message(
      'Internet access through the local proxy failed',
      name: 'networkDiagnosticInternetFailed',
      desc: '',
      args: [],
    );
  }

  /// `The local port works, but the current node cannot access the internet`
  String get networkDiagnosticNodeUnavailable {
    return Intl.message(
      'The local port works, but the current node cannot access the internet',
      name: 'networkDiagnosticNodeUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `The node works, but neither system proxy nor TUN is enabled, so application traffic will not enter the core`
  String get networkDiagnosticTrafficEntryMissing {
    return Intl.message(
      'The node works, but neither system proxy nor TUN is enabled, so application traffic will not enter the core',
      name: 'networkDiagnosticTrafficEntryMissing',
      desc: '',
      args: [],
    );
  }

  /// `Internet access through the local proxy succeeded; application and TUN traffic capture is not verified`
  String get networkDiagnosticSuccess {
    return Intl.message(
      'Internet access through the local proxy succeeded; application and TUN traffic capture is not verified',
      name: 'networkDiagnosticSuccess',
      desc: '',
      args: [],
    );
  }

  /// `The local proxy can access the internet, but no configuration domain resolves`
  String get networkDiagnosticConfigDnsFailed {
    return Intl.message(
      'The local proxy can access the internet, but no configuration domain resolves',
      name: 'networkDiagnosticConfigDnsFailed',
      desc: '',
      args: [],
    );
  }

  /// `User-Agent`
  String get userAgent {
    return Intl.message('User-Agent', name: 'userAgent', desc: '', args: []);
  }

  /// `Unified delay`
  String get unifiedDelay {
    return Intl.message(
      'Unified delay',
      name: 'unifiedDelay',
      desc: '',
      args: [],
    );
  }

  /// `Remove extra delays such as handshaking`
  String get unifiedDelayDesc {
    return Intl.message(
      'Remove extra delays such as handshaking',
      name: 'unifiedDelayDesc',
      desc: '',
      args: [],
    );
  }

  /// `TCP concurrent`
  String get tcpConcurrent {
    return Intl.message(
      'TCP concurrent',
      name: 'tcpConcurrent',
      desc: '',
      args: [],
    );
  }

  /// `Enabling it will allow TCP concurrency`
  String get tcpConcurrentDesc {
    return Intl.message(
      'Enabling it will allow TCP concurrency',
      name: 'tcpConcurrentDesc',
      desc: '',
      args: [],
    );
  }

  /// `Geo Low Memory Mode`
  String get geodataLoader {
    return Intl.message(
      'Geo Low Memory Mode',
      name: 'geodataLoader',
      desc: '',
      args: [],
    );
  }

  /// `Enabling will use the Geo low memory loader`
  String get geodataLoaderDesc {
    return Intl.message(
      'Enabling will use the Geo low memory loader',
      name: 'geodataLoaderDesc',
      desc: '',
      args: [],
    );
  }

  /// `Requests`
  String get requests {
    return Intl.message('Requests', name: 'requests', desc: '', args: []);
  }

  /// `View recently request records`
  String get requestsDesc {
    return Intl.message(
      'View recently request records',
      name: 'requestsDesc',
      desc: '',
      args: [],
    );
  }

  /// `Find process`
  String get findProcessMode {
    return Intl.message(
      'Find process',
      name: 'findProcessMode',
      desc: '',
      args: [],
    );
  }

  /// `Init`
  String get init {
    return Intl.message('Init', name: 'init', desc: '', args: []);
  }

  /// `Long term effective`
  String get infiniteTime {
    return Intl.message(
      'Long term effective',
      name: 'infiniteTime',
      desc: '',
      args: [],
    );
  }

  /// `Connections`
  String get connections {
    return Intl.message('Connections', name: 'connections', desc: '', args: []);
  }

  /// `View current connections data`
  String get connectionsDesc {
    return Intl.message(
      'View current connections data',
      name: 'connectionsDesc',
      desc: '',
      args: [],
    );
  }

  /// `Intranet IP`
  String get intranetIP {
    return Intl.message('Intranet IP', name: 'intranetIP', desc: '', args: []);
  }

  /// `View`
  String get view {
    return Intl.message('View', name: 'view', desc: '', args: []);
  }

  /// `Cut`
  String get cut {
    return Intl.message('Cut', name: 'cut', desc: '', args: []);
  }

  /// `Copy`
  String get copy {
    return Intl.message('Copy', name: 'copy', desc: '', args: []);
  }

  /// `Paste`
  String get paste {
    return Intl.message('Paste', name: 'paste', desc: '', args: []);
  }

  /// `Test url`
  String get testUrl {
    return Intl.message('Test url', name: 'testUrl', desc: '', args: []);
  }

  /// `Sync`
  String get sync {
    return Intl.message('Sync', name: 'sync', desc: '', args: []);
  }

  /// `Hidden from recent tasks`
  String get exclude {
    return Intl.message(
      'Hidden from recent tasks',
      name: 'exclude',
      desc: '',
      args: [],
    );
  }

  /// `When the app is in the background, the app is hidden from the recent task`
  String get excludeDesc {
    return Intl.message(
      'When the app is in the background, the app is hidden from the recent task',
      name: 'excludeDesc',
      desc: '',
      args: [],
    );
  }

  /// `Standard`
  String get expand {
    return Intl.message('Standard', name: 'expand', desc: '', args: []);
  }

  /// `Shrink`
  String get shrink {
    return Intl.message('Shrink', name: 'shrink', desc: '', args: []);
  }

  /// `Min`
  String get min {
    return Intl.message('Min', name: 'min', desc: '', args: []);
  }

  /// `Tab`
  String get tab {
    return Intl.message('Tab', name: 'tab', desc: '', args: []);
  }

  /// `List`
  String get list {
    return Intl.message('List', name: 'list', desc: '', args: []);
  }

  /// `Delay`
  String get delay {
    return Intl.message('Delay', name: 'delay', desc: '', args: []);
  }

  /// `Actual latency`
  String get actualConnectionDelay {
    return Intl.message(
      'Actual latency',
      name: 'actualConnectionDelay',
      desc: '',
      args: [],
    );
  }

  /// `Standard RTT`
  String get standardizedDelay {
    return Intl.message(
      'Standard RTT',
      name: 'standardizedDelay',
      desc: '',
      args: [],
    );
  }

  /// `Style`
  String get style {
    return Intl.message('Style', name: 'style', desc: '', args: []);
  }

  /// `Size`
  String get size {
    return Intl.message('Size', name: 'size', desc: '', args: []);
  }

  /// `Sort`
  String get sort {
    return Intl.message('Sort', name: 'sort', desc: '', args: []);
  }

  /// `Columns`
  String get columns {
    return Intl.message('Columns', name: 'columns', desc: '', args: []);
  }

  /// `Proxy group`
  String get proxyGroup {
    return Intl.message('Proxy group', name: 'proxyGroup', desc: '', args: []);
  }

  /// `Go`
  String get go {
    return Intl.message('Go', name: 'go', desc: '', args: []);
  }

  /// `External link`
  String get externalLink {
    return Intl.message(
      'External link',
      name: 'externalLink',
      desc: '',
      args: [],
    );
  }

  /// `Other contributors`
  String get otherContributors {
    return Intl.message(
      'Other contributors',
      name: 'otherContributors',
      desc: '',
      args: [],
    );
  }

  /// `Auto close connections`
  String get autoCloseConnections {
    return Intl.message(
      'Auto close connections',
      name: 'autoCloseConnections',
      desc: '',
      args: [],
    );
  }

  /// `Auto close connections after change node`
  String get autoCloseConnectionsDesc {
    return Intl.message(
      'Auto close connections after change node',
      name: 'autoCloseConnectionsDesc',
      desc: '',
      args: [],
    );
  }

  /// `Only statistics proxy`
  String get onlyStatisticsProxy {
    return Intl.message(
      'Only statistics proxy',
      name: 'onlyStatisticsProxy',
      desc: '',
      args: [],
    );
  }

  /// `When turned on, only statistics proxy traffic`
  String get onlyStatisticsProxyDesc {
    return Intl.message(
      'When turned on, only statistics proxy traffic',
      name: 'onlyStatisticsProxyDesc',
      desc: '',
      args: [],
    );
  }

  /// `Pure black mode`
  String get pureBlackMode {
    return Intl.message(
      'Pure black mode',
      name: 'pureBlackMode',
      desc: '',
      args: [],
    );
  }

  /// `Tcp keep alive interval`
  String get keepAliveIntervalDesc {
    return Intl.message(
      'Tcp keep alive interval',
      name: 'keepAliveIntervalDesc',
      desc: '',
      args: [],
    );
  }

  /// ` entries`
  String get entries {
    return Intl.message(' entries', name: 'entries', desc: '', args: []);
  }

  /// `Local`
  String get local {
    return Intl.message('Local', name: 'local', desc: '', args: []);
  }

  /// `Remote`
  String get remote {
    return Intl.message('Remote', name: 'remote', desc: '', args: []);
  }

  /// `Backup local data to WebDAV`
  String get remoteBackupDesc {
    return Intl.message(
      'Backup local data to WebDAV',
      name: 'remoteBackupDesc',
      desc: '',
      args: [],
    );
  }

  /// `Backup local data to local`
  String get localBackupDesc {
    return Intl.message(
      'Backup local data to local',
      name: 'localBackupDesc',
      desc: '',
      args: [],
    );
  }

  /// `Mode`
  String get mode {
    return Intl.message('Mode', name: 'mode', desc: '', args: []);
  }

  /// `Time`
  String get time {
    return Intl.message('Time', name: 'time', desc: '', args: []);
  }

  /// `Source`
  String get source {
    return Intl.message('Source', name: 'source', desc: '', args: []);
  }

  /// `Action`
  String get action {
    return Intl.message('Action', name: 'action', desc: '', args: []);
  }

  /// `Intelligent selection`
  String get intelligentSelected {
    return Intl.message(
      'Intelligent selection',
      name: 'intelligentSelected',
      desc: '',
      args: [],
    );
  }

  /// `Clipboard import`
  String get clipboardImport {
    return Intl.message(
      'Clipboard import',
      name: 'clipboardImport',
      desc: '',
      args: [],
    );
  }

  /// `Export clipboard`
  String get clipboardExport {
    return Intl.message(
      'Export clipboard',
      name: 'clipboardExport',
      desc: '',
      args: [],
    );
  }

  /// `Layout`
  String get layout {
    return Intl.message('Layout', name: 'layout', desc: '', args: []);
  }

  /// `Tight`
  String get tight {
    return Intl.message('Tight', name: 'tight', desc: '', args: []);
  }

  /// `Standard`
  String get standard {
    return Intl.message('Standard', name: 'standard', desc: '', args: []);
  }

  /// `Loose`
  String get loose {
    return Intl.message('Loose', name: 'loose', desc: '', args: []);
  }

  /// `Profiles sort`
  String get profilesSort {
    return Intl.message(
      'Profiles sort',
      name: 'profilesSort',
      desc: '',
      args: [],
    );
  }

  /// `Start`
  String get start {
    return Intl.message('Start', name: 'start', desc: '', args: []);
  }

  /// `Stop`
  String get stop {
    return Intl.message('Stop', name: 'stop', desc: '', args: []);
  }

  /// `Update DNS related settings`
  String get dnsDesc {
    return Intl.message(
      'Update DNS related settings',
      name: 'dnsDesc',
      desc: '',
      args: [],
    );
  }

  /// `Key`
  String get key {
    return Intl.message('Key', name: 'key', desc: '', args: []);
  }

  /// `Value`
  String get value {
    return Intl.message('Value', name: 'value', desc: '', args: []);
  }

  /// `Add Hosts`
  String get hostsDesc {
    return Intl.message('Add Hosts', name: 'hostsDesc', desc: '', args: []);
  }

  /// `Changes take effect after restarting the VPN`
  String get vpnTip {
    return Intl.message(
      'Changes take effect after restarting the VPN',
      name: 'vpnTip',
      desc: '',
      args: [],
    );
  }

  /// `Auto routes all system traffic through VpnService`
  String get vpnEnableDesc {
    return Intl.message(
      'Auto routes all system traffic through VpnService',
      name: 'vpnEnableDesc',
      desc: '',
      args: [],
    );
  }

  /// `Options`
  String get options {
    return Intl.message('Options', name: 'options', desc: '', args: []);
  }

  /// `Loopback unlock tool`
  String get loopback {
    return Intl.message(
      'Loopback unlock tool',
      name: 'loopback',
      desc: '',
      args: [],
    );
  }

  /// `Used for UWP loopback unlocking`
  String get loopbackDesc {
    return Intl.message(
      'Used for UWP loopback unlocking',
      name: 'loopbackDesc',
      desc: '',
      args: [],
    );
  }

  /// `Providers`
  String get providers {
    return Intl.message('Providers', name: 'providers', desc: '', args: []);
  }

  /// `Proxy providers`
  String get proxyProviders {
    return Intl.message(
      'Proxy providers',
      name: 'proxyProviders',
      desc: '',
      args: [],
    );
  }

  /// `Rule providers`
  String get ruleProviders {
    return Intl.message(
      'Rule providers',
      name: 'ruleProviders',
      desc: '',
      args: [],
    );
  }

  /// `Override Dns`
  String get overrideDns {
    return Intl.message(
      'Override Dns',
      name: 'overrideDns',
      desc: '',
      args: [],
    );
  }

  /// `Turning it on will override the DNS options in the profile`
  String get overrideDnsDesc {
    return Intl.message(
      'Turning it on will override the DNS options in the profile',
      name: 'overrideDnsDesc',
      desc: '',
      args: [],
    );
  }

  /// `Status`
  String get status {
    return Intl.message('Status', name: 'status', desc: '', args: []);
  }

  /// `System DNS will be used when turned off`
  String get statusDesc {
    return Intl.message(
      'System DNS will be used when turned off',
      name: 'statusDesc',
      desc: '',
      args: [],
    );
  }

  /// `Prioritize the use of DOH's http/3`
  String get preferH3Desc {
    return Intl.message(
      'Prioritize the use of DOH\'s http/3',
      name: 'preferH3Desc',
      desc: '',
      args: [],
    );
  }

  /// `Respect rules`
  String get respectRules {
    return Intl.message(
      'Respect rules',
      name: 'respectRules',
      desc: '',
      args: [],
    );
  }

  /// `DNS connection following rules, need to configure proxy-server-nameserver`
  String get respectRulesDesc {
    return Intl.message(
      'DNS connection following rules, need to configure proxy-server-nameserver',
      name: 'respectRulesDesc',
      desc: '',
      args: [],
    );
  }

  /// `DNS mode`
  String get dnsMode {
    return Intl.message('DNS mode', name: 'dnsMode', desc: '', args: []);
  }

  /// `Fakeip range`
  String get fakeipRange {
    return Intl.message(
      'Fakeip range',
      name: 'fakeipRange',
      desc: '',
      args: [],
    );
  }

  /// `Fakeip filter`
  String get fakeipFilter {
    return Intl.message(
      'Fakeip filter',
      name: 'fakeipFilter',
      desc: '',
      args: [],
    );
  }

  /// `Default nameserver`
  String get defaultNameserver {
    return Intl.message(
      'Default nameserver',
      name: 'defaultNameserver',
      desc: '',
      args: [],
    );
  }

  /// `For resolving DNS server`
  String get defaultNameserverDesc {
    return Intl.message(
      'For resolving DNS server',
      name: 'defaultNameserverDesc',
      desc: '',
      args: [],
    );
  }

  /// `Nameserver`
  String get nameserver {
    return Intl.message('Nameserver', name: 'nameserver', desc: '', args: []);
  }

  /// `For resolving domain`
  String get nameserverDesc {
    return Intl.message(
      'For resolving domain',
      name: 'nameserverDesc',
      desc: '',
      args: [],
    );
  }

  /// `Use hosts`
  String get useHosts {
    return Intl.message('Use hosts', name: 'useHosts', desc: '', args: []);
  }

  /// `Use system hosts`
  String get useSystemHosts {
    return Intl.message(
      'Use system hosts',
      name: 'useSystemHosts',
      desc: '',
      args: [],
    );
  }

  /// `Nameserver policy`
  String get nameserverPolicy {
    return Intl.message(
      'Nameserver policy',
      name: 'nameserverPolicy',
      desc: '',
      args: [],
    );
  }

  /// `Specify the corresponding nameserver policy`
  String get nameserverPolicyDesc {
    return Intl.message(
      'Specify the corresponding nameserver policy',
      name: 'nameserverPolicyDesc',
      desc: '',
      args: [],
    );
  }

  /// `Proxy nameserver`
  String get proxyNameserver {
    return Intl.message(
      'Proxy nameserver',
      name: 'proxyNameserver',
      desc: '',
      args: [],
    );
  }

  /// `Domain for resolving proxy nodes`
  String get proxyNameserverDesc {
    return Intl.message(
      'Domain for resolving proxy nodes',
      name: 'proxyNameserverDesc',
      desc: '',
      args: [],
    );
  }

  /// `Fallback`
  String get fallback {
    return Intl.message('Fallback', name: 'fallback', desc: '', args: []);
  }

  /// `Generally use offshore DNS`
  String get fallbackDesc {
    return Intl.message(
      'Generally use offshore DNS',
      name: 'fallbackDesc',
      desc: '',
      args: [],
    );
  }

  /// `Fallback filter`
  String get fallbackFilter {
    return Intl.message(
      'Fallback filter',
      name: 'fallbackFilter',
      desc: '',
      args: [],
    );
  }

  /// `Geoip code`
  String get geoipCode {
    return Intl.message('Geoip code', name: 'geoipCode', desc: '', args: []);
  }

  /// `Ipcidr`
  String get ipcidr {
    return Intl.message('Ipcidr', name: 'ipcidr', desc: '', args: []);
  }

  /// `Domain`
  String get domain {
    return Intl.message('Domain', name: 'domain', desc: '', args: []);
  }

  /// `Reset`
  String get reset {
    return Intl.message('Reset', name: 'reset', desc: '', args: []);
  }

  /// `Show/Hide`
  String get action_view {
    return Intl.message('Show/Hide', name: 'action_view', desc: '', args: []);
  }

  /// `Start/Stop`
  String get action_start {
    return Intl.message('Start/Stop', name: 'action_start', desc: '', args: []);
  }

  /// `Switch mode`
  String get action_mode {
    return Intl.message('Switch mode', name: 'action_mode', desc: '', args: []);
  }

  /// `System proxy`
  String get action_proxy {
    return Intl.message(
      'System proxy',
      name: 'action_proxy',
      desc: '',
      args: [],
    );
  }

  /// `TUN`
  String get action_tun {
    return Intl.message('TUN', name: 'action_tun', desc: '', args: []);
  }

  /// `Disclaimer`
  String get disclaimer {
    return Intl.message('Disclaimer', name: 'disclaimer', desc: '', args: []);
  }

  /// `This software is only used for non-commercial purposes such as learning exchanges and scientific research. It is strictly prohibited to use this software for commercial purposes. Any commercial activity, if any, has nothing to do with this software.`
  String get disclaimerDesc {
    return Intl.message(
      'This software is only used for non-commercial purposes such as learning exchanges and scientific research. It is strictly prohibited to use this software for commercial purposes. Any commercial activity, if any, has nothing to do with this software.',
      name: 'disclaimerDesc',
      desc: '',
      args: [],
    );
  }

  /// `Agree`
  String get agree {
    return Intl.message('Agree', name: 'agree', desc: '', args: []);
  }

  /// `Hotkey Management`
  String get hotkeyManagement {
    return Intl.message(
      'Hotkey Management',
      name: 'hotkeyManagement',
      desc: '',
      args: [],
    );
  }

  /// `Use keyboard to control applications`
  String get hotkeyManagementDesc {
    return Intl.message(
      'Use keyboard to control applications',
      name: 'hotkeyManagementDesc',
      desc: '',
      args: [],
    );
  }

  /// `Please press the keyboard.`
  String get pressKeyboard {
    return Intl.message(
      'Please press the keyboard.',
      name: 'pressKeyboard',
      desc: '',
      args: [],
    );
  }

  /// `Please enter the correct hotkey`
  String get inputCorrectHotkey {
    return Intl.message(
      'Please enter the correct hotkey',
      name: 'inputCorrectHotkey',
      desc: '',
      args: [],
    );
  }

  /// `Hotkey conflict`
  String get hotkeyConflict {
    return Intl.message(
      'Hotkey conflict',
      name: 'hotkeyConflict',
      desc: '',
      args: [],
    );
  }

  /// `Remove`
  String get remove {
    return Intl.message('Remove', name: 'remove', desc: '', args: []);
  }

  /// `No HotKey`
  String get noHotKey {
    return Intl.message('No HotKey', name: 'noHotKey', desc: '', args: []);
  }

  /// `No network`
  String get noNetwork {
    return Intl.message('No network', name: 'noNetwork', desc: '', args: []);
  }

  /// `Allow IPv6 inbound`
  String get ipv6InboundDesc {
    return Intl.message(
      'Allow IPv6 inbound',
      name: 'ipv6InboundDesc',
      desc: '',
      args: [],
    );
  }

  /// `Export logs`
  String get exportLogs {
    return Intl.message('Export logs', name: 'exportLogs', desc: '', args: []);
  }

  /// `Export Success`
  String get exportSuccess {
    return Intl.message(
      'Export Success',
      name: 'exportSuccess',
      desc: '',
      args: [],
    );
  }

  /// `Icon style`
  String get iconStyle {
    return Intl.message('Icon style', name: 'iconStyle', desc: '', args: []);
  }

  /// `Icon`
  String get onlyIcon {
    return Intl.message('Icon', name: 'onlyIcon', desc: '', args: []);
  }

  /// `Stack mode`
  String get stackMode {
    return Intl.message('Stack mode', name: 'stackMode', desc: '', args: []);
  }

  /// `Network`
  String get network {
    return Intl.message('Network', name: 'network', desc: '', args: []);
  }

  /// `Modify network-related settings`
  String get networkDesc {
    return Intl.message(
      'Modify network-related settings',
      name: 'networkDesc',
      desc: '',
      args: [],
    );
  }

  /// `Bypass domain`
  String get bypassDomain {
    return Intl.message(
      'Bypass domain',
      name: 'bypassDomain',
      desc: '',
      args: [],
    );
  }

  /// `Only takes effect when the system proxy is enabled`
  String get bypassDomainDesc {
    return Intl.message(
      'Only takes effect when the system proxy is enabled',
      name: 'bypassDomainDesc',
      desc: '',
      args: [],
    );
  }

  /// `Make sure to reset`
  String get resetTip {
    return Intl.message(
      'Make sure to reset',
      name: 'resetTip',
      desc: '',
      args: [],
    );
  }

  /// `Icon`
  String get icon {
    return Intl.message('Icon', name: 'icon', desc: '', args: []);
  }

  /// `No data`
  String get noData {
    return Intl.message('No data', name: 'noData', desc: '', args: []);
  }

  /// `FontFamily`
  String get fontFamily {
    return Intl.message('FontFamily', name: 'fontFamily', desc: '', args: []);
  }

  /// `Toggle`
  String get toggle {
    return Intl.message('Toggle', name: 'toggle', desc: '', args: []);
  }

  /// `System`
  String get system {
    return Intl.message('System', name: 'system', desc: '', args: []);
  }

  /// `Route mode`
  String get routeMode {
    return Intl.message('Route mode', name: 'routeMode', desc: '', args: []);
  }

  /// `Bypass private route address`
  String get routeMode_bypassPrivate {
    return Intl.message(
      'Bypass private route address',
      name: 'routeMode_bypassPrivate',
      desc: '',
      args: [],
    );
  }

  /// `Use config`
  String get routeMode_config {
    return Intl.message(
      'Use config',
      name: 'routeMode_config',
      desc: '',
      args: [],
    );
  }

  /// `Route address`
  String get routeAddress {
    return Intl.message(
      'Route address',
      name: 'routeAddress',
      desc: '',
      args: [],
    );
  }

  /// `Config listen route address`
  String get routeAddressDesc {
    return Intl.message(
      'Config listen route address',
      name: 'routeAddressDesc',
      desc: '',
      args: [],
    );
  }

  /// `Please enter the admin password`
  String get pleaseInputAdminPassword {
    return Intl.message(
      'Please enter the admin password',
      name: 'pleaseInputAdminPassword',
      desc: '',
      args: [],
    );
  }

  /// `Copying environment variables`
  String get copyEnvVar {
    return Intl.message(
      'Copying environment variables',
      name: 'copyEnvVar',
      desc: '',
      args: [],
    );
  }

  /// `Memory info`
  String get memoryInfo {
    return Intl.message('Memory info', name: 'memoryInfo', desc: '', args: []);
  }

  /// `Cancel`
  String get cancel {
    return Intl.message('Cancel', name: 'cancel', desc: '', args: []);
  }

  /// `The file has been modified. Do you want to save the changes?`
  String get fileIsUpdate {
    return Intl.message(
      'The file has been modified. Do you want to save the changes?',
      name: 'fileIsUpdate',
      desc: '',
      args: [],
    );
  }

  /// `The profile has been modified. Do you want to disable auto update?`
  String get profileHasUpdate {
    return Intl.message(
      'The profile has been modified. Do you want to disable auto update?',
      name: 'profileHasUpdate',
      desc: '',
      args: [],
    );
  }

  /// `Do you want to cache the changes?`
  String get hasCacheChange {
    return Intl.message(
      'Do you want to cache the changes?',
      name: 'hasCacheChange',
      desc: '',
      args: [],
    );
  }

  /// `Copy success`
  String get copySuccess {
    return Intl.message(
      'Copy success',
      name: 'copySuccess',
      desc: '',
      args: [],
    );
  }

  /// `Copy link`
  String get copyLink {
    return Intl.message('Copy link', name: 'copyLink', desc: '', args: []);
  }

  /// `Export file`
  String get exportFile {
    return Intl.message('Export file', name: 'exportFile', desc: '', args: []);
  }

  /// `The cache is corrupt. Do you want to clear it?`
  String get cacheCorrupt {
    return Intl.message(
      'The cache is corrupt. Do you want to clear it?',
      name: 'cacheCorrupt',
      desc: '',
      args: [],
    );
  }

  /// `Relying on third-party api is for reference only`
  String get detectionTip {
    return Intl.message(
      'Relying on third-party api is for reference only',
      name: 'detectionTip',
      desc: '',
      args: [],
    );
  }

  /// `Listen`
  String get listen {
    return Intl.message('Listen', name: 'listen', desc: '', args: []);
  }

  /// `undo`
  String get undo {
    return Intl.message('undo', name: 'undo', desc: '', args: []);
  }

  /// `redo`
  String get redo {
    return Intl.message('redo', name: 'redo', desc: '', args: []);
  }

  /// `none`
  String get none {
    return Intl.message('none', name: 'none', desc: '', args: []);
  }

  /// `Basic configuration`
  String get basicConfig {
    return Intl.message(
      'Basic configuration',
      name: 'basicConfig',
      desc: '',
      args: [],
    );
  }

  /// `Modify the basic configuration globally`
  String get basicConfigDesc {
    return Intl.message(
      'Modify the basic configuration globally',
      name: 'basicConfigDesc',
      desc: '',
      args: [],
    );
  }

  /// `Advanced configuration`
  String get advancedConfig {
    return Intl.message(
      'Advanced configuration',
      name: 'advancedConfig',
      desc: '',
      args: [],
    );
  }

  /// `Provide diverse configuration options`
  String get advancedConfigDesc {
    return Intl.message(
      'Provide diverse configuration options',
      name: 'advancedConfigDesc',
      desc: '',
      args: [],
    );
  }

  /// `{count} items have been selected`
  String selectedCountTitle(Object count) {
    return Intl.message(
      '$count items have been selected',
      name: 'selectedCountTitle',
      desc: '',
      args: [count],
    );
  }

  /// `Add rule`
  String get addRule {
    return Intl.message('Add rule', name: 'addRule', desc: '', args: []);
  }

  /// `Rule name`
  String get ruleName {
    return Intl.message('Rule name', name: 'ruleName', desc: '', args: []);
  }

  /// `Content`
  String get content {
    return Intl.message('Content', name: 'content', desc: '', args: []);
  }

  /// `Sub rule`
  String get subRule {
    return Intl.message('Sub rule', name: 'subRule', desc: '', args: []);
  }

  /// `Rule target`
  String get ruleTarget {
    return Intl.message('Rule target', name: 'ruleTarget', desc: '', args: []);
  }

  /// `Source IP`
  String get sourceIp {
    return Intl.message('Source IP', name: 'sourceIp', desc: '', args: []);
  }

  /// `No resolve IP`
  String get noResolve {
    return Intl.message('No resolve IP', name: 'noResolve', desc: '', args: []);
  }

  /// `Save changes`
  String get saveChanges {
    return Intl.message(
      'Save changes',
      name: 'saveChanges',
      desc: '',
      args: [],
    );
  }

  /// `There is a certain performance loss after opening`
  String get findProcessModeDesc {
    return Intl.message(
      'There is a certain performance loss after opening',
      name: 'findProcessModeDesc',
      desc: '',
      args: [],
    );
  }

  /// `Effective only in mobile view`
  String get tabAnimationDesc {
    return Intl.message(
      'Effective only in mobile view',
      name: 'tabAnimationDesc',
      desc: '',
      args: [],
    );
  }

  /// `Color schemes`
  String get colorSchemes {
    return Intl.message(
      'Color schemes',
      name: 'colorSchemes',
      desc: '',
      args: [],
    );
  }

  /// `Palette`
  String get palette {
    return Intl.message('Palette', name: 'palette', desc: '', args: []);
  }

  /// `TonalSpot`
  String get tonalSpotScheme {
    return Intl.message(
      'TonalSpot',
      name: 'tonalSpotScheme',
      desc: '',
      args: [],
    );
  }

  /// `Fidelity`
  String get fidelityScheme {
    return Intl.message('Fidelity', name: 'fidelityScheme', desc: '', args: []);
  }

  /// `Monochrome`
  String get monochromeScheme {
    return Intl.message(
      'Monochrome',
      name: 'monochromeScheme',
      desc: '',
      args: [],
    );
  }

  /// `Neutral`
  String get neutralScheme {
    return Intl.message('Neutral', name: 'neutralScheme', desc: '', args: []);
  }

  /// `Vibrant`
  String get vibrantScheme {
    return Intl.message('Vibrant', name: 'vibrantScheme', desc: '', args: []);
  }

  /// `Expressive`
  String get expressiveScheme {
    return Intl.message(
      'Expressive',
      name: 'expressiveScheme',
      desc: '',
      args: [],
    );
  }

  /// `Content`
  String get contentScheme {
    return Intl.message('Content', name: 'contentScheme', desc: '', args: []);
  }

  /// `Rainbow`
  String get rainbowScheme {
    return Intl.message('Rainbow', name: 'rainbowScheme', desc: '', args: []);
  }

  /// `FruitSalad`
  String get fruitSaladScheme {
    return Intl.message(
      'FruitSalad',
      name: 'fruitSaladScheme',
      desc: '',
      args: [],
    );
  }

  /// `Developer mode`
  String get developerMode {
    return Intl.message(
      'Developer mode',
      name: 'developerMode',
      desc: '',
      args: [],
    );
  }

  /// `Developer mode is enabled.`
  String get developerModeEnableTip {
    return Intl.message(
      'Developer mode is enabled.',
      name: 'developerModeEnableTip',
      desc: '',
      args: [],
    );
  }

  /// `Message test`
  String get messageTest {
    return Intl.message(
      'Message test',
      name: 'messageTest',
      desc: '',
      args: [],
    );
  }

  /// `This is a message.`
  String get messageTestTip {
    return Intl.message(
      'This is a message.',
      name: 'messageTestTip',
      desc: '',
      args: [],
    );
  }

  /// `Crash test`
  String get crashTest {
    return Intl.message('Crash test', name: 'crashTest', desc: '', args: []);
  }

  /// `Crash detected`
  String get crashDetected {
    return Intl.message(
      'Crash detected',
      name: 'crashDetected',
      desc: '',
      args: [],
    );
  }

  /// `The app crashed during the previous run. To prevent repeated crashes, the current profile has been cleared and automatic configuration setup was skipped.`
  String get crashDetectedTip {
    return Intl.message(
      'The app crashed during the previous run. To prevent repeated crashes, the current profile has been cleared and automatic configuration setup was skipped.',
      name: 'crashDetectedTip',
      desc: '',
      args: [],
    );
  }

  /// `Clear Data`
  String get clearData {
    return Intl.message('Clear Data', name: 'clearData', desc: '', args: []);
  }

  /// `Text Scaling`
  String get textScale {
    return Intl.message('Text Scaling', name: 'textScale', desc: '', args: []);
  }

  /// `Internet`
  String get internet {
    return Intl.message('Internet', name: 'internet', desc: '', args: []);
  }

  /// `System APP`
  String get systemApp {
    return Intl.message('System APP', name: 'systemApp', desc: '', args: []);
  }

  /// `No network APP`
  String get noNetworkApp {
    return Intl.message(
      'No network APP',
      name: 'noNetworkApp',
      desc: '',
      args: [],
    );
  }

  /// `Restore strategy`
  String get restoreStrategy {
    return Intl.message(
      'Restore strategy',
      name: 'restoreStrategy',
      desc: '',
      args: [],
    );
  }

  /// `Override`
  String get restoreStrategy_override {
    return Intl.message(
      'Override',
      name: 'restoreStrategy_override',
      desc: '',
      args: [],
    );
  }

  /// `Compatible`
  String get restoreStrategy_compatible {
    return Intl.message(
      'Compatible',
      name: 'restoreStrategy_compatible',
      desc: '',
      args: [],
    );
  }

  /// `Logs test`
  String get logsTest {
    return Intl.message('Logs test', name: 'logsTest', desc: '', args: []);
  }

  /// `{label} cannot be empty`
  String emptyTip(Object label) {
    return Intl.message(
      '$label cannot be empty',
      name: 'emptyTip',
      desc: '',
      args: [label],
    );
  }

  /// `{label} must be a url`
  String urlTip(Object label) {
    return Intl.message(
      '$label must be a url',
      name: 'urlTip',
      desc: '',
      args: [label],
    );
  }

  /// `{label} must be a number`
  String numberTip(Object label) {
    return Intl.message(
      '$label must be a number',
      name: 'numberTip',
      desc: '',
      args: [label],
    );
  }

  /// `Interval`
  String get interval {
    return Intl.message('Interval', name: 'interval', desc: '', args: []);
  }

  /// `Current {label} already exists`
  String existsTip(Object label) {
    return Intl.message(
      'Current $label already exists',
      name: 'existsTip',
      desc: '',
      args: [label],
    );
  }

  /// `Are you sure you want to delete the current {label}?`
  String deleteTip(Object label) {
    return Intl.message(
      'Are you sure you want to delete the current $label?',
      name: 'deleteTip',
      desc: '',
      args: [label],
    );
  }

  /// `Are you sure you want to delete the selected {label}?`
  String deleteMultipTip(Object label) {
    return Intl.message(
      'Are you sure you want to delete the selected $label?',
      name: 'deleteMultipTip',
      desc: '',
      args: [label],
    );
  }

  /// `No {label} yet`
  String nullTip(Object label) {
    return Intl.message(
      'No $label yet',
      name: 'nullTip',
      desc: '',
      args: [label],
    );
  }

  /// `Script`
  String get script {
    return Intl.message('Script', name: 'script', desc: '', args: []);
  }

  /// `Color`
  String get color {
    return Intl.message('Color', name: 'color', desc: '', args: []);
  }

  /// `Rename`
  String get rename {
    return Intl.message('Rename', name: 'rename', desc: '', args: []);
  }

  /// `Unnamed`
  String get unnamed {
    return Intl.message('Unnamed', name: 'unnamed', desc: '', args: []);
  }

  /// `Please enter a script name`
  String get pleaseEnterScriptName {
    return Intl.message(
      'Please enter a script name',
      name: 'pleaseEnterScriptName',
      desc: '',
      args: [],
    );
  }

  /// `Mixed Port`
  String get mixedPort {
    return Intl.message('Mixed Port', name: 'mixedPort', desc: '', args: []);
  }

  /// `Socks Port`
  String get socksPort {
    return Intl.message('Socks Port', name: 'socksPort', desc: '', args: []);
  }

  /// `Redir Port`
  String get redirPort {
    return Intl.message('Redir Port', name: 'redirPort', desc: '', args: []);
  }

  /// `Tproxy Port`
  String get tproxyPort {
    return Intl.message('Tproxy Port', name: 'tproxyPort', desc: '', args: []);
  }

  /// `{label} must be between 1024 and 49151`
  String portTip(Object label) {
    return Intl.message(
      '$label must be between 1024 and 49151',
      name: 'portTip',
      desc: '',
      args: [label],
    );
  }

  /// `Please enter a different port`
  String get portConflictTip {
    return Intl.message(
      'Please enter a different port',
      name: 'portConflictTip',
      desc: '',
      args: [],
    );
  }

  /// `Import`
  String get import {
    return Intl.message('Import', name: 'import', desc: '', args: []);
  }

  /// `Import from file`
  String get importFile {
    return Intl.message(
      'Import from file',
      name: 'importFile',
      desc: '',
      args: [],
    );
  }

  /// `Import from URL`
  String get importUrl {
    return Intl.message(
      'Import from URL',
      name: 'importUrl',
      desc: '',
      args: [],
    );
  }

  /// `Auto set system DNS`
  String get autoSetSystemDns {
    return Intl.message(
      'Auto set system DNS',
      name: 'autoSetSystemDns',
      desc: '',
      args: [],
    );
  }

  /// `{label} details`
  String details(Object label) {
    return Intl.message(
      '$label details',
      name: 'details',
      desc: '',
      args: [label],
    );
  }

  /// `Creation time`
  String get creationTime {
    return Intl.message(
      'Creation time',
      name: 'creationTime',
      desc: '',
      args: [],
    );
  }

  /// `Process`
  String get process {
    return Intl.message('Process', name: 'process', desc: '', args: []);
  }

  /// `Host`
  String get host {
    return Intl.message('Host', name: 'host', desc: '', args: []);
  }

  /// `Destination`
  String get destination {
    return Intl.message('Destination', name: 'destination', desc: '', args: []);
  }

  /// `Destination GeoIP`
  String get destinationGeoIP {
    return Intl.message(
      'Destination GeoIP',
      name: 'destinationGeoIP',
      desc: '',
      args: [],
    );
  }

  /// `Destination IPASN`
  String get destinationIPASN {
    return Intl.message(
      'Destination IPASN',
      name: 'destinationIPASN',
      desc: '',
      args: [],
    );
  }

  /// `Special proxy`
  String get specialProxy {
    return Intl.message(
      'Special proxy',
      name: 'specialProxy',
      desc: '',
      args: [],
    );
  }

  /// `special rules`
  String get specialRules {
    return Intl.message(
      'special rules',
      name: 'specialRules',
      desc: '',
      args: [],
    );
  }

  /// `Remote destination`
  String get remoteDestination {
    return Intl.message(
      'Remote destination',
      name: 'remoteDestination',
      desc: '',
      args: [],
    );
  }

  /// `Network type`
  String get networkType {
    return Intl.message(
      'Network type',
      name: 'networkType',
      desc: '',
      args: [],
    );
  }

  /// `Proxy chains`
  String get proxyChains {
    return Intl.message(
      'Proxy chains',
      name: 'proxyChains',
      desc: '',
      args: [],
    );
  }

  /// `Log`
  String get log {
    return Intl.message('Log', name: 'log', desc: '', args: []);
  }

  /// `Connection`
  String get connection {
    return Intl.message('Connection', name: 'connection', desc: '', args: []);
  }

  /// `Request`
  String get request {
    return Intl.message('Request', name: 'request', desc: '', args: []);
  }

  /// `Connected`
  String get connected {
    return Intl.message('Connected', name: 'connected', desc: '', args: []);
  }

  /// `Disconnected`
  String get disconnected {
    return Intl.message(
      'Disconnected',
      name: 'disconnected',
      desc: '',
      args: [],
    );
  }

  /// `Connecting...`
  String get connecting {
    return Intl.message(
      'Connecting...',
      name: 'connecting',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to restart the core?`
  String get restartCoreTip {
    return Intl.message(
      'Are you sure you want to restart the core?',
      name: 'restartCoreTip',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to force restart the core?`
  String get forceRestartCoreTip {
    return Intl.message(
      'Are you sure you want to force restart the core?',
      name: 'forceRestartCoreTip',
      desc: '',
      args: [],
    );
  }

  /// `DNS hijacking`
  String get dnsHijacking {
    return Intl.message(
      'DNS hijacking',
      name: 'dnsHijacking',
      desc: '',
      args: [],
    );
  }

  /// `Core status`
  String get coreStatus {
    return Intl.message('Core status', name: 'coreStatus', desc: '', args: []);
  }

  /// `Data Collection Notice`
  String get dataCollectionTip {
    return Intl.message(
      'Data Collection Notice',
      name: 'dataCollectionTip',
      desc: '',
      args: [],
    );
  }

  /// `This app uses Firebase Crashlytics to collect crash information to improve app stability.\nThe collected data includes device information and crash details, but does not contain personal sensitive data.\nYou can disable this feature in settings.`
  String get dataCollectionContent {
    return Intl.message(
      'This app uses Firebase Crashlytics to collect crash information to improve app stability.\nThe collected data includes device information and crash details, but does not contain personal sensitive data.\nYou can disable this feature in settings.',
      name: 'dataCollectionContent',
      desc: '',
      args: [],
    );
  }

  /// `Crash Analysis`
  String get crashlytics {
    return Intl.message(
      'Crash Analysis',
      name: 'crashlytics',
      desc: '',
      args: [],
    );
  }

  /// `When enabled, automatically uploads crash logs without sensitive information when the app crashes`
  String get crashlyticsTip {
    return Intl.message(
      'When enabled, automatically uploads crash logs without sensitive information when the app crashes',
      name: 'crashlyticsTip',
      desc: '',
      args: [],
    );
  }

  /// `Append System DNS`
  String get appendSystemDns {
    return Intl.message(
      'Append System DNS',
      name: 'appendSystemDns',
      desc: '',
      args: [],
    );
  }

  /// `Forcefully append system DNS to the configuration`
  String get appendSystemDnsTip {
    return Intl.message(
      'Forcefully append system DNS to the configuration',
      name: 'appendSystemDnsTip',
      desc: '',
      args: [],
    );
  }

  /// `Edit rule`
  String get editRule {
    return Intl.message('Edit rule', name: 'editRule', desc: '', args: []);
  }

  /// `Override mode`
  String get overrideMode {
    return Intl.message(
      'Override mode',
      name: 'overrideMode',
      desc: '',
      args: [],
    );
  }

  /// `Standard mode, override basic configuration, provide simple rule addition capability`
  String get standardModeDesc {
    return Intl.message(
      'Standard mode, override basic configuration, provide simple rule addition capability',
      name: 'standardModeDesc',
      desc: '',
      args: [],
    );
  }

  /// `Script mode, use external extension scripts, provide one-click override configuration capability`
  String get scriptModeDesc {
    return Intl.message(
      'Script mode, use external extension scripts, provide one-click override configuration capability',
      name: 'scriptModeDesc',
      desc: '',
      args: [],
    );
  }

  /// `Added rules`
  String get addedRules {
    return Intl.message('Added rules', name: 'addedRules', desc: '', args: []);
  }

  /// `Control global added rules`
  String get controlGlobalAddedRules {
    return Intl.message(
      'Control global added rules',
      name: 'controlGlobalAddedRules',
      desc: '',
      args: [],
    );
  }

  /// `Override script`
  String get overrideScript {
    return Intl.message(
      'Override script',
      name: 'overrideScript',
      desc: '',
      args: [],
    );
  }

  /// `Go to configure script`
  String get goToConfigureScript {
    return Intl.message(
      'Go to configure script',
      name: 'goToConfigureScript',
      desc: '',
      args: [],
    );
  }

  /// `Edit global rules`
  String get editGlobalRules {
    return Intl.message(
      'Edit global rules',
      name: 'editGlobalRules',
      desc: '',
      args: [],
    );
  }

  /// `External fetch`
  String get externalFetch {
    return Intl.message(
      'External fetch',
      name: 'externalFetch',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to force crash the core?`
  String get confirmForceCrashCore {
    return Intl.message(
      'Are you sure you want to force crash the core?',
      name: 'confirmForceCrashCore',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to clear all data?`
  String get confirmClearAllData {
    return Intl.message(
      'Are you sure you want to clear all data?',
      name: 'confirmClearAllData',
      desc: '',
      args: [],
    );
  }

  /// `Loading...`
  String get loading {
    return Intl.message('Loading...', name: 'loading', desc: '', args: []);
  }

  /// `Load test`
  String get loadTest {
    return Intl.message('Load test', name: 'loadTest', desc: '', args: []);
  }

  /// `{count, plural, =1{1 year ago} other{{count} years ago}}`
  String yearsAgo(num count) {
    return Intl.plural(
      count,
      one: '1 year ago',
      other: '$count years ago',
      name: 'yearsAgo',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 month ago} other{{count} months ago}}`
  String monthsAgo(num count) {
    return Intl.plural(
      count,
      one: '1 month ago',
      other: '$count months ago',
      name: 'monthsAgo',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 day ago} other{{count} days ago}}`
  String daysAgo(num count) {
    return Intl.plural(
      count,
      one: '1 day ago',
      other: '$count days ago',
      name: 'daysAgo',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 hour ago} other{{count} hours ago}}`
  String hoursAgo(num count) {
    return Intl.plural(
      count,
      one: '1 hour ago',
      other: '$count hours ago',
      name: 'hoursAgo',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 minute ago} other{{count} minutes ago}}`
  String minutesAgo(num count) {
    return Intl.plural(
      count,
      one: '1 minute ago',
      other: '$count minutes ago',
      name: 'minutesAgo',
      desc: '',
      args: [count],
    );
  }

  /// `Just now`
  String get justNow {
    return Intl.message('Just now', name: 'justNow', desc: '', args: []);
  }

  /// `Don't remind again`
  String get noLongerRemind {
    return Intl.message(
      'Don\'t remind again',
      name: 'noLongerRemind',
      desc: '',
      args: [],
    );
  }

  /// `Access Control Settings`
  String get accessControlSettings {
    return Intl.message(
      'Access Control Settings',
      name: 'accessControlSettings',
      desc: '',
      args: [],
    );
  }

  /// `Turn On`
  String get turnOn {
    return Intl.message('Turn On', name: 'turnOn', desc: '', args: []);
  }

  /// `Turn Off`
  String get turnOff {
    return Intl.message('Turn Off', name: 'turnOff', desc: '', args: []);
  }

  /// `VPN configuration change detected`
  String get vpnConfigChangeDetected {
    return Intl.message(
      'VPN configuration change detected',
      name: 'vpnConfigChangeDetected',
      desc: '',
      args: [],
    );
  }

  /// `Restart`
  String get restart {
    return Intl.message('Restart', name: 'restart', desc: '', args: []);
  }

  /// `Speed statistics`
  String get speedStatistics {
    return Intl.message(
      'Speed statistics',
      name: 'speedStatistics',
      desc: '',
      args: [],
    );
  }

  /// `The current page has changes. Are you sure you want to reset?`
  String get resetPageChangesTip {
    return Intl.message(
      'The current page has changes. Are you sure you want to reset?',
      name: 'resetPageChangesTip',
      desc: '',
      args: [],
    );
  }

  /// `Custom`
  String get overwriteTypeCustom {
    return Intl.message(
      'Custom',
      name: 'overwriteTypeCustom',
      desc: '',
      args: [],
    );
  }

  /// `Custom mode, fully customize proxy groups and rules`
  String get overwriteTypeCustomDesc {
    return Intl.message(
      'Custom mode, fully customize proxy groups and rules',
      name: 'overwriteTypeCustomDesc',
      desc: '',
      args: [],
    );
  }

  /// `Unknown network error`
  String get unknownNetworkError {
    return Intl.message(
      'Unknown network error',
      name: 'unknownNetworkError',
      desc: '',
      args: [],
    );
  }

  /// `Recovery exception`
  String get restoreException {
    return Intl.message(
      'Recovery exception',
      name: 'restoreException',
      desc: '',
      args: [],
    );
  }

  /// `Network exception, please check your connection and try again`
  String get networkException {
    return Intl.message(
      'Network exception, please check your connection and try again',
      name: 'networkException',
      desc: '',
      args: [],
    );
  }

  /// `Invalid backup file`
  String get invalidBackupFile {
    return Intl.message(
      'Invalid backup file',
      name: 'invalidBackupFile',
      desc: '',
      args: [],
    );
  }

  /// `Prune cache`
  String get pruneCache {
    return Intl.message('Prune cache', name: 'pruneCache', desc: '', args: []);
  }

  /// `Backup and Restore`
  String get backupAndRestore {
    return Intl.message(
      'Backup and Restore',
      name: 'backupAndRestore',
      desc: '',
      args: [],
    );
  }

  /// `Sync data via WebDAV or files`
  String get backupAndRestoreDesc {
    return Intl.message(
      'Sync data via WebDAV or files',
      name: 'backupAndRestoreDesc',
      desc: '',
      args: [],
    );
  }

  /// `Restore`
  String get restore {
    return Intl.message('Restore', name: 'restore', desc: '', args: []);
  }

  /// `Restore success`
  String get restoreSuccess {
    return Intl.message(
      'Restore success',
      name: 'restoreSuccess',
      desc: '',
      args: [],
    );
  }

  /// `Restore data via WebDAV`
  String get restoreFromWebDAVDesc {
    return Intl.message(
      'Restore data via WebDAV',
      name: 'restoreFromWebDAVDesc',
      desc: '',
      args: [],
    );
  }

  /// `Restore data via file`
  String get restoreFromFileDesc {
    return Intl.message(
      'Restore data via file',
      name: 'restoreFromFileDesc',
      desc: '',
      args: [],
    );
  }

  /// `Restore configuration files only`
  String get restoreOnlyConfig {
    return Intl.message(
      'Restore configuration files only',
      name: 'restoreOnlyConfig',
      desc: '',
      args: [],
    );
  }

  /// `Restore all data`
  String get restoreAllData {
    return Intl.message(
      'Restore all data',
      name: 'restoreAllData',
      desc: '',
      args: [],
    );
  }

  /// `Add Profile`
  String get addProfile {
    return Intl.message('Add Profile', name: 'addProfile', desc: '', args: []);
  }

  /// `Delay Test`
  String get delayTest {
    return Intl.message('Delay Test', name: 'delayTest', desc: '', args: []);
  }

  /// `Proxy group is empty`
  String get proxyGroupEmpty {
    return Intl.message(
      'Proxy group is empty',
      name: 'proxyGroupEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Proxy group name cannot be empty`
  String get proxyGroupNameEmpty {
    return Intl.message(
      'Proxy group name cannot be empty',
      name: 'proxyGroupNameEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Proxy group name is duplicate`
  String get proxyGroupNameDuplicate {
    return Intl.message(
      'Proxy group name is duplicate',
      name: 'proxyGroupNameDuplicate',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to exit the current window?`
  String get confirmExitWindow {
    return Intl.message(
      'Are you sure you want to exit the current window?',
      name: 'confirmExitWindow',
      desc: '',
      args: [],
    );
  }

  /// `Data changes detected, do you want to save?`
  String get dataChangedSave {
    return Intl.message(
      'Data changes detected, do you want to save?',
      name: 'dataChangedSave',
      desc: '',
      args: [],
    );
  }

  /// `Select proxy providers`
  String get selectProxyProviders {
    return Intl.message(
      'Select proxy providers',
      name: 'selectProxyProviders',
      desc: '',
      args: [],
    );
  }

  /// `Proxy filter`
  String get proxyFilter {
    return Intl.message(
      'Proxy filter',
      name: 'proxyFilter',
      desc: '',
      args: [],
    );
  }

  /// `Optional`
  String get optional {
    return Intl.message('Optional', name: 'optional', desc: '', args: []);
  }

  /// `Max failed times`
  String get maxFailedTimes {
    return Intl.message(
      'Max failed times',
      name: 'maxFailedTimes',
      desc: '',
      args: [],
    );
  }

  /// `Test interval`
  String get testInterval {
    return Intl.message(
      'Test interval',
      name: 'testInterval',
      desc: '',
      args: [],
    );
  }

  /// `Exclude proxy filter`
  String get excludeProxyFilter {
    return Intl.message(
      'Exclude proxy filter',
      name: 'excludeProxyFilter',
      desc: '',
      args: [],
    );
  }

  /// `Exclude type`
  String get excludeType {
    return Intl.message(
      'Exclude type',
      name: 'excludeType',
      desc: '',
      args: [],
    );
  }

  /// `Expected status`
  String get expectedStatus {
    return Intl.message(
      'Expected status',
      name: 'expectedStatus',
      desc: '',
      args: [],
    );
  }

  /// `Select proxies`
  String get selectProxies {
    return Intl.message(
      'Select proxies',
      name: 'selectProxies',
      desc: '',
      args: [],
    );
  }

  /// `Input proxy group name`
  String get inputProxyGroupName {
    return Intl.message(
      'Input proxy group name',
      name: 'inputProxyGroupName',
      desc: '',
      args: [],
    );
  }

  /// `Helper service unavailable; TUN mode cannot be enabled. Reinstall FlClash to restore it.`
  String get helperCorruptTip {
    return Intl.message(
      'Helper service unavailable; TUN mode cannot be enabled. Reinstall FlClash to restore it.',
      name: 'helperCorruptTip',
      desc: '',
      args: [],
    );
  }

  /// `Hide from list`
  String get hideFromList {
    return Intl.message(
      'Hide from list',
      name: 'hideFromList',
      desc: '',
      args: [],
    );
  }

  /// `Test when used`
  String get testWhenUsed {
    return Intl.message(
      'Test when used',
      name: 'testWhenUsed',
      desc: '',
      args: [],
    );
  }

  /// `Disable UDP`
  String get disableUDP {
    return Intl.message('Disable UDP', name: 'disableUDP', desc: '', args: []);
  }

  /// `Are you sure you want to delete the current proxy group?`
  String get confirmDeleteProxyGroup {
    return Intl.message(
      'Are you sure you want to delete the current proxy group?',
      name: 'confirmDeleteProxyGroup',
      desc: '',
      args: [],
    );
  }

  /// `Rule is empty`
  String get ruleEmpty {
    return Intl.message('Rule is empty', name: 'ruleEmpty', desc: '', args: []);
  }

  /// `Input rule content`
  String get inputRuleContent {
    return Intl.message(
      'Input rule content',
      name: 'inputRuleContent',
      desc: '',
      args: [],
    );
  }

  /// `Rule set`
  String get ruleSet {
    return Intl.message('Rule set', name: 'ruleSet', desc: '', args: []);
  }

  /// `Please select rule set`
  String get selectRuleSet {
    return Intl.message(
      'Please select rule set',
      name: 'selectRuleSet',
      desc: '',
      args: [],
    );
  }

  /// `Split strategy`
  String get splitStrategy {
    return Intl.message(
      'Split strategy',
      name: 'splitStrategy',
      desc: '',
      args: [],
    );
  }

  /// `Please select split strategy`
  String get selectSplitStrategy {
    return Intl.message(
      'Please select split strategy',
      name: 'selectSplitStrategy',
      desc: '',
      args: [],
    );
  }

  /// `Please select sub rule`
  String get selectSubRule {
    return Intl.message(
      'Please select sub rule',
      name: 'selectSubRule',
      desc: '',
      args: [],
    );
  }

  /// `No resolve hostname`
  String get noResolveHostname {
    return Intl.message(
      'No resolve hostname',
      name: 'noResolveHostname',
      desc: '',
      args: [],
    );
  }

  /// `Match source IP`
  String get matchSourceIp {
    return Intl.message(
      'Match source IP',
      name: 'matchSourceIp',
      desc: '',
      args: [],
    );
  }

  /// `Basic info`
  String get basicInfo {
    return Intl.message('Basic info', name: 'basicInfo', desc: '', args: []);
  }

  /// `Additional parameters`
  String get additionalParameters {
    return Intl.message(
      'Additional parameters',
      name: 'additionalParameters',
      desc: '',
      args: [],
    );
  }

  /// `Proxy type`
  String get proxyType {
    return Intl.message('Proxy type', name: 'proxyType', desc: '', args: []);
  }

  /// `Basic strategy`
  String get basicStrategy {
    return Intl.message(
      'Basic strategy',
      name: 'basicStrategy',
      desc: '',
      args: [],
    );
  }

  /// `Edit proxy`
  String get editProxy {
    return Intl.message('Edit proxy', name: 'editProxy', desc: '', args: []);
  }

  /// `Include all proxy providers`
  String get includeAllProxyProviders {
    return Intl.message(
      'Include all proxy providers',
      name: 'includeAllProxyProviders',
      desc: '',
      args: [],
    );
  }

  /// `When enabled, it will override the imported proxy providers`
  String get includeAllProxyProvidersTip {
    return Intl.message(
      'When enabled, it will override the imported proxy providers',
      name: 'includeAllProxyProvidersTip',
      desc: '',
      args: [],
    );
  }

  /// `Add proxy providers`
  String get addProxyProviders {
    return Intl.message(
      'Add proxy providers',
      name: 'addProxyProviders',
      desc: '',
      args: [],
    );
  }

  /// `Include all proxies`
  String get includeAllProxies {
    return Intl.message(
      'Include all proxies',
      name: 'includeAllProxies',
      desc: '',
      args: [],
    );
  }

  /// `Import all proxies not containing proxy groups, additional proxy groups can be added below`
  String get includeAllProxiesTip {
    return Intl.message(
      'Import all proxies not containing proxy groups, additional proxy groups can be added below',
      name: 'includeAllProxiesTip',
      desc: '',
      args: [],
    );
  }

  /// `Proxies is empty`
  String get proxiesEmpty {
    return Intl.message(
      'Proxies is empty',
      name: 'proxiesEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Add proxies`
  String get addProxies {
    return Intl.message('Add proxies', name: 'addProxies', desc: '', args: []);
  }

  /// `Add proxy group`
  String get addProxyGroup {
    return Intl.message(
      'Add proxy group',
      name: 'addProxyGroup',
      desc: '',
      args: [],
    );
  }

  /// `Edit proxy group`
  String get editProxyGroup {
    return Intl.message(
      'Edit proxy group',
      name: 'editProxyGroup',
      desc: '',
      args: [],
    );
  }

  /// `Existing data will be overwritten after confirmation`
  String get confirmOverwriteTip {
    return Intl.message(
      'Existing data will be overwritten after confirmation',
      name: 'confirmOverwriteTip',
      desc: '',
      args: [],
    );
  }

  /// `Data detected in configuration`
  String get configDataDetected {
    return Intl.message(
      'Data detected in configuration',
      name: 'configDataDetected',
      desc: '',
      args: [],
    );
  }

  /// `Quick fill`
  String get quickFill {
    return Intl.message('Quick fill', name: 'quickFill', desc: '', args: []);
  }

  /// `Icon URL`
  String get iconUrl {
    return Intl.message('Icon URL', name: 'iconUrl', desc: '', args: []);
  }

  /// `Icon records`
  String get iconRecords {
    return Intl.message(
      'Icon records',
      name: 'iconRecords',
      desc: '',
      args: [],
    );
  }

  /// `No records`
  String get noRecords {
    return Intl.message('No records', name: 'noRecords', desc: '', args: []);
  }

  /// `Custom`
  String get custom {
    return Intl.message('Custom', name: 'custom', desc: '', args: []);
  }

  /// `Match full domain`
  String get ruleActionDomainDesc {
    return Intl.message(
      'Match full domain',
      name: 'ruleActionDomainDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match domain suffix`
  String get ruleActionDomainSuffixDesc {
    return Intl.message(
      'Match domain suffix',
      name: 'ruleActionDomainSuffixDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match domain keyword`
  String get ruleActionDomainKeywordDesc {
    return Intl.message(
      'Match domain keyword',
      name: 'ruleActionDomainKeywordDesc',
      desc: '',
      args: [],
    );
  }

  /// `Wildcard match, only supports * and ? wildcards`
  String get ruleActionDomainRegexDesc {
    return Intl.message(
      'Wildcard match, only supports * and ? wildcards',
      name: 'ruleActionDomainRegexDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match domains within Geosite`
  String get ruleActionGeositeDesc {
    return Intl.message(
      'Match domains within Geosite',
      name: 'ruleActionGeositeDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match IP address range`
  String get ruleActionIpCidrDesc {
    return Intl.message(
      'Match IP address range',
      name: 'ruleActionIpCidrDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match IP address range, IP-CIDR6 is just an alias`
  String get ruleActionIpCidr6Desc {
    return Intl.message(
      'Match IP address range, IP-CIDR6 is just an alias',
      name: 'ruleActionIpCidr6Desc',
      desc: '',
      args: [],
    );
  }

  /// `Match IP suffix range`
  String get ruleActionIpSuffixDesc {
    return Intl.message(
      'Match IP suffix range',
      name: 'ruleActionIpSuffixDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match IP's ASN`
  String get ruleActionIpAsnDesc {
    return Intl.message(
      'Match IP\'s ASN',
      name: 'ruleActionIpAsnDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match IP's country code`
  String get ruleActionGeoipDesc {
    return Intl.message(
      'Match IP\'s country code',
      name: 'ruleActionGeoipDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match source IP's country code`
  String get ruleActionSrcGeoipDesc {
    return Intl.message(
      'Match source IP\'s country code',
      name: 'ruleActionSrcGeoipDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match source IP's ASN`
  String get ruleActionSrcIpAsnDesc {
    return Intl.message(
      'Match source IP\'s ASN',
      name: 'ruleActionSrcIpAsnDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match source IP address range`
  String get ruleActionSrcIpCidrDesc {
    return Intl.message(
      'Match source IP address range',
      name: 'ruleActionSrcIpCidrDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match source IP suffix range`
  String get ruleActionSrcIpSuffixDesc {
    return Intl.message(
      'Match source IP suffix range',
      name: 'ruleActionSrcIpSuffixDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match request target port range`
  String get ruleActionDstPortDesc {
    return Intl.message(
      'Match request target port range',
      name: 'ruleActionDstPortDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match request source port range`
  String get ruleActionSrcPortDesc {
    return Intl.message(
      'Match request source port range',
      name: 'ruleActionSrcPortDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match inbound port`
  String get ruleActionInPortDesc {
    return Intl.message(
      'Match inbound port',
      name: 'ruleActionInPortDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match inbound type`
  String get ruleActionInTypeDesc {
    return Intl.message(
      'Match inbound type',
      name: 'ruleActionInTypeDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match inbound username, supports multiple usernames separated by /`
  String get ruleActionInUserDesc {
    return Intl.message(
      'Match inbound username, supports multiple usernames separated by /',
      name: 'ruleActionInUserDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match inbound name`
  String get ruleActionInNameDesc {
    return Intl.message(
      'Match inbound name',
      name: 'ruleActionInNameDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match using full process path`
  String get ruleActionProcessPathDesc {
    return Intl.message(
      'Match using full process path',
      name: 'ruleActionProcessPathDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match using process path regex`
  String get ruleActionProcessPathRegexDesc {
    return Intl.message(
      'Match using process path regex',
      name: 'ruleActionProcessPathRegexDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match using process name, matches package name on Android`
  String get ruleActionProcessNameDesc {
    return Intl.message(
      'Match using process name, matches package name on Android',
      name: 'ruleActionProcessNameDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match using process name regex, matches package name on Android`
  String get ruleActionProcessNameRegexDesc {
    return Intl.message(
      'Match using process name regex, matches package name on Android',
      name: 'ruleActionProcessNameRegexDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match Linux USER ID`
  String get ruleActionUidDesc {
    return Intl.message(
      'Match Linux USER ID',
      name: 'ruleActionUidDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match TCP or UDP`
  String get ruleActionNetworkDesc {
    return Intl.message(
      'Match TCP or UDP',
      name: 'ruleActionNetworkDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match DSCP mark (tproxy udp inbound only)`
  String get ruleActionDscpDesc {
    return Intl.message(
      'Match DSCP mark (tproxy udp inbound only)',
      name: 'ruleActionDscpDesc',
      desc: '',
      args: [],
    );
  }

  /// `Reference rule set, requires rule-providers configuration`
  String get ruleActionRuleSetDesc {
    return Intl.message(
      'Reference rule set, requires rule-providers configuration',
      name: 'ruleActionRuleSetDesc',
      desc: '',
      args: [],
    );
  }

  /// `Logical rule AND`
  String get ruleActionAndDesc {
    return Intl.message(
      'Logical rule AND',
      name: 'ruleActionAndDesc',
      desc: '',
      args: [],
    );
  }

  /// `Logical rule OR`
  String get ruleActionOrDesc {
    return Intl.message(
      'Logical rule OR',
      name: 'ruleActionOrDesc',
      desc: '',
      args: [],
    );
  }

  /// `Logical rule NOT`
  String get ruleActionNotDesc {
    return Intl.message(
      'Logical rule NOT',
      name: 'ruleActionNotDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match to sub-rule, pay attention to the use of parentheses`
  String get ruleActionSubRuleDesc {
    return Intl.message(
      'Match to sub-rule, pay attention to the use of parentheses',
      name: 'ruleActionSubRuleDesc',
      desc: '',
      args: [],
    );
  }

  /// `Match all requests, no conditions needed`
  String get ruleActionMatchDesc {
    return Intl.message(
      'Match all requests, no conditions needed',
      name: 'ruleActionMatchDesc',
      desc: '',
      args: [],
    );
  }

  /// `Sub rule is empty`
  String get subRuleEmpty {
    return Intl.message(
      'Sub rule is empty',
      name: 'subRuleEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Proxy providers cannot be empty`
  String get proxyProvidersNotEmpty {
    return Intl.message(
      'Proxy providers cannot be empty',
      name: 'proxyProvidersNotEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Content cannot be empty`
  String get contentNotEmpty {
    return Intl.message(
      'Content cannot be empty',
      name: 'contentNotEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Sub rule cannot be empty`
  String get subRuleNotEmpty {
    return Intl.message(
      'Sub rule cannot be empty',
      name: 'subRuleNotEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Split strategy cannot be empty`
  String get splitStrategyNotEmpty {
    return Intl.message(
      'Split strategy cannot be empty',
      name: 'splitStrategyNotEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Proxy providers is empty`
  String get proxyProvidersEmpty {
    return Intl.message(
      'Proxy providers is empty',
      name: 'proxyProvidersEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Timeout`
  String get timeout {
    return Intl.message('Timeout', name: 'timeout', desc: '', args: []);
  }

  /// `{subRule} is an invalid SUB_RULE`
  String invalidSubRule(Object subRule) {
    return Intl.message(
      '$subRule is an invalid SUB_RULE',
      name: 'invalidSubRule',
      desc: '',
      args: [subRule],
    );
  }

  /// `{target} is an invalid policy`
  String invalidPolicy(Object target) {
    return Intl.message(
      '$target is an invalid policy',
      name: 'invalidPolicy',
      desc: '',
      args: [target],
    );
  }

  /// `{providerName} is an invalid proxy provider`
  String invalidProxyProvider(Object providerName) {
    return Intl.message(
      '$providerName is an invalid proxy provider',
      name: 'invalidProxyProvider',
      desc: '',
      args: [providerName],
    );
  }

  /// `{proxyName} is an invalid proxy`
  String invalidProxy(Object proxyName) {
    return Intl.message(
      '$proxyName is an invalid proxy',
      name: 'invalidProxy',
      desc: '',
      args: [proxyName],
    );
  }

  /// `Detected current proxy group is abnormal`
  String get proxyGroupDetectedAbnormal {
    return Intl.message(
      'Detected current proxy group is abnormal',
      name: 'proxyGroupDetectedAbnormal',
      desc: '',
      args: [],
    );
  }

  /// `Detected selected proxy providers are abnormal`
  String get proxyProviderDetectedAbnormal {
    return Intl.message(
      'Detected selected proxy providers are abnormal',
      name: 'proxyProviderDetectedAbnormal',
      desc: '',
      args: [],
    );
  }

  /// `Detected selected proxies are abnormal`
  String get proxyDetectedAbnormal {
    return Intl.message(
      'Detected selected proxies are abnormal',
      name: 'proxyDetectedAbnormal',
      desc: '',
      args: [],
    );
  }

  /// `Create Profile`
  String get createProfile {
    return Intl.message(
      'Create Profile',
      name: 'createProfile',
      desc: '',
      args: [],
    );
  }

  /// `Location Permission Required`
  String get locationPermissionRequired {
    return Intl.message(
      'Location Permission Required',
      name: 'locationPermissionRequired',
      desc: '',
      args: [],
    );
  }

  /// `1. Open System Settings > Privacy & Security\n2. Choose Location Services\n3. Find and check {appName} in the right list\n\nAfter completing the setup, return to the app and use it normally. Thank you for your cooperation.`
  String locationPermissionGuide(Object appName) {
    return Intl.message(
      '1. Open System Settings > Privacy & Security\n2. Choose Location Services\n3. Find and check $appName in the right list\n\nAfter completing the setup, return to the app and use it normally. Thank you for your cooperation.',
      name: 'locationPermissionGuide',
      desc: '',
      args: [appName],
    );
  }

  /// `Prerequisites`
  String get prerequisites {
    return Intl.message(
      'Prerequisites',
      name: 'prerequisites',
      desc: '',
      args: [],
    );
  }

  /// `Ignore Battery Optimization`
  String get ignoreBatteryOptimization {
    return Intl.message(
      'Ignore Battery Optimization',
      name: 'ignoreBatteryOptimization',
      desc: '',
      args: [],
    );
  }

  /// `To ensure background operation, please disable battery optimization for this app. Tap to go to settings.`
  String get batteryOptimizationDesc {
    return Intl.message(
      'To ensure background operation, please disable battery optimization for this app. Tap to go to settings.',
      name: 'batteryOptimizationDesc',
      desc: '',
      args: [],
    );
  }

  /// `Affected by the system, this status may not always be accurate.`
  String get batteryOptimizationStatusTip {
    return Intl.message(
      'Affected by the system, this status may not always be accurate.',
      name: 'batteryOptimizationStatusTip',
      desc: '',
      args: [],
    );
  }

  /// `Location Permission`
  String get locationPermission {
    return Intl.message(
      'Location Permission',
      name: 'locationPermission',
      desc: '',
      args: [],
    );
  }

  /// `According to system requirements, obtaining the Wi-Fi name requires you to grant location permission.`
  String get locationPermissionDesc {
    return Intl.message(
      'According to system requirements, obtaining the Wi-Fi name requires you to grant location permission.',
      name: 'locationPermissionDesc',
      desc: '',
      args: [],
    );
  }

  /// `Exclude SSIDs`
  String get excludeSsids {
    return Intl.message(
      'Exclude SSIDs',
      name: 'excludeSsids',
      desc: '',
      args: [],
    );
  }

  /// `When connected to an excluded SSID Wi-Fi, the app running state will be automatically switched.`
  String get excludeSsidsDesc {
    return Intl.message(
      'When connected to an excluded SSID Wi-Fi, the app running state will be automatically switched.',
      name: 'excludeSsidsDesc',
      desc: '',
      args: [],
    );
  }

  /// `SSIDs is empty`
  String get ssidsEmpty {
    return Intl.message(
      'SSIDs is empty',
      name: 'ssidsEmpty',
      desc: '',
      args: [],
    );
  }

  /// `On Demand`
  String get onDemand {
    return Intl.message('On Demand', name: 'onDemand', desc: '', args: []);
  }

  /// `Configure the program running state for specific scenarios`
  String get onDemandDesc {
    return Intl.message(
      'Configure the program running state for specific scenarios',
      name: 'onDemandDesc',
      desc: '',
      args: [],
    );
  }

  /// `Location permission was denied, so the current Wi-Fi name cannot be obtained. Please open location permission manually in system settings.`
  String get locationPermissionDeniedMessage {
    return Intl.message(
      'Location permission was denied, so the current Wi-Fi name cannot be obtained. Please open location permission manually in system settings.',
      name: 'locationPermissionDeniedMessage',
      desc: '',
      args: [],
    );
  }

  /// `Add SSID`
  String get addSsid {
    return Intl.message('Add SSID', name: 'addSsid', desc: '', args: []);
  }

  /// `Edit SSID`
  String get editSsid {
    return Intl.message('Edit SSID', name: 'editSsid', desc: '', args: []);
  }

  /// `Authorized`
  String get authorized {
    return Intl.message('Authorized', name: 'authorized', desc: '', args: []);
  }

  /// `Tap to authorize`
  String get tapToAuthorize {
    return Intl.message(
      'Tap to authorize',
      name: 'tapToAuthorize',
      desc: '',
      args: [],
    );
  }

  /// `Suspended...`
  String get suspended {
    return Intl.message('Suspended...', name: 'suspended', desc: '', args: []);
  }

  /// `Geo Options`
  String get geoOptions {
    return Intl.message('Geo Options', name: 'geoOptions', desc: '', args: []);
  }

  /// `Auto Update`
  String get geoAutoUpdate {
    return Intl.message(
      'Auto Update',
      name: 'geoAutoUpdate',
      desc: '',
      args: [],
    );
  }

  /// `Auto Update Interval`
  String get geoAutoUpdateInterval {
    return Intl.message(
      'Auto Update Interval',
      name: 'geoAutoUpdateInterval',
      desc: '',
      args: [],
    );
  }

  /// `Auto update interval must be greater than 0`
  String get geoAutoUpdateIntervalTip {
    return Intl.message(
      'Auto update interval must be greater than 0',
      name: 'geoAutoUpdateIntervalTip',
      desc: '',
      args: [],
    );
  }

  /// `hours`
  String get hours {
    return Intl.message('hours', name: 'hours', desc: '', args: []);
  }

  /// `{count} hours`
  String hoursCount(Object count) {
    return Intl.message(
      '$count hours',
      name: 'hoursCount',
      desc: '',
      args: [count],
    );
  }

  /// `Geo Resources`
  String get geoResources {
    return Intl.message(
      'Geo Resources',
      name: 'geoResources',
      desc: '',
      args: [],
    );
  }

  /// `Updating {name}...`
  String geoUpdating(Object name) {
    return Intl.message(
      'Updating $name...',
      name: 'geoUpdating',
      desc: '',
      args: [name],
    );
  }

  /// `{name} is already up to date`
  String geoSkipped(Object name) {
    return Intl.message(
      '$name is already up to date',
      name: 'geoSkipped',
      desc: '',
      args: [name],
    );
  }

  /// `{name} updated`
  String geoUpdated(Object name) {
    return Intl.message(
      '$name updated',
      name: 'geoUpdated',
      desc: '',
      args: [name],
    );
  }

  /// `{count} seconds`
  String secondsCount(Object count) {
    return Intl.message(
      '$count seconds',
      name: 'secondsCount',
      desc: '',
      args: [count],
    );
  }

  /// `{count} entries`
  String entriesCount(Object count) {
    return Intl.message(
      '$count entries',
      name: 'entriesCount',
      desc: '',
      args: [count],
    );
  }

  /// `FengWo Accelerator`
  String get brandName {
    return Intl.message(
      'FengWo Accelerator',
      name: 'brandName',
      desc: '',
      args: [],
    );
  }

  /// `Accelerator`
  String get acceleratorHome {
    return Intl.message(
      'Accelerator',
      name: 'acceleratorHome',
      desc: '',
      args: [],
    );
  }

  /// `Plans`
  String get purchasePlan {
    return Intl.message('Plans', name: 'purchasePlan', desc: '', args: []);
  }

  /// `Secure global access with fast, stable connections`
  String get planStoreSubtitle {
    return Intl.message(
      'Secure global access with fast, stable connections',
      name: 'planStoreSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `All`
  String get allPlans {
    return Intl.message('All', name: 'allPlans', desc: '', args: []);
  }

  /// `Recurring`
  String get recurringPlans {
    return Intl.message(
      'Recurring',
      name: 'recurringPlans',
      desc: '',
      args: [],
    );
  }

  /// `One-time`
  String get oneTimePlans {
    return Intl.message('One-time', name: 'oneTimePlans', desc: '', args: []);
  }

  /// `Current plan`
  String get currentPlanLabel {
    return Intl.message(
      'Current plan',
      name: 'currentPlanLabel',
      desc: '',
      args: [],
    );
  }

  /// `Monthly`
  String get monthlyBilling {
    return Intl.message('Monthly', name: 'monthlyBilling', desc: '', args: []);
  }

  /// `Quarterly`
  String get quarterlyBilling {
    return Intl.message(
      'Quarterly',
      name: 'quarterlyBilling',
      desc: '',
      args: [],
    );
  }

  /// `6 months`
  String get halfYearBilling {
    return Intl.message(
      '6 months',
      name: 'halfYearBilling',
      desc: '',
      args: [],
    );
  }

  /// `Yearly`
  String get yearlyBilling {
    return Intl.message('Yearly', name: 'yearlyBilling', desc: '', args: []);
  }

  /// `2 years`
  String get twoYearBilling {
    return Intl.message('2 years', name: 'twoYearBilling', desc: '', args: []);
  }

  /// `3 years`
  String get threeYearBilling {
    return Intl.message(
      '3 years',
      name: 'threeYearBilling',
      desc: '',
      args: [],
    );
  }

  /// `One-time`
  String get oneTimeBilling {
    return Intl.message('One-time', name: 'oneTimeBilling', desc: '', args: []);
  }

  /// `Reset`
  String get trafficResetBilling {
    return Intl.message(
      'Reset',
      name: 'trafficResetBilling',
      desc: '',
      args: [],
    );
  }

  /// `Traffic`
  String get planTrafficLabel {
    return Intl.message(
      'Traffic',
      name: 'planTrafficLabel',
      desc: '',
      args: [],
    );
  }

  /// `Speed`
  String get planSpeedLabel {
    return Intl.message('Speed', name: 'planSpeedLabel', desc: '', args: []);
  }

  /// `Devices`
  String get planDevicesLabel {
    return Intl.message(
      'Devices',
      name: 'planDevicesLabel',
      desc: '',
      args: [],
    );
  }

  /// `Unlimited`
  String get noLimit {
    return Intl.message('Unlimited', name: 'noLimit', desc: '', args: []);
  }

  /// `Buy now`
  String get buyNow {
    return Intl.message('Buy now', name: 'buyNow', desc: '', args: []);
  }

  /// `Free`
  String get freeLabel {
    return Intl.message('Free', name: 'freeLabel', desc: '', args: []);
  }

  /// `Sold out`
  String get soldOut {
    return Intl.message('Sold out', name: 'soldOut', desc: '', args: []);
  }

  /// `No plans are available right now`
  String get planCatalogEmpty {
    return Intl.message(
      'No plans are available right now',
      name: 'planCatalogEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Plans could not be loaded`
  String get planCatalogFailed {
    return Intl.message(
      'Plans could not be loaded',
      name: 'planCatalogFailed',
      desc: '',
      args: [],
    );
  }

  /// `Nodes`
  String get nodeStatus {
    return Intl.message('Nodes', name: 'nodeStatus', desc: '', args: []);
  }

  /// `Traffic`
  String get trafficDetails {
    return Intl.message('Traffic', name: 'trafficDetails', desc: '', args: []);
  }

  /// `My orders`
  String get myOrders {
    return Intl.message('My orders', name: 'myOrders', desc: '', args: []);
  }

  /// `My`
  String get mine {
    return Intl.message('My', name: 'mine', desc: '', args: []);
  }

  /// `Review plan and traffic-reset orders, payments, and activation status`
  String get orderCenterSubtitle {
    return Intl.message(
      'Review plan and traffic-reset orders, payments, and activation status',
      name: 'orderCenterSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `{count} orders`
  String totalOrders(Object count) {
    return Intl.message(
      '$count orders',
      name: 'totalOrders',
      desc: '',
      args: [count],
    );
  }

  /// `Period`
  String get orderPeriod {
    return Intl.message('Period', name: 'orderPeriod', desc: '', args: []);
  }

  /// `Amount`
  String get orderAmount {
    return Intl.message('Amount', name: 'orderAmount', desc: '', args: []);
  }

  /// `Plan`
  String get orderPlan {
    return Intl.message('Plan', name: 'orderPlan', desc: '', args: []);
  }

  /// `View details`
  String get viewOrderDetails {
    return Intl.message(
      'View details',
      name: 'viewOrderDetails',
      desc: '',
      args: [],
    );
  }

  /// `Cancel order`
  String get cancelOrder {
    return Intl.message(
      'Cancel order',
      name: 'cancelOrder',
      desc: '',
      args: [],
    );
  }

  /// `Cancel this order?`
  String get cancelOrderTitle {
    return Intl.message(
      'Cancel this order?',
      name: 'cancelOrderTitle',
      desc: '',
      args: [],
    );
  }

  /// `A cancelled order can no longer be paid. You can place a new order when needed.`
  String get cancelOrderMessage {
    return Intl.message(
      'A cancelled order can no longer be paid. You can place a new order when needed.',
      name: 'cancelOrderMessage',
      desc: '',
      args: [],
    );
  }

  /// `Order cancelled`
  String get orderCancelledSuccess {
    return Intl.message(
      'Order cancelled',
      name: 'orderCancelledSuccess',
      desc: '',
      args: [],
    );
  }

  /// `No orders yet`
  String get noOrders {
    return Intl.message('No orders yet', name: 'noOrders', desc: '', args: []);
  }

  /// `Unable to load orders`
  String get orderListFailed {
    return Intl.message(
      'Unable to load orders',
      name: 'orderListFailed',
      desc: '',
      args: [],
    );
  }

  /// `Order details`
  String get orderDetailsTitle {
    return Intl.message(
      'Order details',
      name: 'orderDetailsTitle',
      desc: '',
      args: [],
    );
  }

  /// `Pending payment`
  String get orderStatusPending {
    return Intl.message(
      'Pending payment',
      name: 'orderStatusPending',
      desc: '',
      args: [],
    );
  }

  /// `Activating`
  String get orderStatusProcessing {
    return Intl.message(
      'Activating',
      name: 'orderStatusProcessing',
      desc: '',
      args: [],
    );
  }

  /// `Cancelled`
  String get orderStatusCancelled {
    return Intl.message(
      'Cancelled',
      name: 'orderStatusCancelled',
      desc: '',
      args: [],
    );
  }

  /// `Completed`
  String get orderStatusCompleted {
    return Intl.message(
      'Completed',
      name: 'orderStatusCompleted',
      desc: '',
      args: [],
    );
  }

  /// `Unknown`
  String get orderStatusUnknown {
    return Intl.message(
      'Unknown',
      name: 'orderStatusUnknown',
      desc: '',
      args: [],
    );
  }

  /// `Page {current} of {total}`
  String orderPageIndicator(Object current, Object total) {
    return Intl.message(
      'Page $current of $total',
      name: 'orderPageIndicator',
      desc: '',
      args: [current, total],
    );
  }

  /// `Previous`
  String get previousPage {
    return Intl.message('Previous', name: 'previousPage', desc: '', args: []);
  }

  /// `Next`
  String get nextPage {
    return Intl.message('Next', name: 'nextPage', desc: '', args: []);
  }

  /// `Payment method`
  String get paymentMethod {
    return Intl.message(
      'Payment method',
      name: 'paymentMethod',
      desc: '',
      args: [],
    );
  }

  /// `Paid at`
  String get paidAt {
    return Intl.message('Paid at', name: 'paidAt', desc: '', args: []);
  }

  /// `Account`
  String get personalCenter {
    return Intl.message('Account', name: 'personalCenter', desc: '', args: []);
  }

  /// `Live connections`
  String get realTimeConnections {
    return Intl.message(
      'Live connections',
      name: 'realTimeConnections',
      desc: '',
      args: [],
    );
  }

  /// `Advanced`
  String get advancedSettings {
    return Intl.message(
      'Advanced',
      name: 'advancedSettings',
      desc: '',
      args: [],
    );
  }

  /// `Utilities`
  String get practicalTools {
    return Intl.message(
      'Utilities',
      name: 'practicalTools',
      desc: '',
      args: [],
    );
  }

  /// `Signed in`
  String get loggedIn {
    return Intl.message('Signed in', name: 'loggedIn', desc: '', args: []);
  }

  /// `Current node`
  String get currentNode {
    return Intl.message(
      'Current node',
      name: 'currentNode',
      desc: '',
      args: [],
    );
  }

  /// `Auto select`
  String get automaticSelection {
    return Intl.message(
      'Auto select',
      name: 'automaticSelection',
      desc: '',
      args: [],
    );
  }

  /// `Manual select`
  String get manualSelection {
    return Intl.message(
      'Manual select',
      name: 'manualSelection',
      desc: '',
      args: [],
    );
  }

  /// `Remaining traffic`
  String get remainingTraffic {
    return Intl.message(
      'Remaining traffic',
      name: 'remainingTraffic',
      desc: '',
      args: [],
    );
  }

  /// `Used`
  String get usedTrafficLabel {
    return Intl.message('Used', name: 'usedTrafficLabel', desc: '', args: []);
  }

  /// `Remaining`
  String get remainingTrafficLabel {
    return Intl.message(
      'Remaining',
      name: 'remainingTrafficLabel',
      desc: '',
      args: [],
    );
  }

  /// `Unlimited`
  String get unlimitedTime {
    return Intl.message('Unlimited', name: 'unlimitedTime', desc: '', args: []);
  }

  /// `Start acceleration`
  String get startAcceleration {
    return Intl.message(
      'Start acceleration',
      name: 'startAcceleration',
      desc: '',
      args: [],
    );
  }

  /// `Stop acceleration`
  String get stopAcceleration {
    return Intl.message(
      'Stop acceleration',
      name: 'stopAcceleration',
      desc: '',
      args: [],
    );
  }

  /// `Invite rewards`
  String get invitePromotion {
    return Intl.message(
      'Invite rewards',
      name: 'invitePromotion',
      desc: '',
      args: [],
    );
  }

  /// `Log out`
  String get logoutAccount {
    return Intl.message('Log out', name: 'logoutAccount', desc: '', args: []);
  }

  /// `No active plan`
  String get noActivePlan {
    return Intl.message(
      'No active plan',
      name: 'noActivePlan',
      desc: '',
      args: [],
    );
  }

  /// `Connection status`
  String get connectionStatus {
    return Intl.message(
      'Connection status',
      name: 'connectionStatus',
      desc: '',
      args: [],
    );
  }

  /// `Refresh subscription`
  String get refreshSubscription {
    return Intl.message(
      'Refresh subscription',
      name: 'refreshSubscription',
      desc: '',
      args: [],
    );
  }

  /// `Switch node`
  String get switchNode {
    return Intl.message('Switch node', name: 'switchNode', desc: '', args: []);
  }

  /// `Not tested`
  String get notTested {
    return Intl.message('Not tested', name: 'notTested', desc: '', args: []);
  }

  /// `Total`
  String get totalTrafficLabel {
    return Intl.message('Total', name: 'totalTrafficLabel', desc: '', args: []);
  }

  /// `Global acceleration network`
  String get globalAccelerationNetwork {
    return Intl.message(
      'Global acceleration network',
      name: 'globalAccelerationNetwork',
      desc: '',
      args: [],
    );
  }

  /// `User`
  String get userMapLabel {
    return Intl.message('User', name: 'userMapLabel', desc: '', args: []);
  }

  /// `{count} nodes`
  String nodesCount(Object count) {
    return Intl.message(
      '$count nodes',
      name: 'nodesCount',
      desc: '',
      args: [count],
    );
  }

  /// `{count} countries & regions`
  String countriesCount(Object count) {
    return Intl.message(
      '$count countries & regions',
      name: 'countriesCount',
      desc: '',
      args: [count],
    );
  }

  /// `Zoom in`
  String get zoomIn {
    return Intl.message('Zoom in', name: 'zoomIn', desc: '', args: []);
  }

  /// `Zoom out`
  String get zoomOut {
    return Intl.message('Zoom out', name: 'zoomOut', desc: '', args: []);
  }

  /// `Choose the best node for a fast and stable connection`
  String get nodeStatusSubtitle {
    return Intl.message(
      'Choose the best node for a fast and stable connection',
      name: 'nodeStatusSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Global node distribution`
  String get globalNodeDistribution {
    return Intl.message(
      'Global node distribution',
      name: 'globalNodeDistribution',
      desc: '',
      args: [],
    );
  }

  /// `Preferred nodes`
  String get preferredNodes {
    return Intl.message(
      'Preferred nodes',
      name: 'preferredNodes',
      desc: '',
      args: [],
    );
  }

  /// `Countries & regions`
  String get countriesAndRegions {
    return Intl.message(
      'Countries & regions',
      name: 'countriesAndRegions',
      desc: '',
      args: [],
    );
  }

  /// `Quality nodes`
  String get qualityNodes {
    return Intl.message(
      'Quality nodes',
      name: 'qualityNodes',
      desc: '',
      args: [],
    );
  }

  /// `Availability`
  String get availabilityRate {
    return Intl.message(
      'Availability',
      name: 'availabilityRate',
      desc: '',
      args: [],
    );
  }

  /// `Refresh`
  String get refreshNodes {
    return Intl.message('Refresh', name: 'refreshNodes', desc: '', args: []);
  }

  /// `Online`
  String get online {
    return Intl.message('Online', name: 'online', desc: '', args: []);
  }

  /// `Offline`
  String get offline {
    return Intl.message('Offline', name: 'offline', desc: '', args: []);
  }

  /// `Backend online`
  String get nodeBackendOnline {
    return Intl.message(
      'Backend online',
      name: 'nodeBackendOnline',
      desc: '',
      args: [],
    );
  }

  /// `Backend offline`
  String get nodeBackendOffline {
    return Intl.message(
      'Backend offline',
      name: 'nodeBackendOffline',
      desc: '',
      args: [],
    );
  }

  /// `Available`
  String get nodeAvailable {
    return Intl.message('Available', name: 'nodeAvailable', desc: '', args: []);
  }

  /// `Network unstable`
  String get nodeNetworkFluctuating {
    return Intl.message(
      'Network unstable',
      name: 'nodeNetworkFluctuating',
      desc: '',
      args: [],
    );
  }

  /// `Unreachable here`
  String get nodeLocallyUnreachable {
    return Intl.message(
      'Unreachable here',
      name: 'nodeLocallyUnreachable',
      desc: '',
      args: [],
    );
  }

  /// `Status unknown`
  String get nodeStatusUnknown {
    return Intl.message(
      'Status unknown',
      name: 'nodeStatusUnknown',
      desc: '',
      args: [],
    );
  }

  /// `Offline mode`
  String get offlineMode {
    return Intl.message(
      'Offline mode',
      name: 'offlineMode',
      desc: '',
      args: [],
    );
  }

  /// `Continue with local cache`
  String get offlineEntry {
    return Intl.message(
      'Continue with local cache',
      name: 'offlineEntry',
      desc: '',
      args: [],
    );
  }

  /// `No offline cache available`
  String get offlineEntryUnavailable {
    return Intl.message(
      'No offline cache available',
      name: 'offlineEntryUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `Use the most recently verified subscription and nodes`
  String get offlineEntryHint {
    return Intl.message(
      'Use the most recently verified subscription and nodes',
      name: 'offlineEntryHint',
      desc: '',
      args: [],
    );
  }

  /// `Enable offline mode?`
  String get enableOfflineTitle {
    return Intl.message(
      'Enable offline mode?',
      name: 'enableOfflineTitle',
      desc: '',
      args: [],
    );
  }

  /// `Online sign-in validation and account refreshes will be skipped. Cached subscription, nodes, and account summary will be used instead.`
  String get enableOfflineDescription {
    return Intl.message(
      'Online sign-in validation and account refreshes will be skipped. Cached subscription, nodes, and account summary will be used instead.',
      name: 'enableOfflineDescription',
      desc: '',
      args: [],
    );
  }

  /// `About offline mode`
  String get offlineModeDescriptionTitle {
    return Intl.message(
      'About offline mode',
      name: 'offlineModeDescriptionTitle',
      desc: '',
      args: [],
    );
  }

  /// `Existing cache remains available on the dashboard and node pages.`
  String get offlineCacheContinues {
    return Intl.message(
      'Existing cache remains available on the dashboard and node pages.',
      name: 'offlineCacheContinues',
      desc: '',
      args: [],
    );
  }

  /// `Plans, invitations, subscriptions, and account data will not be refreshed.`
  String get offlineNoUpdates {
    return Intl.message(
      'Plans, invitations, subscriptions, and account data will not be refreshed.',
      name: 'offlineNoUpdates',
      desc: '',
      args: [],
    );
  }

  /// `Network tools that do not require account sign-in remain available.`
  String get offlineNetworkTools {
    return Intl.message(
      'Network tools that do not require account sign-in remain available.',
      name: 'offlineNetworkTools',
      desc: '',
      args: [],
    );
  }

  /// `Enable offline mode`
  String get enableOfflineAction {
    return Intl.message(
      'Enable offline mode',
      name: 'enableOfflineAction',
      desc: '',
      args: [],
    );
  }

  /// `Enabled`
  String get offlineModeEnabled {
    return Intl.message(
      'Enabled',
      name: 'offlineModeEnabled',
      desc: '',
      args: [],
    );
  }

  /// `Restore online mode`
  String get restoreOnline {
    return Intl.message(
      'Restore online mode',
      name: 'restoreOnline',
      desc: '',
      args: [],
    );
  }

  /// `Restoring online mode…`
  String get restoringOnline {
    return Intl.message(
      'Restoring online mode…',
      name: 'restoringOnline',
      desc: '',
      args: [],
    );
  }

  /// `No valid subscription cache verified within the last three days`
  String get offlineCacheUnavailable {
    return Intl.message(
      'No valid subscription cache verified within the last three days',
      name: 'offlineCacheUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `Offline mode is enabled. Local cached data is being shown.`
  String get offlineModeBanner {
    return Intl.message(
      'Offline mode is enabled. Local cached data is being shown.',
      name: 'offlineModeBanner',
      desc: '',
      args: [],
    );
  }

  /// `Restore online mode to use this feature`
  String get onlineFeaturesUnavailableOffline {
    return Intl.message(
      'Restore online mode to use this feature',
      name: 'onlineFeaturesUnavailableOffline',
      desc: '',
      args: [],
    );
  }

  /// `Login endpoint`
  String get loginEndpoint {
    return Intl.message(
      'Login endpoint',
      name: 'loginEndpoint',
      desc: '',
      args: [],
    );
  }

  /// `Service status`
  String get serviceStatus {
    return Intl.message(
      'Service status',
      name: 'serviceStatus',
      desc: '',
      args: [],
    );
  }

  /// `Available endpoints`
  String get availableEndpoints {
    return Intl.message(
      'Available endpoints',
      name: 'availableEndpoints',
      desc: '',
      args: [],
    );
  }

  /// `Currently used`
  String get currentEndpoint {
    return Intl.message(
      'Currently used',
      name: 'currentEndpoint',
      desc: '',
      args: [],
    );
  }

  /// `Refresh config`
  String get refreshConfiguration {
    return Intl.message(
      'Refresh config',
      name: 'refreshConfiguration',
      desc: '',
      args: [],
    );
  }

  /// `Test all`
  String get testAllEndpoints {
    return Intl.message(
      'Test all',
      name: 'testAllEndpoints',
      desc: '',
      args: [],
    );
  }

  /// `Test`
  String get testEndpoint {
    return Intl.message('Test', name: 'testEndpoint', desc: '', args: []);
  }

  /// `Endpoint {index}`
  String loginEndpointLabel(Object index) {
    return Intl.message(
      'Endpoint $index',
      name: 'loginEndpointLabel',
      desc: '',
      args: [index],
    );
  }

  /// `Set as the global preferred API endpoint`
  String get apiEndpointApplied {
    return Intl.message(
      'Set as the global preferred API endpoint',
      name: 'apiEndpointApplied',
      desc: '',
      args: [],
    );
  }

  /// `In-app payment`
  String get inAppPayment {
    return Intl.message(
      'In-app payment',
      name: 'inAppPayment',
      desc: '',
      args: [],
    );
  }

  /// `The payment QR code stays securely inside the app`
  String get paymentStaysInApp {
    return Intl.message(
      'The payment QR code stays securely inside the app',
      name: 'paymentStaysInApp',
      desc: '',
      args: [],
    );
  }

  /// `Loading payment methods…`
  String get loadingPaymentMethods {
    return Intl.message(
      'Loading payment methods…',
      name: 'loadingPaymentMethods',
      desc: '',
      args: [],
    );
  }

  /// `No payment method is currently available`
  String get noPaymentMethods {
    return Intl.message(
      'No payment method is currently available',
      name: 'noPaymentMethods',
      desc: '',
      args: [],
    );
  }

  /// `Free activation`
  String get freeOrder {
    return Intl.message(
      'Free activation',
      name: 'freeOrder',
      desc: '',
      args: [],
    );
  }

  /// `No payment is required for this order`
  String get noPaymentRequired {
    return Intl.message(
      'No payment is required for this order',
      name: 'noPaymentRequired',
      desc: '',
      args: [],
    );
  }

  /// `Select a payment method`
  String get selectPaymentMethod {
    return Intl.message(
      'Select a payment method',
      name: 'selectPaymentMethod',
      desc: '',
      args: [],
    );
  }

  /// `Generate payment QR code`
  String get generatePaymentQr {
    return Intl.message(
      'Generate payment QR code',
      name: 'generatePaymentQr',
      desc: '',
      args: [],
    );
  }

  /// `Activate now`
  String get activateNow {
    return Intl.message(
      'Activate now',
      name: 'activateNow',
      desc: '',
      args: [],
    );
  }

  /// `Orders and QR codes are generated live by the XBoard payment API`
  String get paymentSecurityHint {
    return Intl.message(
      'Orders and QR codes are generated live by the XBoard payment API',
      name: 'paymentSecurityHint',
      desc: '',
      args: [],
    );
  }

  /// `Creating order…`
  String get creatingOrder {
    return Intl.message(
      'Creating order…',
      name: 'creatingOrder',
      desc: '',
      args: [],
    );
  }

  /// `Please wait and do not submit again`
  String get pleaseWait {
    return Intl.message(
      'Please wait and do not submit again',
      name: 'pleaseWait',
      desc: '',
      args: [],
    );
  }

  /// `Scan to pay`
  String get scanToPay {
    return Intl.message('Scan to pay', name: 'scanToPay', desc: '', args: []);
  }

  /// `Scan the QR code below with the matching payment app`
  String get scanWithPaymentApp {
    return Intl.message(
      'Scan the QR code below with the matching payment app',
      name: 'scanWithPaymentApp',
      desc: '',
      args: [],
    );
  }

  /// `Order number`
  String get orderNumber {
    return Intl.message(
      'Order number',
      name: 'orderNumber',
      desc: '',
      args: [],
    );
  }

  /// `Waiting for payment`
  String get waitingForPayment {
    return Intl.message(
      'Waiting for payment',
      name: 'waitingForPayment',
      desc: '',
      args: [],
    );
  }

  /// `I have paid, refresh status`
  String get iHavePaid {
    return Intl.message(
      'I have paid, refresh status',
      name: 'iHavePaid',
      desc: '',
      args: [],
    );
  }

  /// `Payment successful`
  String get paymentSuccessful {
    return Intl.message(
      'Payment successful',
      name: 'paymentSuccessful',
      desc: '',
      args: [],
    );
  }

  /// `Your plan is being activated. Refresh the subscription shortly`
  String get paymentSuccessfulHint {
    return Intl.message(
      'Your plan is being activated. Refresh the subscription shortly',
      name: 'paymentSuccessfulHint',
      desc: '',
      args: [],
    );
  }

  /// `Payment not completed`
  String get paymentFailed {
    return Intl.message(
      'Payment not completed',
      name: 'paymentFailed',
      desc: '',
      args: [],
    );
  }

  /// `The order was cancelled`
  String get orderCancelled {
    return Intl.message(
      'The order was cancelled',
      name: 'orderCancelled',
      desc: '',
      args: [],
    );
  }

  /// `Handling fee`
  String get handlingFee {
    return Intl.message(
      'Handling fee',
      name: 'handlingFee',
      desc: '',
      args: [],
    );
  }

  /// `No handling fee`
  String get noHandlingFee {
    return Intl.message(
      'No handling fee',
      name: 'noHandlingFee',
      desc: '',
      args: [],
    );
  }

  /// `Done`
  String get done {
    return Intl.message('Done', name: 'done', desc: '', args: []);
  }

  /// `Retry`
  String get retry {
    return Intl.message('Retry', name: 'retry', desc: '', args: []);
  }

  /// `Manage your account information and security settings`
  String get accountCenterSubtitle {
    return Intl.message(
      'Manage your account information and security settings',
      name: 'accountCenterSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Membership valid until`
  String get memberValidUntil {
    return Intl.message(
      'Membership valid until',
      name: 'memberValidUntil',
      desc: '',
      args: [],
    );
  }

  /// `My wallet`
  String get myWallet {
    return Intl.message('My wallet', name: 'myWallet', desc: '', args: []);
  }

  /// `Spending only`
  String get consumptionOnly {
    return Intl.message(
      'Spending only',
      name: 'consumptionOnly',
      desc: '',
      args: [],
    );
  }

  /// `Account balance`
  String get accountBalance {
    return Intl.message(
      'Account balance',
      name: 'accountBalance',
      desc: '',
      args: [],
    );
  }

  /// `Notifications`
  String get notificationSettings {
    return Intl.message(
      'Notifications',
      name: 'notificationSettings',
      desc: '',
      args: [],
    );
  }

  /// `Expiration email reminder`
  String get expiryEmailReminder {
    return Intl.message(
      'Expiration email reminder',
      name: 'expiryEmailReminder',
      desc: '',
      args: [],
    );
  }

  /// `Traffic email reminder`
  String get trafficEmailReminder {
    return Intl.message(
      'Traffic email reminder',
      name: 'trafficEmailReminder',
      desc: '',
      args: [],
    );
  }

  /// `Notification settings saved`
  String get notificationSettingsSaved {
    return Intl.message(
      'Notification settings saved',
      name: 'notificationSettingsSaved',
      desc: '',
      args: [],
    );
  }

  /// `Change password`
  String get changePasswordTitle {
    return Intl.message(
      'Change password',
      name: 'changePasswordTitle',
      desc: '',
      args: [],
    );
  }

  /// `Current password`
  String get oldPassword {
    return Intl.message(
      'Current password',
      name: 'oldPassword',
      desc: '',
      args: [],
    );
  }

  /// `Enter your current password`
  String get enterOldPassword {
    return Intl.message(
      'Enter your current password',
      name: 'enterOldPassword',
      desc: '',
      args: [],
    );
  }

  /// `Confirm new password`
  String get confirmNewPassword {
    return Intl.message(
      'Confirm new password',
      name: 'confirmNewPassword',
      desc: '',
      args: [],
    );
  }

  /// `Password changed successfully`
  String get passwordChanged {
    return Intl.message(
      'Password changed successfully',
      name: 'passwordChanged',
      desc: '',
      args: [],
    );
  }

  /// `Telegram binding`
  String get telegramBinding {
    return Intl.message(
      'Telegram binding',
      name: 'telegramBinding',
      desc: '',
      args: [],
    );
  }

  /// `Telegram ID`
  String get telegramId {
    return Intl.message('Telegram ID', name: 'telegramId', desc: '', args: []);
  }

  /// `Telegram is not bound to this account`
  String get telegramUnboundHint {
    return Intl.message(
      'Telegram is not bound to this account',
      name: 'telegramUnboundHint',
      desc: '',
      args: [],
    );
  }

  /// `Bound`
  String get bound {
    return Intl.message('Bound', name: 'bound', desc: '', args: []);
  }

  /// `Not bound`
  String get unbound {
    return Intl.message('Not bound', name: 'unbound', desc: '', args: []);
  }

  /// `Reset subscription`
  String get resetSubscription {
    return Intl.message(
      'Reset subscription',
      name: 'resetSubscription',
      desc: '',
      args: [],
    );
  }

  /// `Generate a new subscription address if the current one is exposed or unavailable`
  String get resetSubscriptionDescription {
    return Intl.message(
      'Generate a new subscription address if the current one is exposed or unavailable',
      name: 'resetSubscriptionDescription',
      desc: '',
      args: [],
    );
  }

  /// `Reset the subscription?`
  String get resetSubscriptionConfirmTitle {
    return Intl.message(
      'Reset the subscription?',
      name: 'resetSubscriptionConfirmTitle',
      desc: '',
      args: [],
    );
  }

  /// `The old address will stop working immediately and every device must sync again.`
  String get resetSubscriptionConfirmMessage {
    return Intl.message(
      'The old address will stop working immediately and every device must sync again.',
      name: 'resetSubscriptionConfirmMessage',
      desc: '',
      args: [],
    );
  }

  /// `Reset now`
  String get confirmReset {
    return Intl.message('Reset now', name: 'confirmReset', desc: '', args: []);
  }

  /// `Subscription reset and synchronized`
  String get subscriptionResetSuccess {
    return Intl.message(
      'Subscription reset and synchronized',
      name: 'subscriptionResetSuccess',
      desc: '',
      args: [],
    );
  }

  /// `Sign out of this account?`
  String get logoutConfirmTitle {
    return Intl.message(
      'Sign out of this account?',
      name: 'logoutConfirmTitle',
      desc: '',
      args: [],
    );
  }

  /// `Saved sign-in information on this device will be cleared.`
  String get logoutConfirmMessage {
    return Intl.message(
      'Saved sign-in information on this device will be cleared.',
      name: 'logoutConfirmMessage',
      desc: '',
      args: [],
    );
  }

  /// `Unable to load account information`
  String get userInfoFailed {
    return Intl.message(
      'Unable to load account information',
      name: 'userInfoFailed',
      desc: '',
      args: [],
    );
  }

  /// `Request failed. Please try again later`
  String get requestFailed {
    return Intl.message(
      'Request failed. Please try again later',
      name: 'requestFailed',
      desc: '',
      args: [],
    );
  }

  /// `Customize VPN behavior and network parameters for your connection`
  String get advancedSettingsSubtitle {
    return Intl.message(
      'Customize VPN behavior and network parameters for your connection',
      name: 'advancedSettingsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Proxy settings`
  String get proxySettings {
    return Intl.message(
      'Proxy settings',
      name: 'proxySettings',
      desc: '',
      args: [],
    );
  }

  /// `Manage the local proxy service`
  String get proxySettingsSubtitle {
    return Intl.message(
      'Manage the local proxy service',
      name: 'proxySettingsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Shared HTTP & SOCKS5 port`
  String get mixedPortSharedDescription {
    return Intl.message(
      'Shared HTTP & SOCKS5 port',
      name: 'mixedPortSharedDescription',
      desc: '',
      args: [],
    );
  }

  /// `Local proxy address`
  String get proxyAccessAddress {
    return Intl.message(
      'Local proxy address',
      name: 'proxyAccessAddress',
      desc: '',
      args: [],
    );
  }

  /// `IPv6 settings`
  String get ipv6Settings {
    return Intl.message(
      'IPv6 settings',
      name: 'ipv6Settings',
      desc: '',
      args: [],
    );
  }

  /// `Manage Mihomo IPv6 connectivity`
  String get ipv6SettingsSubtitle {
    return Intl.message(
      'Manage Mihomo IPv6 connectivity',
      name: 'ipv6SettingsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Core IPv6`
  String get coreIpv6 {
    return Intl.message('Core IPv6', name: 'coreIpv6', desc: '', args: []);
  }

  /// `Control Mihomo top-level IPv6 support`
  String get coreIpv6Description {
    return Intl.message(
      'Control Mihomo top-level IPv6 support',
      name: 'coreIpv6Description',
      desc: '',
      args: [],
    );
  }

  /// `DNS IPv6`
  String get dnsIpv6 {
    return Intl.message('DNS IPv6', name: 'dnsIpv6', desc: '', args: []);
  }

  /// `Return IPv6 records from DNS queries`
  String get dnsIpv6Description {
    return Intl.message(
      'Return IPv6 records from DNS queries',
      name: 'dnsIpv6Description',
      desc: '',
      args: [],
    );
  }

  /// `Geodata`
  String get geodataSettings {
    return Intl.message('Geodata', name: 'geodataSettings', desc: '', args: []);
  }

  /// `Update GeoIP and GeoSite databases`
  String get geodataSettingsSubtitle {
    return Intl.message(
      'Update GeoIP and GeoSite databases',
      name: 'geodataSettingsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Update all`
  String get updateAll {
    return Intl.message('Update all', name: 'updateAll', desc: '', args: []);
  }

  /// `All geodata resources have been updated`
  String get allGeodataUpdated {
    return Intl.message(
      'All geodata resources have been updated',
      name: 'allGeodataUpdated',
      desc: '',
      args: [],
    );
  }

  /// `DNS settings`
  String get dnsSettings {
    return Intl.message(
      'DNS settings',
      name: 'dnsSettings',
      desc: '',
      args: [],
    );
  }

  /// `Manage DNS resolution settings`
  String get dnsSettingsSubtitle {
    return Intl.message(
      'Manage DNS resolution settings',
      name: 'dnsSettingsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Custom DNS servers`
  String get customDnsServers {
    return Intl.message(
      'Custom DNS servers',
      name: 'customDnsServers',
      desc: '',
      args: [],
    );
  }

  /// `{count} saved; active when override is enabled`
  String savedDnsServersCount(Object count) {
    return Intl.message(
      '$count saved; active when override is enabled',
      name: 'savedDnsServersCount',
      desc: '',
      args: [count],
    );
  }

  /// `When enabled, the app's built-in DNS configuration is used instead of the profile DNS settings`
  String get dnsOverrideInformation {
    return Intl.message(
      'When enabled, the app\'s built-in DNS configuration is used instead of the profile DNS settings',
      name: 'dnsOverrideInformation',
      desc: '',
      args: [],
    );
  }

  /// `Switch to global mode`
  String get switchToGlobalMode {
    return Intl.message(
      'Switch to global mode',
      name: 'switchToGlobalMode',
      desc: '',
      args: [],
    );
  }

  /// `Global mode takes over all network traffic. The first switch uses DIRECT, then you can choose a proxy node after confirming.`
  String get globalModeWarningDescription {
    return Intl.message(
      'Global mode takes over all network traffic. The first switch uses DIRECT, then you can choose a proxy node after confirming.',
      name: 'globalModeWarningDescription',
      desc: '',
      args: [],
    );
  }

  /// `What happens after switching`
  String get whatHappensAfterSwitch {
    return Intl.message(
      'What happens after switching',
      name: 'whatHappensAfterSwitch',
      desc: '',
      args: [],
    );
  }

  /// `Daily browsing: rule mode is more reliable.`
  String get dailyBrowsingRuleMode {
    return Intl.message(
      'Daily browsing: rule mode is more reliable.',
      name: 'dailyBrowsingRuleMode',
      desc: '',
      args: [],
    );
  }

  /// `Need a proxy: open the node list and choose a non-DIRECT node.`
  String get proxyNeededChooseNode {
    return Intl.message(
      'Need a proxy: open the node list and choose a non-DIRECT node.',
      name: 'proxyNeededChooseNode',
      desc: '',
      args: [],
    );
  }

  /// `Don't show again`
  String get dontShowAgain {
    return Intl.message(
      'Don\'t show again',
      name: 'dontShowAgain',
      desc: '',
      args: [],
    );
  }

  /// `Switch and use DIRECT`
  String get switchAndDirect {
    return Intl.message(
      'Switch and use DIRECT',
      name: 'switchAndDirect',
      desc: '',
      args: [],
    );
  }

  /// `Review usage and understand your network trends`
  String get trafficDetailsSubtitle {
    return Intl.message(
      'Review usage and understand your network trends',
      name: 'trafficDetailsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Today`
  String get todayTraffic {
    return Intl.message('Today', name: 'todayTraffic', desc: '', args: []);
  }

  /// `This month`
  String get currentMonthTraffic {
    return Intl.message(
      'This month',
      name: 'currentMonthTraffic',
      desc: '',
      args: [],
    );
  }

  /// `Traffic usage records`
  String get trafficDetailRecords {
    return Intl.message(
      'Traffic usage records',
      name: 'trafficDetailRecords',
      desc: '',
      args: [],
    );
  }

  /// `Refresh data`
  String get refreshData {
    return Intl.message(
      'Refresh data',
      name: 'refreshData',
      desc: '',
      args: [],
    );
  }

  /// `Date`
  String get dateLabel {
    return Intl.message('Date', name: 'dateLabel', desc: '', args: []);
  }

  /// `Download`
  String get downloadTraffic {
    return Intl.message(
      'Download',
      name: 'downloadTraffic',
      desc: '',
      args: [],
    );
  }

  /// `Upload`
  String get uploadTraffic {
    return Intl.message('Upload', name: 'uploadTraffic', desc: '', args: []);
  }

  /// `Rate`
  String get trafficRate {
    return Intl.message('Rate', name: 'trafficRate', desc: '', args: []);
  }

  /// `No traffic records for this month`
  String get noTrafficRecords {
    return Intl.message(
      'No traffic records for this month',
      name: 'noTrafficRecords',
      desc: '',
      args: [],
    );
  }

  /// `Unable to load traffic data`
  String get trafficRecordsFailed {
    return Intl.message(
      'Unable to load traffic data',
      name: 'trafficRecordsFailed',
      desc: '',
      args: [],
    );
  }

  /// `Auto-renew`
  String get autoRenew {
    return Intl.message('Auto-renew', name: 'autoRenew', desc: '', args: []);
  }

  /// `Not enabled`
  String get notEnabled {
    return Intl.message('Not enabled', name: 'notEnabled', desc: '', args: []);
  }

  /// `Invite friends, earn rewards`
  String get inviteHeroTitle {
    return Intl.message(
      'Invite friends, earn rewards',
      name: 'inviteHeroTitle',
      desc: '',
      args: [],
    );
  }

  /// `Invite more, earn more — no reward limit!`
  String get inviteHeroSubtitle {
    return Intl.message(
      'Invite more, earn more — no reward limit!',
      name: 'inviteHeroSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `My invitations`
  String get myInvitation {
    return Intl.message(
      'My invitations',
      name: 'myInvitation',
      desc: '',
      args: [],
    );
  }

  /// `Available commission`
  String get remainingCommission {
    return Intl.message(
      'Available commission',
      name: 'remainingCommission',
      desc: '',
      args: [],
    );
  }

  /// `Transfer`
  String get commissionTransfer {
    return Intl.message(
      'Transfer',
      name: 'commissionTransfer',
      desc: '',
      args: [],
    );
  }

  /// `Withdraw`
  String get commissionWithdraw {
    return Intl.message(
      'Withdraw',
      name: 'commissionWithdraw',
      desc: '',
      args: [],
    );
  }

  /// `Registered users`
  String get registeredUsers {
    return Intl.message(
      'Registered users',
      name: 'registeredUsers',
      desc: '',
      args: [],
    );
  }

  /// `{count}`
  String peopleCount(Object count) {
    return Intl.message('$count', name: 'peopleCount', desc: '', args: [count]);
  }

  /// `Commission rate`
  String get commissionRate {
    return Intl.message(
      'Commission rate',
      name: 'commissionRate',
      desc: '',
      args: [],
    );
  }

  /// `Pending commission`
  String get pendingCommission {
    return Intl.message(
      'Pending commission',
      name: 'pendingCommission',
      desc: '',
      args: [],
    );
  }

  /// `Total commission`
  String get totalCommission {
    return Intl.message(
      'Total commission',
      name: 'totalCommission',
      desc: '',
      args: [],
    );
  }

  /// `Invite code management`
  String get inviteCodeManagement {
    return Intl.message(
      'Invite code management',
      name: 'inviteCodeManagement',
      desc: '',
      args: [],
    );
  }

  /// `Share your invite code. You earn commission after a friend signs up and purchases a plan.`
  String get inviteCodeDescription {
    return Intl.message(
      'Share your invite code. You earn commission after a friend signs up and purchases a plan.',
      name: 'inviteCodeDescription',
      desc: '',
      args: [],
    );
  }

  /// `Generate code`
  String get generateInviteCode {
    return Intl.message(
      'Generate code',
      name: 'generateInviteCode',
      desc: '',
      args: [],
    );
  }

  /// `Invite code`
  String get inviteCode {
    return Intl.message('Invite code', name: 'inviteCode', desc: '', args: []);
  }

  /// `Created`
  String get createdAt {
    return Intl.message('Created', name: 'createdAt', desc: '', args: []);
  }

  /// `Action`
  String get actions {
    return Intl.message('Action', name: 'actions', desc: '', args: []);
  }

  /// `Copy invite code`
  String get copyInviteCode {
    return Intl.message(
      'Copy invite code',
      name: 'copyInviteCode',
      desc: '',
      args: [],
    );
  }

  /// `Commission records`
  String get commissionPayoutRecords {
    return Intl.message(
      'Commission records',
      name: 'commissionPayoutRecords',
      desc: '',
      args: [],
    );
  }

  /// `Paid at`
  String get payoutTime {
    return Intl.message('Paid at', name: 'payoutTime', desc: '', args: []);
  }

  /// `Commission`
  String get commission {
    return Intl.message('Commission', name: 'commission', desc: '', args: []);
  }

  /// `No commission records`
  String get noCommissionRecords {
    return Intl.message(
      'No commission records',
      name: 'noCommissionRecords',
      desc: '',
      args: [],
    );
  }

  /// `No invite codes yet. Generate one above.`
  String get noInviteCodes {
    return Intl.message(
      'No invite codes yet. Generate one above.',
      name: 'noInviteCodes',
      desc: '',
      args: [],
    );
  }

  /// `Unable to load invite data`
  String get inviteLoadFailed {
    return Intl.message(
      'Unable to load invite data',
      name: 'inviteLoadFailed',
      desc: '',
      args: [],
    );
  }

  /// `Invite code generated`
  String get inviteCodeGenerated {
    return Intl.message(
      'Invite code generated',
      name: 'inviteCodeGenerated',
      desc: '',
      args: [],
    );
  }

  /// `Invite code copied`
  String get inviteCodeCopied {
    return Intl.message(
      'Invite code copied',
      name: 'inviteCodeCopied',
      desc: '',
      args: [],
    );
  }

  /// `Commission transferred to account balance`
  String get commissionTransferred {
    return Intl.message(
      'Commission transferred to account balance',
      name: 'commissionTransferred',
      desc: '',
      args: [],
    );
  }

  /// `Transfer all available commission?`
  String get commissionTransferConfirmTitle {
    return Intl.message(
      'Transfer all available commission?',
      name: 'commissionTransferConfirmTitle',
      desc: '',
      args: [],
    );
  }

  /// `The available commission will move to your account balance for purchasing plans.`
  String get commissionTransferConfirmMessage {
    return Intl.message(
      'The available commission will move to your account balance for purchasing plans.',
      name: 'commissionTransferConfirmMessage',
      desc: '',
      args: [],
    );
  }

  /// `No commission available to transfer`
  String get availableCommissionEmpty {
    return Intl.message(
      'No commission available to transfer',
      name: 'availableCommissionEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Commission withdrawal request`
  String get withdrawalRequestTitle {
    return Intl.message(
      'Commission withdrawal request',
      name: 'withdrawalRequestTitle',
      desc: '',
      args: [],
    );
  }

  /// `Withdrawal method`
  String get withdrawalMethod {
    return Intl.message(
      'Withdrawal method',
      name: 'withdrawalMethod',
      desc: '',
      args: [],
    );
  }

  /// `Withdrawal amount`
  String get withdrawalAmount {
    return Intl.message(
      'Withdrawal amount',
      name: 'withdrawalAmount',
      desc: '',
      args: [],
    );
  }

  /// `Receiving account`
  String get withdrawalAccount {
    return Intl.message(
      'Receiving account',
      name: 'withdrawalAccount',
      desc: '',
      args: [],
    );
  }

  /// `Select a withdrawal method`
  String get selectWithdrawalMethod {
    return Intl.message(
      'Select a withdrawal method',
      name: 'selectWithdrawalMethod',
      desc: '',
      args: [],
    );
  }

  /// `Enter the withdrawal amount`
  String get enterWithdrawalAmount {
    return Intl.message(
      'Enter the withdrawal amount',
      name: 'enterWithdrawalAmount',
      desc: '',
      args: [],
    );
  }

  /// `Enter the receiving account or address`
  String get enterWithdrawalAccount {
    return Intl.message(
      'Enter the receiving account or address',
      name: 'enterWithdrawalAccount',
      desc: '',
      args: [],
    );
  }

  /// `Submit withdrawal ticket`
  String get submitWithdrawalTicket {
    return Intl.message(
      'Submit withdrawal ticket',
      name: 'submitWithdrawalTicket',
      desc: '',
      args: [],
    );
  }

  /// `Withdrawal ticket submitted. Please wait for an administrator to process it.`
  String get withdrawalTicketCreated {
    return Intl.message(
      'Withdrawal ticket submitted. Please wait for an administrator to process it.',
      name: 'withdrawalTicketCreated',
      desc: '',
      args: [],
    );
  }

  /// `Enter a valid withdrawal amount`
  String get withdrawalAmountInvalid {
    return Intl.message(
      'Enter a valid withdrawal amount',
      name: 'withdrawalAmountInvalid',
      desc: '',
      args: [],
    );
  }

  /// `The amount cannot exceed available commission`
  String get withdrawalAmountExceeds {
    return Intl.message(
      'The amount cannot exceed available commission',
      name: 'withdrawalAmountExceeds',
      desc: '',
      args: [],
    );
  }

  /// `A support ticket will be created in the system for an administrator to process.`
  String get withdrawalTicketDescription {
    return Intl.message(
      'A support ticket will be created in the system for an administrator to process.',
      name: 'withdrawalTicketDescription',
      desc: '',
      args: [],
    );
  }

  /// `Alipay`
  String get withdrawalMethodAlipay {
    return Intl.message(
      'Alipay',
      name: 'withdrawalMethodAlipay',
      desc: '',
      args: [],
    );
  }

  /// `WeChat Pay`
  String get withdrawalMethodWechat {
    return Intl.message(
      'WeChat Pay',
      name: 'withdrawalMethodWechat',
      desc: '',
      args: [],
    );
  }

  /// `USDT`
  String get withdrawalMethodUsdt {
    return Intl.message(
      'USDT',
      name: 'withdrawalMethodUsdt',
      desc: '',
      args: [],
    );
  }

  /// `Bank card`
  String get withdrawalMethodBank {
    return Intl.message(
      'Bank card',
      name: 'withdrawalMethodBank',
      desc: '',
      args: [],
    );
  }

  /// `Plan warning. Click to view details`
  String get subscriptionWarningTooltip {
    return Intl.message(
      'Plan warning. Click to view details',
      name: 'subscriptionWarningTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Plan status is normal. Click to view details`
  String get subscriptionNormalTooltip {
    return Intl.message(
      'Plan status is normal. Click to view details',
      name: 'subscriptionNormalTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Plan warning`
  String get subscriptionWarningTitle {
    return Intl.message(
      'Plan warning',
      name: 'subscriptionWarningTitle',
      desc: '',
      args: [],
    );
  }

  /// `Plan status normal`
  String get subscriptionStatusNormalTitle {
    return Intl.message(
      'Plan status normal',
      name: 'subscriptionStatusNormalTitle',
      desc: '',
      args: [],
    );
  }

  /// `Only {remaining} GB remains, which is below 10 GB. Purchase or renew a plan soon.`
  String subscriptionLowTrafficWarning(Object remaining) {
    return Intl.message(
      'Only $remaining GB remains, which is below 10 GB. Purchase or renew a plan soon.',
      name: 'subscriptionLowTrafficWarning',
      desc: '',
      args: [remaining],
    );
  }

  /// `Your plan expires on {date}, in less than 3 days. Renew it soon.`
  String subscriptionExpiringWarning(Object date) {
    return Intl.message(
      'Your plan expires on $date, in less than 3 days. Renew it soon.',
      name: 'subscriptionExpiringWarning',
      desc: '',
      args: [date],
    );
  }

  /// `Your plan expired on {date}. Renew it to continue using the service.`
  String subscriptionExpiredWarning(Object date) {
    return Intl.message(
      'Your plan expired on $date. Renew it to continue using the service.',
      name: 'subscriptionExpiredWarning',
      desc: '',
      args: [date],
    );
  }

  /// `Your remaining traffic and plan validity are both in a normal state.`
  String get subscriptionStatusNormalMessage {
    return Intl.message(
      'Your remaining traffic and plan validity are both in a normal state.',
      name: 'subscriptionStatusNormalMessage',
      desc: '',
      args: [],
    );
  }

  /// `Renew`
  String get renewPlanAction {
    return Intl.message('Renew', name: 'renewPlanAction', desc: '', args: []);
  }

  /// `Reset traffic`
  String get resetTrafficAction {
    return Intl.message(
      'Reset traffic',
      name: 'resetTrafficAction',
      desc: '',
      args: [],
    );
  }

  /// `Change plan`
  String get changePlanAction {
    return Intl.message(
      'Change plan',
      name: 'changePlanAction',
      desc: '',
      args: [],
    );
  }

  /// `Upgrade`
  String get upgradePlanAction {
    return Intl.message(
      'Upgrade',
      name: 'upgradePlanAction',
      desc: '',
      args: [],
    );
  }

  /// `Renewal notice`
  String get renewalNoticeTitle {
    return Intl.message(
      'Renewal notice',
      name: 'renewalNoticeTitle',
      desc: '',
      args: [],
    );
  }

  /// `A renewal order only extends the plan expiry date and does not reset used traffic. Choose Reset traffic if you need to restore the plan quota.`
  String get renewalDoesNotResetTraffic {
    return Intl.message(
      'A renewal order only extends the plan expiry date and does not reset used traffic. Choose Reset traffic if you need to restore the plan quota.',
      name: 'renewalDoesNotResetTraffic',
      desc: '',
      args: [],
    );
  }

  /// `Select a renewal period`
  String get selectRenewalPeriod {
    return Intl.message(
      'Select a renewal period',
      name: 'selectRenewalPeriod',
      desc: '',
      args: [],
    );
  }

  /// `This plan does not currently support renewal`
  String get renewalUnavailable {
    return Intl.message(
      'This plan does not currently support renewal',
      name: 'renewalUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `This plan does not currently support traffic reset`
  String get trafficResetUnavailable {
    return Intl.message(
      'This plan does not currently support traffic reset',
      name: 'trafficResetUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `The current plan could not be found. Refresh and try again`
  String get subscriptionPlanUnavailable {
    return Intl.message(
      'The current plan could not be found. Refresh and try again',
      name: 'subscriptionPlanUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `Next plan reset: {date}`
  String nextPlanResetAt(Object date) {
    return Intl.message(
      'Next plan reset: $date',
      name: 'nextPlanResetAt',
      desc: '',
      args: [date],
    );
  }

  /// `Close`
  String get closeAction {
    return Intl.message('Close', name: 'closeAction', desc: '', args: []);
  }

  /// `Announcement center`
  String get announcementCenter {
    return Intl.message(
      'Announcement center',
      name: 'announcementCenter',
      desc: '',
      args: [],
    );
  }

  /// `View announcements`
  String get announcementTooltip {
    return Intl.message(
      'View announcements',
      name: 'announcementTooltip',
      desc: '',
      args: [],
    );
  }

  /// `No announcements`
  String get noAnnouncements {
    return Intl.message(
      'No announcements',
      name: 'noAnnouncements',
      desc: '',
      args: [],
    );
  }

  /// `Latest announcements are unavailable in offline mode`
  String get announcementUnavailableOffline {
    return Intl.message(
      'Latest announcements are unavailable in offline mode',
      name: 'announcementUnavailableOffline',
      desc: '',
      args: [],
    );
  }

  /// `Don't remind me again today`
  String get doNotRemindToday {
    return Intl.message(
      'Don\'t remind me again today',
      name: 'doNotRemindToday',
      desc: '',
      args: [],
    );
  }

  /// `Previous`
  String get previousAnnouncement {
    return Intl.message(
      'Previous',
      name: 'previousAnnouncement',
      desc: '',
      args: [],
    );
  }

  /// `Next`
  String get nextAnnouncement {
    return Intl.message('Next', name: 'nextAnnouncement', desc: '', args: []);
  }

  /// `{current} / {total}`
  String announcementPosition(Object current, Object total) {
    return Intl.message(
      '$current / $total',
      name: 'announcementPosition',
      desc: '',
      args: [current, total],
    );
  }

  /// `VPN acceleration is active and protecting your network connections`
  String get realTimeConnectionsSubtitle {
    return Intl.message(
      'VPN acceleration is active and protecting your network connections',
      name: 'realTimeConnectionsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Live connections`
  String get liveConnectionList {
    return Intl.message(
      'Live connections',
      name: 'liveConnectionList',
      desc: '',
      args: [],
    );
  }

  /// `{count} connections`
  String liveConnectionsCount(Object count) {
    return Intl.message(
      '$count connections',
      name: 'liveConnectionsCount',
      desc: '',
      args: [count],
    );
  }

  /// `Search domain, IP, rule, or node`
  String get searchConnectionsHint {
    return Intl.message(
      'Search domain, IP, rule, or node',
      name: 'searchConnectionsHint',
      desc: '',
      args: [],
    );
  }

  /// `Auto refresh`
  String get autoRefresh {
    return Intl.message(
      'Auto refresh',
      name: 'autoRefresh',
      desc: '',
      args: [],
    );
  }

  /// `Unable to load live connections. Try again later`
  String get liveConnectionsFailed {
    return Intl.message(
      'Unable to load live connections. Try again later',
      name: 'liveConnectionsFailed',
      desc: '',
      args: [],
    );
  }

  /// `Close all connections`
  String get closeAllConnections {
    return Intl.message(
      'Close all connections',
      name: 'closeAllConnections',
      desc: '',
      args: [],
    );
  }

  /// `All current connections will be closed. Apps may reconnect automatically.`
  String get closeAllConnectionsDescription {
    return Intl.message(
      'All current connections will be closed. Apps may reconnect automatically.',
      name: 'closeAllConnectionsDescription',
      desc: '',
      args: [],
    );
  }

  /// `Domain / service`
  String get domainOrService {
    return Intl.message(
      'Domain / service',
      name: 'domainOrService',
      desc: '',
      args: [],
    );
  }

  /// `Node`
  String get nodeLabel {
    return Intl.message('Node', name: 'nodeLabel', desc: '', args: []);
  }

  /// `Download speed`
  String get downloadSpeed {
    return Intl.message(
      'Download speed',
      name: 'downloadSpeed',
      desc: '',
      args: [],
    );
  }

  /// `Upload speed`
  String get uploadSpeed {
    return Intl.message(
      'Upload speed',
      name: 'uploadSpeed',
      desc: '',
      args: [],
    );
  }

  /// `Downloaded`
  String get downloaded {
    return Intl.message('Downloaded', name: 'downloaded', desc: '', args: []);
  }

  /// `Uploaded`
  String get uploaded {
    return Intl.message('Uploaded', name: 'uploaded', desc: '', args: []);
  }

  /// `Access time`
  String get accessTime {
    return Intl.message('Access time', name: 'accessTime', desc: '', args: []);
  }

  /// `Active connections`
  String get currentActiveConnections {
    return Intl.message(
      'Active connections',
      name: 'currentActiveConnections',
      desc: '',
      args: [],
    );
  }

  /// `Current node latency`
  String get currentNodeDelay {
    return Intl.message(
      'Current node latency',
      name: 'currentNodeDelay',
      desc: '',
      args: [],
    );
  }

  /// `No active connections. Start the VPN and browse to see them here`
  String get noActiveConnections {
    return Intl.message(
      'No active connections. Start the VPN and browse to see them here',
      name: 'noActiveConnections',
      desc: '',
      args: [],
    );
  }

  /// `No matching connections`
  String get noMatchingConnections {
    return Intl.message(
      'No matching connections',
      name: 'noMatchingConnections',
      desc: '',
      args: [],
    );
  }

  /// `View details`
  String get viewDetails {
    return Intl.message(
      'View details',
      name: 'viewDetails',
      desc: '',
      args: [],
    );
  }

  /// `Close connection`
  String get closeConnection {
    return Intl.message(
      'Close connection',
      name: 'closeConnection',
      desc: '',
      args: [],
    );
  }

  /// `Connection details`
  String get connectionDetails {
    return Intl.message(
      'Connection details',
      name: 'connectionDetails',
      desc: '',
      args: [],
    );
  }

  /// `Generate a Mihomo rule from this connection`
  String get generateMihomoRule {
    return Intl.message(
      'Generate a Mihomo rule from this connection',
      name: 'generateMihomoRule',
      desc: '',
      args: [],
    );
  }

  /// `Rule type`
  String get ruleType {
    return Intl.message('Rule type', name: 'ruleType', desc: '', args: []);
  }

  /// `DOMAIN matches the exact domain; DOMAIN-SUFFIX also matches subdomains`
  String get ruleTypeHelp {
    return Intl.message(
      'DOMAIN matches the exact domain; DOMAIN-SUFFIX also matches subdomains',
      name: 'ruleTypeHelp',
      desc: '',
      args: [],
    );
  }

  /// `Match content`
  String get matchContent {
    return Intl.message(
      'Match content',
      name: 'matchContent',
      desc: '',
      args: [],
    );
  }

  /// `Target policy`
  String get targetPolicy {
    return Intl.message(
      'Target policy',
      name: 'targetPolicy',
      desc: '',
      args: [],
    );
  }

  /// `Global mode is active. Adding this rule switches to Rule mode: this connection uses the policy above and all other traffic uses your selected proxy group.`
  String get globalRuleModeSwitchHint {
    return Intl.message(
      'Global mode is active. Adding this rule switches to Rule mode: this connection uses the policy above and all other traffic uses your selected proxy group.',
      name: 'globalRuleModeSwitchHint',
      desc: '',
      args: [],
    );
  }

  /// `Other traffic policy`
  String get otherTrafficPolicy {
    return Intl.message(
      'Other traffic policy',
      name: 'otherTrafficPolicy',
      desc: '',
      args: [],
    );
  }

  /// `Select a proxy group`
  String get selectProxyGroup {
    return Intl.message(
      'Select a proxy group',
      name: 'selectProxyGroup',
      desc: '',
      args: [],
    );
  }

  /// `This profile has no proxy group available for the global fallback rule`
  String get noProxyGroupForFallback {
    return Intl.message(
      'This profile has no proxy group available for the global fallback rule',
      name: 'noProxyGroupForFallback',
      desc: '',
      args: [],
    );
  }

  /// `There is no current profile where this rule can be saved`
  String get noProfileForRule {
    return Intl.message(
      'There is no current profile where this rule can be saved',
      name: 'noProfileForRule',
      desc: '',
      args: [],
    );
  }

  /// `This rule already exists. The profile was reapplied`
  String get connectionRuleAlreadyExists {
    return Intl.message(
      'This rule already exists. The profile was reapplied',
      name: 'connectionRuleAlreadyExists',
      desc: '',
      args: [],
    );
  }

  /// `Rule added and switched to Rule mode`
  String get connectionRuleAppliedAndSwitched {
    return Intl.message(
      'Rule added and switched to Rule mode',
      name: 'connectionRuleAppliedAndSwitched',
      desc: '',
      args: [],
    );
  }

  /// `Rule added and applied`
  String get connectionRuleApplied {
    return Intl.message(
      'Rule added and applied',
      name: 'connectionRuleApplied',
      desc: '',
      args: [],
    );
  }

  /// `Reject`
  String get reject {
    return Intl.message('Reject', name: 'reject', desc: '', args: []);
  }

  /// `Campus network mode`
  String get campusNetworkMode {
    return Intl.message(
      'Campus network mode',
      name: 'campusNetworkMode',
      desc: '',
      args: [],
    );
  }

  /// `Switch to dedicated entry routes on campus networks`
  String get campusNetworkModeSubtitle {
    return Intl.message(
      'Switch to dedicated entry routes on campus networks',
      name: 'campusNetworkModeSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Enable campus network mode`
  String get campusNetworkSwitch {
    return Intl.message(
      'Enable campus network mode',
      name: 'campusNetworkSwitch',
      desc: '',
      args: [],
    );
  }

  /// `Maps node domains to the selected entry route when enabled`
  String get campusNetworkSwitchDescription {
    return Intl.message(
      'Maps node domains to the selected entry route when enabled',
      name: 'campusNetworkSwitchDescription',
      desc: '',
      args: [],
    );
  }

  /// `Entry route`
  String get campusNetworkLine {
    return Intl.message(
      'Entry route',
      name: 'campusNetworkLine',
      desc: '',
      args: [],
    );
  }

  /// `Route 1`
  String get campusNetworkLine1 {
    return Intl.message(
      'Route 1',
      name: 'campusNetworkLine1',
      desc: '',
      args: [],
    );
  }

  /// `Route 2`
  String get campusNetworkLine2 {
    return Intl.message(
      'Route 2',
      name: 'campusNetworkLine2',
      desc: '',
      args: [],
    );
  }

  /// `Route 3`
  String get campusNetworkLine3 {
    return Intl.message(
      'Route 3',
      name: 'campusNetworkLine3',
      desc: '',
      args: [],
    );
  }

  /// `When disabled, CDN resolution remains in use. Enabling or switching routes automatically reloads the core configuration.`
  String get campusNetworkInformation {
    return Intl.message(
      'When disabled, CDN resolution remains in use. Enabling or switching routes automatically reloads the core configuration.',
      name: 'campusNetworkInformation',
      desc: '',
      args: [],
    );
  }

  /// `Campus network mode is enabled and active`
  String get campusNetworkEnabled {
    return Intl.message(
      'Campus network mode is enabled and active',
      name: 'campusNetworkEnabled',
      desc: '',
      args: [],
    );
  }

  /// `Campus network mode is disabled`
  String get campusNetworkDisabled {
    return Intl.message(
      'Campus network mode is disabled',
      name: 'campusNetworkDisabled',
      desc: '',
      args: [],
    );
  }

  /// `Failed to apply campus network mode. Check your connection and try again`
  String get campusNetworkApplyFailed {
    return Intl.message(
      'Failed to apply campus network mode. Check your connection and try again',
      name: 'campusNetworkApplyFailed',
      desc: '',
      args: [],
    );
  }

  /// `Everyday network tools for a faster, easier online experience`
  String get practicalToolsSubtitle {
    return Intl.message(
      'Everyday network tools for a faster, easier online experience',
      name: 'practicalToolsSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Toolbox`
  String get toolbox {
    return Intl.message('Toolbox', name: 'toolbox', desc: '', args: []);
  }

  /// `Speed test`
  String get speedTest {
    return Intl.message('Speed test', name: 'speedTest', desc: '', args: []);
  }

  /// `Test your current connection with a third-party speed service`
  String get speedTestDescription {
    return Intl.message(
      'Test your current connection with a third-party speed service',
      name: 'speedTestDescription',
      desc: '',
      args: [],
    );
  }

  /// `Choose service`
  String get chooseSpeedTest {
    return Intl.message(
      'Choose service',
      name: 'chooseSpeedTest',
      desc: '',
      args: [],
    );
  }

  /// `CF preferred IP`
  String get cloudflarePreferredIp {
    return Intl.message(
      'CF preferred IP',
      name: 'cloudflarePreferredIp',
      desc: '',
      args: [],
    );
  }

  /// `Find faster Cloudflare edge addresses for this network`
  String get cloudflarePreferredIpDescription {
    return Intl.message(
      'Find faster Cloudflare edge addresses for this network',
      name: 'cloudflarePreferredIpDescription',
      desc: '',
      args: [],
    );
  }

  /// `Start scan`
  String get startOptimization {
    return Intl.message(
      'Start scan',
      name: 'startOptimization',
      desc: '',
      args: [],
    );
  }

  /// `IP lookup`
  String get ipLookup {
    return Intl.message('IP lookup', name: 'ipLookup', desc: '', args: []);
  }

  /// `View location, carrier, and other public IP details`
  String get ipLookupDescription {
    return Intl.message(
      'View location, carrier, and other public IP details',
      name: 'ipLookupDescription',
      desc: '',
      args: [],
    );
  }

  /// `Check now`
  String get queryNow {
    return Intl.message('Check now', name: 'queryNow', desc: '', args: []);
  }

  /// `Streaming access test`
  String get streamingUnlockTest {
    return Intl.message(
      'Streaming access test',
      name: 'streamingUnlockTest',
      desc: '',
      args: [],
    );
  }

  /// `Check streaming and AI service availability on this node`
  String get streamingUnlockTestDescription {
    return Intl.message(
      'Check streaming and AI service availability on this node',
      name: 'streamingUnlockTestDescription',
      desc: '',
      args: [],
    );
  }

  /// `Start test`
  String get startTest {
    return Intl.message('Start test', name: 'startTest', desc: '', args: []);
  }

  /// `Chain proxy`
  String get chainProxy {
    return Intl.message('Chain proxy', name: 'chainProxy', desc: '', args: []);
  }

  /// `Manage an additional SOCKS5 or HTTP egress proxy`
  String get chainProxyDescription {
    return Intl.message(
      'Manage an additional SOCKS5 or HTTP egress proxy',
      name: 'chainProxyDescription',
      desc: '',
      args: [],
    );
  }

  /// `Manage chain`
  String get manageChainProxy {
    return Intl.message(
      'Manage chain',
      name: 'manageChainProxy',
      desc: '',
      args: [],
    );
  }

  /// `Popular apps`
  String get popularApps {
    return Intl.message(
      'Popular apps',
      name: 'popularApps',
      desc: '',
      args: [],
    );
  }

  /// `Browse useful clients and companion apps`
  String get popularAppsDescription {
    return Intl.message(
      'Browse useful clients and companion apps',
      name: 'popularAppsDescription',
      desc: '',
      args: [],
    );
  }

  /// `View apps`
  String get viewApps {
    return Intl.message('View apps', name: 'viewApps', desc: '', args: []);
  }

  /// `Loading Cloudflare candidate IPs`
  String get optimizationPreparing {
    return Intl.message(
      'Loading Cloudflare candidate IPs',
      name: 'optimizationPreparing',
      desc: '',
      args: [],
    );
  }

  /// `Testing connection latency`
  String get optimizationLatency {
    return Intl.message(
      'Testing connection latency',
      name: 'optimizationLatency',
      desc: '',
      args: [],
    );
  }

  /// `Testing download speed`
  String get optimizationDownload {
    return Intl.message(
      'Testing download speed',
      name: 'optimizationDownload',
      desc: '',
      args: [],
    );
  }

  /// `Optimization complete`
  String get optimizationComplete {
    return Intl.message(
      'Optimization complete',
      name: 'optimizationComplete',
      desc: '',
      args: [],
    );
  }

  /// `No available Cloudflare IP was found. Check your connection and try again`
  String get optimizationFailed {
    return Intl.message(
      'No available Cloudflare IP was found. Check your connection and try again',
      name: 'optimizationFailed',
      desc: '',
      args: [],
    );
  }

  /// `Candidates`
  String get candidateCount {
    return Intl.message(
      'Candidates',
      name: 'candidateCount',
      desc: '',
      args: [],
    );
  }

  /// `Available`
  String get availableCount {
    return Intl.message(
      'Available',
      name: 'availableCount',
      desc: '',
      args: [],
    );
  }

  /// `Kept`
  String get keptCount {
    return Intl.message('Kept', name: 'keptCount', desc: '', args: []);
  }

  /// `Fastest download`
  String get fastestDownload {
    return Intl.message(
      'Fastest download',
      name: 'fastestDownload',
      desc: '',
      args: [],
    );
  }

  /// `Lowest latency`
  String get lowestLatency {
    return Intl.message(
      'Lowest latency',
      name: 'lowestLatency',
      desc: '',
      args: [],
    );
  }

  /// `Highest latency`
  String get highestLatency {
    return Intl.message(
      'Highest latency',
      name: 'highestLatency',
      desc: '',
      args: [],
    );
  }

  /// `IP address`
  String get ipAddress {
    return Intl.message('IP address', name: 'ipAddress', desc: '', args: []);
  }

  /// `Region`
  String get region {
    return Intl.message('Region', name: 'region', desc: '', args: []);
  }

  /// `Scan again`
  String get rerunOptimization {
    return Intl.message(
      'Scan again',
      name: 'rerunOptimization',
      desc: '',
      args: [],
    );
  }

  /// `Apply all`
  String get applyPreferredIps {
    return Intl.message(
      'Apply all',
      name: 'applyPreferredIps',
      desc: '',
      args: [],
    );
  }

  /// `No target domain configured`
  String get cfTargetMissingTitle {
    return Intl.message(
      'No target domain configured',
      name: 'cfTargetMissingTitle',
      desc: '',
      args: [],
    );
  }

  /// `Add the node domains that CF optimization may replace to the remote configuration first.`
  String get cfTargetMissingMessage {
    return Intl.message(
      'Add the node domains that CF optimization may replace to the remote configuration first.',
      name: 'cfTargetMissingMessage',
      desc: '',
      args: [],
    );
  }

  /// `Validating target domains against preferred IPs`
  String get validatingTargets {
    return Intl.message(
      'Validating target domains against preferred IPs',
      name: 'validatingTargets',
      desc: '',
      args: [],
    );
  }

  /// `Preferred CF IPs applied and the core configuration reloaded`
  String get cfApplySuccess {
    return Intl.message(
      'Preferred CF IPs applied and the core configuration reloaded',
      name: 'cfApplySuccess',
      desc: '',
      args: [],
    );
  }

  /// `Failed to apply preferred CF IPs. The previous configuration was restored`
  String get cfApplyFailed {
    return Intl.message(
      'Failed to apply preferred CF IPs. The previous configuration was restored',
      name: 'cfApplyFailed',
      desc: '',
      args: [],
    );
  }

  /// `Preferred IPs failed TLS validation for the target domains. Nothing was changed`
  String get cfTargetValidationFailed {
    return Intl.message(
      'Preferred IPs failed TLS validation for the target domains. Nothing was changed',
      name: 'cfTargetValidationFailed',
      desc: '',
      args: [],
    );
  }

  /// `Public IP`
  String get publicIp {
    return Intl.message('Public IP', name: 'publicIp', desc: '', args: []);
  }

  /// `Country/region`
  String get countryRegion {
    return Intl.message(
      'Country/region',
      name: 'countryRegion',
      desc: '',
      args: [],
    );
  }

  /// `State/city`
  String get provinceCity {
    return Intl.message('State/city', name: 'provinceCity', desc: '', args: []);
  }

  /// `Carrier`
  String get carrier {
    return Intl.message('Carrier', name: 'carrier', desc: '', args: []);
  }

  /// `Organization`
  String get organization {
    return Intl.message(
      'Organization',
      name: 'organization',
      desc: '',
      args: [],
    );
  }

  /// `ASN`
  String get asnLabel {
    return Intl.message('ASN', name: 'asnLabel', desc: '', args: []);
  }

  /// `Time zone`
  String get timezoneLabel {
    return Intl.message('Time zone', name: 'timezoneLabel', desc: '', args: []);
  }

  /// `Data source`
  String get dataSource {
    return Intl.message('Data source', name: 'dataSource', desc: '', args: []);
  }

  /// `IP lookup failed. Check your connection and try again`
  String get ipLookupFailed {
    return Intl.message(
      'IP lookup failed. Check your connection and try again',
      name: 'ipLookupFailed',
      desc: '',
      args: [],
    );
  }

  /// `Platforms`
  String get platformCount {
    return Intl.message('Platforms', name: 'platformCount', desc: '', args: []);
  }

  /// `Completed`
  String get completedCount {
    return Intl.message(
      'Completed',
      name: 'completedCount',
      desc: '',
      args: [],
    );
  }

  /// `Pending`
  String get pendingTest {
    return Intl.message('Pending', name: 'pendingTest', desc: '', args: []);
  }

  /// `Test all`
  String get testAll {
    return Intl.message('Test all', name: 'testAll', desc: '', args: []);
  }

  /// `Chain proxy is not enabled`
  String get chainProxyDisabled {
    return Intl.message(
      'Chain proxy is not enabled',
      name: 'chainProxyDisabled',
      desc: '',
      args: [],
    );
  }

  /// `When enabled, proxied traffic goes through the selected subscription node and then exits through this chain proxy. Only one can run at a time.`
  String get chainProxySessionNotice {
    return Intl.message(
      'When enabled, proxied traffic goes through the selected subscription node and then exits through this chain proxy. Only one can run at a time.',
      name: 'chainProxySessionNotice',
      desc: '',
      args: [],
    );
  }

  /// `Add proxy`
  String get addProxy {
    return Intl.message('Add proxy', name: 'addProxy', desc: '', args: []);
  }

  /// `Protocol`
  String get protocolLabel {
    return Intl.message('Protocol', name: 'protocolLabel', desc: '', args: []);
  }

  /// `Server`
  String get proxyServer {
    return Intl.message('Server', name: 'proxyServer', desc: '', args: []);
  }

  /// `Username`
  String get username {
    return Intl.message('Username', name: 'username', desc: '', args: []);
  }

  /// `Enable`
  String get enableProxy {
    return Intl.message('Enable', name: 'enableProxy', desc: '', args: []);
  }

  /// `Stop`
  String get disableProxy {
    return Intl.message('Stop', name: 'disableProxy', desc: '', args: []);
  }

  /// `Chain proxy is running`
  String get chainProxyActive {
    return Intl.message(
      'Chain proxy is running',
      name: 'chainProxyActive',
      desc: '',
      args: [],
    );
  }

  /// `Other entries are locked while a chain proxy is running`
  String get chainProxyLocked {
    return Intl.message(
      'Other entries are locked while a chain proxy is running',
      name: 'chainProxyLocked',
      desc: '',
      args: [],
    );
  }

  /// `Validating proxy connection…`
  String get validatingProxy {
    return Intl.message(
      'Validating proxy connection…',
      name: 'validatingProxy',
      desc: '',
      args: [],
    );
  }

  /// `Cannot connect through this proxy. Check the server, port, username, and password`
  String get proxyValidationFailed {
    return Intl.message(
      'Cannot connect through this proxy. Check the server, port, username, and password',
      name: 'proxyValidationFailed',
      desc: '',
      args: [],
    );
  }

  /// `Incorrect protocol. Detected protocol:`
  String get proxyProtocolMismatch {
    return Intl.message(
      'Incorrect protocol. Detected protocol:',
      name: 'proxyProtocolMismatch',
      desc: '',
      args: [],
    );
  }

  /// `This proxy name already exists`
  String get proxyNameDuplicate {
    return Intl.message(
      'This proxy name already exists',
      name: 'proxyNameDuplicate',
      desc: '',
      args: [],
    );
  }

  /// `Chain proxy started`
  String get chainProxyEnabled {
    return Intl.message(
      'Chain proxy started',
      name: 'chainProxyEnabled',
      desc: '',
      args: [],
    );
  }

  /// `Chain proxy stopped`
  String get chainProxyStopped {
    return Intl.message(
      'Chain proxy stopped',
      name: 'chainProxyStopped',
      desc: '',
      args: [],
    );
  }

  /// `Failed to apply the core configuration. The previous configuration was restored`
  String get chainProxyApplyFailed {
    return Intl.message(
      'Failed to apply the core configuration. The previous configuration was restored',
      name: 'chainProxyApplyFailed',
      desc: '',
      args: [],
    );
  }

  /// `Chain proxy connectivity test failed. It was disabled and the previous configuration was restored`
  String get chainProxyConnectivityFailed {
    return Intl.message(
      'Chain proxy connectivity test failed. It was disabled and the previous configuration was restored',
      name: 'chainProxyConnectivityFailed',
      desc: '',
      args: [],
    );
  }

  /// `The chain proxy failed and the previous configuration could not be restored. Restart the app`
  String get chainProxyRollbackFailed {
    return Intl.message(
      'The chain proxy failed and the previous configuration could not be restored. Restart the app',
      name: 'chainProxyRollbackFailed',
      desc: '',
      args: [],
    );
  }

  /// `Switch the outbound mode to Rule or Global first`
  String get chainProxyDirectModeUnsupported {
    return Intl.message(
      'Switch the outbound mode to Rule or Global first',
      name: 'chainProxyDirectModeUnsupported',
      desc: '',
      args: [],
    );
  }

  /// `No chain proxies`
  String get noChainProxy {
    return Intl.message(
      'No chain proxies',
      name: 'noChainProxy',
      desc: '',
      args: [],
    );
  }

  /// `Add a SOCKS5 or HTTP proxy to get started.`
  String get noChainProxyDescription {
    return Intl.message(
      'Add a SOCKS5 or HTTP proxy to get started.',
      name: 'noChainProxyDescription',
      desc: '',
      args: [],
    );
  }

  /// `Enter a valid port`
  String get invalidPort {
    return Intl.message(
      'Enter a valid port',
      name: 'invalidPort',
      desc: '',
      args: [],
    );
  }

  /// `This field is required`
  String get requiredField {
    return Intl.message(
      'This field is required',
      name: 'requiredField',
      desc: '',
      args: [],
    );
  }

  /// `Testing`
  String get testingStatus {
    return Intl.message('Testing', name: 'testingStatus', desc: '', args: []);
  }

  /// `Web page reachable`
  String get streamingUnlocked {
    return Intl.message(
      'Web page reachable',
      name: 'streamingUnlocked',
      desc: '',
      args: [],
    );
  }

  /// `Web page reachable, deep status unconfirmed`
  String get streamingReachable {
    return Intl.message(
      'Web page reachable, deep status unconfirmed',
      name: 'streamingReachable',
      desc: '',
      args: [],
    );
  }

  /// `Region restricted`
  String get streamingRestricted {
    return Intl.message(
      'Region restricted',
      name: 'streamingRestricted',
      desc: '',
      args: [],
    );
  }

  /// `Connection failed`
  String get streamingFailed {
    return Intl.message(
      'Connection failed',
      name: 'streamingFailed',
      desc: '',
      args: [],
    );
  }

  /// `Test timed out. Try again`
  String get streamingTimedOut {
    return Intl.message(
      'Test timed out. Try again',
      name: 'streamingTimedOut',
      desc: '',
      args: [],
    );
  }

  /// `Network connection failed`
  String get streamingNetworkError {
    return Intl.message(
      'Network connection failed',
      name: 'streamingNetworkError',
      desc: '',
      args: [],
    );
  }

  /// `Service is temporarily unavailable`
  String get streamingServiceError {
    return Intl.message(
      'Service is temporarily unavailable',
      name: 'streamingServiceError',
      desc: '',
      args: [],
    );
  }

  /// `Web page reachable, deep check timed out`
  String get streamingReachableProbeTimedOut {
    return Intl.message(
      'Web page reachable, deep check timed out',
      name: 'streamingReachableProbeTimedOut',
      desc: '',
      args: [],
    );
  }

  /// `Web page reachable, deep status unconfirmed`
  String get streamingReachableProbeFailed {
    return Intl.message(
      'Web page reachable, deep status unconfirmed',
      name: 'streamingReachableProbeFailed',
      desc: '',
      args: [],
    );
  }

  /// `Exit region`
  String get streamingExitRegion {
    return Intl.message(
      'Exit region',
      name: 'streamingExitRegion',
      desc: '',
      args: [],
    );
  }

  /// `Start acceleration and select a proxy node before testing`
  String get streamingProxyRequired {
    return Intl.message(
      'Start acceleration and select a proxy node before testing',
      name: 'streamingProxyRequired',
      desc: '',
      args: [],
    );
  }
}

class AppLocalizationDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'en'),
      Locale.fromSubtags(languageCode: 'ja'),
      Locale.fromSubtags(languageCode: 'ru'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}
