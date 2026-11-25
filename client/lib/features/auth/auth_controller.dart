import 'dart:convert';

import 'package:client/data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_auth.dart';

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
  static const tokenKey = 'auth_tokens';

  AuthStatus status = AuthStatus.loading;
  User? user;
  bool isNewUser = false;
  bool busy = false;
  String? error;

  // Called once when the app opens: check saved login.
  Future<void> start() async {
    // Every token change (sign-in, refresh rotation, logout) goes to disk,
    // otherwise the next launch would use a refresh token already rotated.
    repos.tokenStore.onChanged = persistTokens;
    try {
      final saved = await storage.read(key: tokenKey);
      if (saved == null) {
        status = AuthStatus.loggedOut;
      } else {
        repos.tokenStore.save(AuthTokens.fromJson(jsonDecode(saved)));
        // ApiClient refreshes an expired access token by itself here.
        user = await repos.user.getMe();
        status = AuthStatus.loggedIn;
      }
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // Refresh token expired or revoked -> log in again
        await clear();
        status = AuthStatus.loggedOut;
      } else {
        // Offline or server down: keep the login, screens show retry.
        status = AuthStatus.loggedIn;
      }
    } catch (e) {
      // Broken saved data -> log in again
      await clear();
      status = AuthStatus.loggedOut;
    }
    notifyListeners();
  }

  // Writes the current tokens to secure storage (null = delete).
  Future<void> persistTokens(AuthTokens? tokens) async {
    if (tokens == null) {
      await storage.delete(key: tokenKey);
    } else {
      await storage.write(key: tokenKey, value: jsonEncode(tokens.toJson()));
    }
  }

  Future<String?> getGoogleCode() async {
    if (ApiConfig.useMock) return 'mock-server-auth-code';
    await ensureGoogleReady();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: googleScopes,
    );
    final auth = await account.authorizationClient.authorizeServer(
      googleScopes,
    );
    return auth?.serverAuthCode;
  }

  Future<void> signIn() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();

    try {
      final code = await getGoogleCode();
      if (code == null) {
        error = 'Bạn chưa cấp quyền Google Calendar';
      } else {
        final session = await repos.auth.signInWithGoogle(code);
        repos.tokenStore.save(session.tokens);
        await persistTokens(session.tokens);
        user = session.user;
        isNewUser = session.isNewUser;
        status = AuthStatus.loggedIn;
      }
    } on GoogleSignInException catch (e) {
      // User closed the Google popup -> no message
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error = 'Đăng nhập Google lỗi, thử lại nhé';
      }
    } on ApiException catch (e) {
      error = e.isNetworkError
          ? 'Không kết nối được server'
          : 'Đăng nhập thất bại, thử lại sau';
    } catch (e) {
      error = 'Đăng nhập thất bại, thử lại sau';
    }

    busy = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await repos.auth.logout();
      if (!ApiConfig.useMock) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // still log out on this phone
    }
    await clear();
    user = null;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<void> clear() async {
    repos.tokenStore.clear();
    await storage.delete(key: tokenKey);
  }
}
