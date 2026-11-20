import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../widgets/auth_sheet_layout.dart';
import '../widgets/auth_text_link.dart';
import '../widgets/google_logo.dart';
import '../widgets/inset_text_field.dart';

typedef LoginCredentials = ({String email, String password});

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onLogin,
    this.onGoogleSignIn,
    this.onForgotPassword,
    this.onGoToRegister,
  });

  final ValueChanged<LoginCredentials>? onLogin;
  final VoidCallback? onGoogleSignIn;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onGoToRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() => widget.onLogin?.call((
    email: _emailController.text.trim(),
    password: _passwordController.text,
  ));

  @override
  Widget build(BuildContext context) {
    return AuthSheetLayout(
      backgroundColor: AppColors.yellow,
      foregroundColor: AppColors.ink,
      headline: 'Recolly vẫn đang đợi bạn nè!!!',
      sheetChildren: [
        BrutalButton(
          label: 'Đăng nhập với Google',
          color: AppColors.white,
          leading: const GoogleLogo(),
          onPressed: widget.onGoogleSignIn ?? () {},
        ),
        const SizedBox(height: AppSpacing.md),
        const AuthDivider(),
        const SizedBox(height: AppSpacing.md),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InsetTextField(
                label: 'Email',
                hint: 'ban@example.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: AppSpacing.md),
              InsetTextField(
                label: 'Mật khẩu',
                hint: 'Nhập mật khẩu',
                controller: _passwordController,
                isPassword: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: AuthTextLink(
            label: 'Quên mật khẩu?',
            onTap: widget.onForgotPassword ?? () {},
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BrutalButton(
          label: 'Đăng nhập',
          color: AppColors.teal,
          onPressed: _submit,
        ),
        const Spacer(),
        const SizedBox(height: AppSpacing.lg),
        AuthSwitchPrompt(
          question: 'Chưa có tài khoản?',
          actionLabel: 'Đăng ký',
          onTap: widget.onGoToRegister ?? () {},
        ),
      ],
    );
  }
}
