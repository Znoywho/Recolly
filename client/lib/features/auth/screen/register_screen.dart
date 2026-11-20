import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/widgets.dart';
import '../widgets/auth_sheet_layout.dart';
import '../widgets/auth_text_link.dart';
import '../widgets/google_logo.dart';
import '../widgets/inset_text_field.dart';

typedef RegistrationForm = ({
  String firstName,
  String lastName,
  String email,
  String password,
});

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.onRegister,
    this.onGoogleSignUp,
    this.onOpenTerms,
    this.onGoToLogin,
  });

  static const int minimumPasswordLength = 8;

  final ValueChanged<RegistrationForm>? onRegister;
  final VoidCallback? onGoogleSignUp;
  final VoidCallback? onOpenTerms;
  final VoidCallback? onGoToLogin;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() => widget.onRegister?.call((
    firstName: _firstNameController.text.trim(),
    lastName: _lastNameController.text.trim(),
    email: _emailController.text.trim(),
    password: _passwordController.text,
  ));

  @override
  Widget build(BuildContext context) {
    return AuthSheetLayout(
      backgroundColor: AppColors.deepSlate,
      foregroundColor: AppColors.cream,
      headline: 'Bắt đầu\nvới recolly thôi nào !!!',
      sheetChildren: [
        BrutalButton(
          label: 'Đăng ký với Google',
          color: AppColors.white,
          leading: const GoogleLogo(),
          onPressed: widget.onGoogleSignUp ?? () {},
        ),
        const SizedBox(height: AppSpacing.md),
        const AuthDivider(),
        const SizedBox(height: AppSpacing.md),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InsetTextField(
                      label: 'Tên',
                      hint: 'Tên của bạn',
                      controller: _firstNameController,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.givenName],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: InsetTextField(
                      label: 'Họ',
                      hint: 'Họ của bạn',
                      controller: _lastNameController,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.familyName],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
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
                hint: 'Tạo mật khẩu',
                controller: _passwordController,
                isPassword: true,
                helperText:
                    'Sử dụng ít nhất ${RegisterScreen.minimumPasswordLength} ký tự.',
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        BrutalButton(
          label: 'Tạo tài khoản',
          color: AppColors.green,
          onPressed: _submit,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Bằng việc đăng ký, bạn đồng ý với',
          textAlign: TextAlign.center,
          style: AppTypography.caption,
        ),
        Center(
          child: AuthTextLink(
            label: 'Điều khoản & Chính sách bảo mật.',
            onTap: widget.onOpenTerms ?? () {},
          ),
        ),
        const Spacer(),
        const SizedBox(height: AppSpacing.md),
        AuthSwitchPrompt(
          question: 'Đã có tài khoản?',
          actionLabel: 'Đăng nhập',
          onTap: widget.onGoToLogin ?? () {},
        ),
      ],
    );
  }
}
