import 'dart:convert';
import 'dart:io';

import 'package:cartadrive/logic/cartaauth.dart';
import 'package:cartadrive/model/cartabook.dart';
import 'package:cartadrive/model/cartalibrary.dart';
import 'package:cartadrive/model/cartasection.dart';
import 'package:cartadrive/model/cartaserver.dart';
import 'package:cartadrive/repo/local_shelf_cache.dart';
import 'package:cartadrive/shared/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineGoogleSignIn implements GoogleSignIn {
  OfflineGoogleSignIn({this.silentAccount, this.interactiveAccount});

  final GoogleSignInAccount? silentAccount;
  final GoogleSignInAccount? interactiveAccount;
  int silentCalls = 0;
  int interactiveCalls = 0;

  @override
  Future<GoogleSignInAccount?> signInSilently(
      {bool suppressErrors = true, bool reAuthenticate = false}) async {
    silentCalls++;
    return silentAccount;
  }

  @override
  Future<GoogleSignInAccount?> signIn() async {
    interactiveCalls++;
    return interactiveAccount;
  }

  @override
  Future<bool> canAccessScopes(List<String> scopes,
          {String? accessToken}) async =>
      throw UnimplementedError('Android does not implement canAccessScopes');

  @override
  Future<bool> requestScopes(List<String> scopes) async =>
      throw StateError('Scopes are requested during Android sign-in');

  @override
  Future<GoogleSignInAccount?> signOut() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestGoogleAccount implements GoogleSignInAccount {
  TestGoogleAccount(this.id, this.email);

  @override
  final String id;
  @override
  final String email;

  @override
  Future<GoogleSignInAuthentication> get authentication async =>
      TestGoogleAuthentication();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestGoogleAuthentication implements GoogleSignInAuthentication {
  @override
  String? get accessToken => 'test-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingGoogleSignInPlatform extends GoogleSignInPlatform {
  final recoverFlags = <bool?>[];

  @override
  Future<GoogleSignInTokenData> getTokens(
      {required String email, bool? shouldRecoverAuth}) async {
    recoverFlags.add(shouldRecoverAuth);
    return GoogleSignInTokenData(accessToken: 'test-token');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cached account remains open when silent Google sign-in fails',
      () async {
    SharedPreferences.setMockInitialValues({
      '$appId.activeAccount':
          jsonEncode({'id': 'user-one', 'email': 'reader@example.org'}),
    });
    final google = OfflineGoogleSignIn();
    final auth = await CartaAuth.create(
      google: google,
      tokenWithoutPrompt: (_) async => null,
      restoreOnline: false,
    );

    expect(auth.hasSavedAccount, isTrue);
    expect(auth.uid, 'user-one');
    expect(auth.email, 'reader@example.org');
    expect(await auth.ensureGoogleSession(), isFalse);
    expect(google.silentCalls, 1);
    expect(auth.hasSavedAccount, isTrue);
    expect(google.interactiveCalls, 0);

    await auth.signOut();
    expect(auth.hasSavedAccount, isFalse);
    final googleAfterLogout = OfflineGoogleSignIn();
    final reopened = await CartaAuth.create(
      google: googleAfterLogout,
      tokenWithoutPrompt: (_) async => null,
    );
    expect(reopened.hasSavedAccount, isFalse);
    expect(googleAfterLogout.silentCalls, 0);
  });

  test('silent restore accepts only the saved account and never opens sign-in',
      () async {
    SharedPreferences.setMockInitialValues({
      '$appId.activeAccount':
          jsonEncode({'id': 'user-one', 'email': 'reader@example.org'}),
    });
    final wrongAccount = OfflineGoogleSignIn(
      silentAccount: TestGoogleAccount('user-two', 'other@example.org'),
    );
    final auth = await CartaAuth.create(
      google: wrongAccount,
      tokenWithoutPrompt: (_) async => 'test-token',
      restoreOnline: false,
    );
    expect(await auth.ensureGoogleSession(), isFalse);
    expect(auth.hasSavedAccount, isTrue);
    expect(auth.hasGoogleSession, isFalse);
    expect(wrongAccount.interactiveCalls, 0);

    final rightAccount = OfflineGoogleSignIn(
      silentAccount: TestGoogleAccount('user-one', 'reader@example.org'),
    );
    final reopened = await CartaAuth.create(
      google: rightAccount,
      tokenWithoutPrompt: (_) async => 'test-token',
      restoreOnline: false,
    );
    expect(await reopened.ensureGoogleSession(), isTrue);
    expect(await reopened.accessToken(), 'test-token');
    expect(rightAccount.interactiveCalls, 0);
  });

  test('background Drive tokens never request an authentication dialog',
      () async {
    SharedPreferences.setMockInitialValues({
      '$appId.activeAccount':
          jsonEncode({'id': 'user-one', 'email': 'reader@example.org'}),
    });
    final previousPlatform = GoogleSignInPlatform.instance;
    final platform = RecordingGoogleSignInPlatform();
    GoogleSignInPlatform.instance = platform;
    addTearDown(() => GoogleSignInPlatform.instance = previousPlatform);
    final google = OfflineGoogleSignIn(
      silentAccount: TestGoogleAccount('user-one', 'reader@example.org'),
    );
    final auth = await CartaAuth.create(google: google, restoreOnline: false);

    expect(await auth.ensureGoogleSession(), isTrue);
    expect(await auth.accessToken(), 'test-token');
    expect(platform.recoverFlags, [false, false]);
    expect(google.interactiveCalls, 0);
  });

  test('Android sign-in works without the unsupported scope check', () async {
    SharedPreferences.setMockInitialValues({});
    final google = OfflineGoogleSignIn(
      interactiveAccount: TestGoogleAccount('user-one', 'reader@example.org'),
    );
    final auth = await CartaAuth.create(
      google: google,
      tokenWithoutPrompt: (_) async => 'test-token',
    );
    expect(google.interactiveCalls, 0);
    expect(auth.hasSavedAccount, isFalse);
    expect(await auth.signInWithGoogle(), isNotNull);
    expect(google.interactiveCalls, 1);
    expect(auth.hasSavedAccount, isTrue);
    expect(auth.hasGoogleSession, isTrue);
  });

  test('reconnecting with another account cannot replace the offline shelf',
      () async {
    SharedPreferences.setMockInitialValues({
      '$appId.activeAccount':
          jsonEncode({'id': 'user-one', 'email': 'reader@example.org'}),
    });
    final google = OfflineGoogleSignIn(
      interactiveAccount: TestGoogleAccount('user-two', 'other@example.org'),
    );
    final auth = await CartaAuth.create(
      google: google,
      tokenWithoutPrompt: (_) async => null,
      restoreOnline: false,
    );

    expect(await auth.signInWithGoogle(), isNull);
    expect(auth.uid, 'user-one');
    expect(auth.hasSavedAccount, isTrue);
    expect(auth.hasGoogleSession, isFalse);
    expect(auth.lastError, contains('Choose the account'));
  });

  test('a canceled Google sign-in does not save an account', () async {
    SharedPreferences.setMockInitialValues({});
    final google = OfflineGoogleSignIn();
    final auth = await CartaAuth.create(
      google: google,
      tokenWithoutPrompt: (_) async => 'test-token',
    );

    expect(await auth.signInWithGoogle(), isNull);
    expect(auth.hasSavedAccount, isFalse);
  });

  test('cached shelf is UTF-8, account-specific and contains no credentials',
      () async {
    final directory = await Directory.systemTemp.createTemp('carta-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = LocalShelfCache(directory);
    final book = CartaBook(
      bookId: 'book-one',
      title: 'Книга с буквами ёж',
      authors: 'Тестовый автор',
      source: CartaSource.cloud,
      info: {'username': 'reader', 'password': 'book-secret'},
      sections: [
        CartaSection(
          index: 0,
          title: 'Тестовая глава',
          uri: 'https://example.org/1.mp3',
          info: {'password': 'section-secret'},
        ),
      ],
    );
    final server = CartaServer(
      serverId: 'server-one',
      type: ServerType.webdav,
      title: 'Тестовый WebDAV',
      url: 'https://example.org/dav',
      settings: {'username': 'reader', 'password': 'server-secret'},
    );
    final library = CartaLibrary(
      id: 'library-one',
      title: 'Тестовая библиотека',
      owner: 'user-one',
      members: [],
      books: [book],
      isPublic: true,
      credential: 'library-secret',
      info: {},
    );

    await cache.save('user-one', CachedShelf([book], [server], [library]));
    expect(await cache.load('user-two'), isNull);
    final restored = (await cache.load('user-one'))!;
    expect(restored.books.single.title, 'Книга с буквами ёж');
    expect(restored.books.single.sections!.single.title, 'Тестовая глава');
    expect(restored.servers.single.title, 'Тестовый WebDAV');
    expect(restored.libraries.single.title, 'Тестовая библиотека');
    expect(restored.libraries.single.signedUp, isTrue);

    final file = await directory.list().single as File;
    final text = await file.readAsString();
    expect(text, isNot(contains('book-secret')));
    expect(text, isNot(contains('section-secret')));
    expect(text, isNot(contains('server-secret')));
    expect(text, isNot(contains('library-secret')));
    expect(text, isNot(contains('reader')));
  });
}
