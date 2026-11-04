import 'dart:convert';

import 'package:client/data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

enum AuthStatus { loading, loggedOut, loggedIn }

const googleScopes = [
  'openid',
  'email',
  'profile',
  'https://www.googleapis.com/auth/calendar.events',
];

class AuthController extends ChangeNotifier {
  AuthController(this.repos);

  final AppRepositories repos;
  final storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_tokens';

  AuthStatus status = AuthStatus.loading;
  User? user;
  bool isNewUser = false;
  bool busy = false;
  String? error;

  // Called once when the app opens.
  Future<void> start() async {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: ApiConfig.googleServerClientId,
      );

      final saved = await storage.read(key: _tokenKey);
      if (saved == null) {
        status = AuthStatus.loggedOut;
      } else {
        repos.tokenStore.save(AuthTokens.fromJson(jsonDecode(saved)));
        user = await repos.user.getMe();
        status = AuthStatus.loggedIn;
      }
    } catch (e) {
      // Token expired or server down -> log in again.
      await _clear();
      status = AuthStatus.loggedOut;
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    busy = true;
    error = null;
    notifyListeners();

    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: googleScopes,
      );
      final auth = await account.authorizationClient.authorizeServer(
        googleScopes,
      );
      if (auth == null) {
        throw Exception('Bạn chưa cấp quyền Google Calendar');
      }

      final session = await repos.auth.signInWithGoogle(auth.serverAuthCode);
      repos.tokenStore.save(session.tokens);
      await storage.write(
        key: _tokenKey,
        value: jsonEncode(session.tokens.toJson()),
      );
      user = session.user;
      isNewUser = session.isNewUser;
      status = AuthStatus.loggedIn;
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error = 'Đăng nhập Google thất bại, thử lại nhé';
      }
    } on ApiException catch (e) {
      error = e.isNetworkError
          ? 'Không kết nối được server'
          : 'Đăng nhập thất bại, thử lại sau';
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }

    busy = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await repos.auth.logout();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // still log out on this phone
    }
    await _clear();
    user = null;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<void> _clear() async {
    repos.tokenStore.clear();
    await storage.delete(key: _tokenKey);
  }
}
