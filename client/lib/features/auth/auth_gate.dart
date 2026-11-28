import 'package:client/core/di/repository_scope.dart';
import 'package:client/features/theme_gallery/navigation_preview_page.dart';
import 'package:client/features/welcome_screens/startscreen.dart';
import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'screen/login_screen.dart';

// Not logged in -> login. New user -> Startscreen. Else -> app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.sessionExpired = false});

  /// Shows "session expired" once on the login screen.
  final bool sessionExpired;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthController? controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (controller == null) {
      controller = AuthController(RepositoryScope.of(context));
      // Root navigator outlives this gate (onboarding replaces it), so the
      // reset to login still works after the gate is gone.
      final navigator = Navigator.of(context, rootNavigator: true);
      controller!.onSessionExpired = () => navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const AuthGate(sessionExpired: true),
        ),
        (route) => false,
      );
      controller!.addListener(refresh);
      controller!.start();
      if (widget.sessionExpired) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showSnack('Phiên đăng nhập hết hạn, đăng nhập lại nhé');
        });
      }
    }
  }

  void refresh() {
    final err = controller!.error;
    if (err != null) {
      showSnack(err);
      controller!.error = null;
    }
    setState(() {});
  }

  void showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void onlyGoogle() => showSnack('Hiện chỉ hỗ trợ đăng nhập Google');

  @override
  void dispose() {
    controller?.removeListener(refresh);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller!;
    if (c.status == AuthStatus.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (c.status == AuthStatus.loggedOut) {
      return LoginScreen(
        onGoogleSignIn: c.busy ? null : c.signIn,
        onLogin: (_) => onlyGoogle(),
        onForgotPassword: onlyGoogle,
        onGoToRegister: onlyGoogle,
      );
    }
    return c.isNewUser ? const Startscreen() : const NavigationPreviewPage();
  }
}
