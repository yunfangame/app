import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const macIdentityBundleIdentifier = 'com.fengwo.accelerator';
const macIdentityDebugBundleIdentifier = 'com.fengwo.accelerator.debug';
const macIdentityKeychainService = kDebugMode
    ? macIdentityDebugBundleIdentifier
    : macIdentityBundleIdentifier;
const identitySecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(accountName: macIdentityKeychainService),
);
