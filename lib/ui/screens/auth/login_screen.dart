import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/app_toast.dart';

/// Tela de login.
///
/// Erros mapeados para mensagens em pt-BR via `AppException.code` → l10n.
/// **Nunca** mostra `AuthException` cru (ver `AGENTS.md` §6 regra 6).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  AppErrorCode? _error;
  String? _lastEmailForResend;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authActionsProvider.notifier).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      // O redirect do router cuida da navegação — não precisa de push/go.
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code;
          if (e.code == AppErrorCode.emailNotConfirmed) {
            _lastEmailForResend = _emailController.text.trim();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppErrorCode.unknown);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _lastEmailForResend;
    if (email == null) return;

    try {
      await ref.read(authActionsProvider.notifier).resendEmailConfirmation(email);
      if (mounted) {
        showAppToast(context, AppLocalizations.of(context).auth_reset_email_sent);
      }
    } on AppException catch (e) {
      if (mounted) {
        showAppToast(context, _errorMessage(e.code), isError: true);
      }
    }
  }

  String _errorMessage(AppErrorCode code) {
    final l = AppLocalizations.of(context);
    return switch (code) {
      AppErrorCode.invalidCredentials => l.auth_error_invalid_credentials,
      AppErrorCode.emailNotConfirmed => l.auth_error_email_not_confirmed,
      AppErrorCode.emailAlreadyRegistered => l.auth_error_email_already_registered,
      AppErrorCode.weakPassword => l.auth_error_weak_password,
      AppErrorCode.sessionExpired => l.auth_error_session_expired,
      AppErrorCode.notAuthenticated => l.auth_error_not_authenticated,
      AppErrorCode.noConnection => l.error_no_connection,
      AppErrorCode.timeout => l.auth_error_timeout,
      AppErrorCode.serverUnavailable => l.auth_error_server_unavailable,
      _ => l.auth_error_unknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo.jpg',
                    width: 96,
                    height: 96,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.auth_login_subtitle,
                    style: AppTypography.headline.copyWith(color: colors.label),
                  ),
                  const SizedBox(height: 24),

                  // Campos agrupados: é como o iOS apresenta formulários
                  // curtos — um cartão arredondado com as linhas separadas
                  // por um traço fino, em vez de caixas independentes.
                  CupertinoFormSection.insetGrouped(
                    backgroundColor: colors.groupedBackground,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _emailController,
                        prefix: Icon(
                          CupertinoIcons.mail,
                          size: 20,
                          color: colors.secondaryLabel,
                        ),
                        placeholder: l.auth_email_label,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        style: AppTypography.body.copyWith(color: colors.label),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l.auth_error_validation;
                          }
                          if (!value.contains('@')) {
                            return l.auth_error_validation;
                          }
                          return null;
                        },
                      ),
                      CupertinoTextFormFieldRow(
                        controller: _passwordController,
                        prefix: Icon(
                          CupertinoIcons.lock,
                          size: 20,
                          color: colors.secondaryLabel,
                        ),
                        placeholder: l.auth_password_label,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _signIn(),
                        style: AppTypography.body.copyWith(color: colors.label),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l.auth_error_validation;
                          }
                          return null;
                        },
                      ),
                    ],
                  ),

                  // O olho de "mostrar senha" sai de dentro do campo: no iOS
                  // a linha do formulário não comporta um botão à direita sem
                  // competir com a mensagem de validação.
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        child: Text(
                          _obscurePassword
                              ? l.auth_password_show
                              : l.auth_password_hide,
                          style: AppTypography.footnote
                              .copyWith(color: colors.tint),
                        ),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _errorMessage(_error!),
                        textAlign: TextAlign.center,
                        style: AppTypography.footnote
                            .copyWith(color: colors.destructive),
                      ),
                    ),
                    if (_error == AppErrorCode.emailNotConfirmed)
                      CupertinoButton(
                        onPressed: _resendConfirmation,
                        child: Text(l.auth_error_email_not_confirmed_resend),
                      ),
                  ],

                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        onPressed: _isLoading ? null : _signIn,
                        child: _isLoading
                            ? const CupertinoActivityIndicator()
                            : Text(l.auth_login_button),
                      ),
                    ),
                  ),

                  CupertinoButton(
                    onPressed: () => context.push(Routes.esqueciSenha),
                    child: Text(l.auth_forgot_password),
                  ),
                  CupertinoButton(
                    onPressed: () => context.push(Routes.cadastro),
                    child: Text(l.auth_signup_button),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
