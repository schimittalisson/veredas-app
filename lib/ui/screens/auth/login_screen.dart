import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).auth_reset_email_sent)),
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(e.code))),
        );
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo / ícone
                  Icon(
                    Icons.wb_shade,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.auth_login_subtitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),

                  // E-mail
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: l.auth_email_label,
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
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
                  const SizedBox(height: 16),

                  // Senha
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: l.auth_password_label,
                      prefixIcon: const Icon(Icons.lock_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _signIn(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l.auth_error_validation;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Erro
                  if (_error != null) ...[
                    Text(
                      _errorMessage(_error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_error == AppErrorCode.emailNotConfirmed)
                      TextButton(
                        onPressed: _resendConfirmation,
                        child: Text(l.auth_error_email_not_confirmed_resend),
                      ),
                    const SizedBox(height: 8),
                  ],

                  // Entrar
                  FilledButton(
                    onPressed: _isLoading ? null : _signIn,
                    child: Text(
                      _isLoading ? l.auth_signing_in : l.auth_login_button,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Esqueci senha
                  TextButton(
                    onPressed: () => context.push(Routes.esqueciSenha),
                    child: Text(l.auth_forgot_password),
                  ),

                  // Divisor
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('—'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Criar conta
                  TextButton(
                    onPressed: () => context.push(Routes.cadastro),
                    child: Text(l.auth_have_invite),
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
