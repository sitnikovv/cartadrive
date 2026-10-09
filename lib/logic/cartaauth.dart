import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/settings.dart';

const driveScopes = <String>[
  'https://www.googleapis.com/auth/drive.appdata',
  'https://www.googleapis.com/auth/drive.file',
];

/// A saved account identifies the local shelf. A Google session is required
/// separately for Drive requests and is never needed to open that shelf.
class CartaAuth extends ChangeNotifier {
  CartaAuth._(this._prefs, this._google, this._tokenWithoutPrompt)
      : _savedAccount = _readSavedAccount(_prefs);

  static const _accountKey = '$appId.activeAccount';

  static Map<String, String>? _readSavedAccount(SharedPreferences prefs) {
    final value = prefs.getString(_accountKey);
    if (value == null) return null;
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final id = data['id'];
      final email = data['email'];
      if (id is String && id.isNotEmpty && email is String) {
        return {'id': id, 'email': email};
      }
    } catch (_) {
      // An invalid local account record cannot authorize Drive access.
    }
    return null;
  }

  static Future<String?> _readTokenWithoutPrompt(String email) async {
    final token = await GoogleSignInPlatform.instance.getTokens(
      email: email,
      shouldRecoverAuth: false,
    );
    return token.accessToken;
  }

  static Future<CartaAuth> create({
    GoogleSignIn? google,
    Future<String?> Function(String email)? tokenWithoutPrompt,
    bool restoreOnline = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final auth = CartaAuth._(
      prefs,
      google ??
          GoogleSignIn(
            scopes: driveScopes,
            serverClientId:
                const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID').isEmpty
                    ? null
                    : const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
          ),
      tokenWithoutPrompt ?? _readTokenWithoutPrompt,
    );
    if (restoreOnline && auth.hasSavedAccount) {
      unawaited(auth.ensureGoogleSession());
    }
    return auth;
  }

  final SharedPreferences _prefs;
  final GoogleSignIn _google;
  final Future<String?> Function(String email) _tokenWithoutPrompt;
  Map<String, String>? _savedAccount;
  GoogleSignInAccount? _googleAccount;
  Future<bool>? _restoring;
  int _sessionVersion = 0;
  String lastError = '';

  String? get uid => _savedAccount?['id'];
  String? get email => _googleAccount?.email ?? _savedAccount?['email'];
  bool get hasSavedAccount => uid != null;
  bool get hasGoogleSession => uid != null && _googleAccount?.id == uid;

  Future<void> _saveAccount(GoogleSignInAccount account) async {
    final saved = {'id': account.id, 'email': account.email};
    await _prefs.setString(_accountKey, jsonEncode(saved));
    _savedAccount = saved;
    _googleAccount = account;
    _sessionVersion++;
    notifyListeners();
  }

  /// Restores Drive access without opening any account or consent dialog.
  /// The local shelf remains available if this cannot be completed.
  Future<bool> ensureGoogleSession() {
    final expectedUid = uid;
    if (expectedUid == null) return Future.value(false);
    if (hasGoogleSession) return Future.value(true);
    if (_restoring != null) return _restoring!;
    final future = _restoreAccount(expectedUid, _sessionVersion);
    _restoring = future;
    return future.whenComplete(() {
      if (identical(_restoring, future)) _restoring = null;
    });
  }

  Future<bool> _restoreAccount(String expectedUid, int version) async {
    try {
      final account = await _google.signInSilently(suppressErrors: false);
      if (account == null || account.id != expectedUid) return false;
      final token = await _tokenWithoutPrompt(account.email);
      if (token == null || token.isEmpty) return false;
      if (uid != expectedUid || _sessionVersion != version) return false;
      _googleAccount = account;
      lastError = '';
      notifyListeners();
      return true;
    } catch (error) {
      lastError = error.toString();
      return false;
    }
  }

  Future<String> accessToken() async {
    if (!await ensureGoogleSession()) {
      throw StateError('Google Drive is unavailable; showing saved bookshelf');
    }
    try {
      final token = await _tokenWithoutPrompt(_googleAccount!.email);
      if (token == null || token.isEmpty) {
        throw StateError('Google Drive access is not available');
      }
      return token;
    } catch (error) {
      _googleAccount = null;
      lastError = error.toString();
      notifyListeners();
      throw StateError('Google Drive needs to be reconnected from Settings');
    }
  }

  Future<void> invalidateAccessToken(String token) =>
      GoogleSignInPlatform.instance.clearAuthCache(token: token);

  /// This is the only path that can show Google account or consent UI.
  Future<GoogleSignInAccount?> signInWithGoogle() async {
    lastError = '';
    final version = _sessionVersion;
    try {
      // A previous failed restore may have selected another account inside the
      // plugin. Start a fresh, user-initiated account selection instead.
      await _google.signOut();
      final account = await _google.signIn();
      if (account == null) return null;
      if (uid != null && uid != account.id) {
        await _google.signOut();
        lastError = 'Choose the account already used for this bookshelf, '
            'or sign out before switching accounts';
        return null;
      }
      final token = (await account.authentication).accessToken;
      if (token == null || token.isEmpty) {
        throw StateError('Google did not provide a Drive access token');
      }
      if (_sessionVersion != version) return null;
      await _saveAccount(account);
      return account;
    } on PlatformException catch (error) {
      lastError = '${error.code}: ${error.message ?? ''}';
    } catch (error) {
      lastError = error.toString();
    }
    return null;
  }

  Future<void> signOut() async {
    _sessionVersion++;
    _savedAccount = null;
    _googleAccount = null;
    await _prefs.remove(_accountKey);
    notifyListeners();
    try {
      await _google.signOut();
    } catch (error) {
      lastError = error.toString();
    }
  }
}
