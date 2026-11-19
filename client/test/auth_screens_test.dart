import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/auth/screen/login_screen.dart';
import 'package:client/features/auth/screen/register_screen.dart';
import 'package:client/features/auth/widgets/inset_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpOnPhone(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: screen));
}

void main() {
  testWidgets('LoginScreen renders the Figma content and submits credentials', (
    tester,
  ) async {
    LoginCredentials? submitted;
    await _pumpOnPhone(tester, LoginScreen(onLogin: (c) => submitted = c));

    expect(find.text('Recolly vẫn đang đợi bạn nè!!!'), findsOneWidget);
    expect(find.text('Đăng nhập với Google'), findsOneWidget);
    expect(find.byType(InsetTextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).at(0), ' ban@example.com ');
    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.ensureVisible(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng nhập'));

    expect(submitted?.email, 'ban@example.com');
    expect(submitted?.password, 'secret123');
    expect(tester.takeException(), isNull);
  });

  testWidgets('password field toggles visibility', (tester) async {
    await _pumpOnPhone(tester, const LoginScreen());

    TextField passwordField() =>
        tester.widget<TextField>(find.byType(TextField).at(1));

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byTooltip('Hiện mật khẩu'));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('RegisterScreen renders all fields and submits the form', (
    tester,
  ) async {
    RegistrationForm? submitted;
    await _pumpOnPhone(
      tester,
      RegisterScreen(onRegister: (form) => submitted = form),
    );

    expect(find.text('Đăng ký với Google'), findsOneWidget);
    expect(find.byType(InsetTextField), findsNWidgets(4));
    expect(find.text('Sử dụng ít nhất 8 ký tự.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'An');
    await tester.enterText(find.byType(TextField).at(1), 'Nguyễn');
    await tester.enterText(find.byType(TextField).at(2), 'an@example.com');
    await tester.enterText(find.byType(TextField).at(3), 'password1');
    await tester.ensureVisible(find.text('Tạo tài khoản'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tạo tài khoản'));

    expect(submitted?.firstName, 'An');
    expect(submitted?.lastName, 'Nguyễn');
    expect(submitted?.email, 'an@example.com');
    expect(submitted?.password, 'password1');
    expect(tester.takeException(), isNull);
  });
}
