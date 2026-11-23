import 'package:client/core/di/repository_scope.dart';
import 'package:client/features/theme_gallery/navigation_preview_page.dart';
import 'package:client/features/welcome_screens/startscreen.dart';
import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'screen/login_screen.dart';

// Not logged in -> login. New user -> Startscreen. Else -> app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

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
      controller!.addListener(refresh);
      controller!.start();
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
