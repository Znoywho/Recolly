import 'package:client/core/di/repository_scope.dart';
import 'package:client/features/today/today_page.dart';
import 'package:client/features/welcome_screens/startscreen.dart';
import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'login_screen.dart';

// Not logged in -> login. New user -> onboarding. Else -> Today.
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
      controller!.addListener(_refresh);
      controller!.start();
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    controller?.removeListener(_refresh);
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
      return LoginScreen(controller: c);
    }
    final needOnboarding = c.isNewUser || !(c.user?.onboardingCompleted ?? false);
    return needOnboarding ? const Startscreen() : const TodayPage();
  }
}
