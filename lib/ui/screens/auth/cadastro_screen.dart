import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';

/// Tela de cadastro com convite.
///
/// Fluxo (PLANO.md Fase 3):
/// 1. `signUp` → se retornar sessão, chama `redeem_invite` na hora → redirect.
/// 2. Se exigir confirmação de e-mail, guarda o código em secure storage,
///    mostra "Confirme seu e-mail para continuar".
class CadastroScreen extends ConsumerStatefulWidget {
  const CadastroScreen({super.key});

  @override
  ConsumerState<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends ConsumerState<CadastroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _inviteController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  AppErrorCode? _error;
  bool _emailConfirmationRequired = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _emailConfirmationRequired = false;
    });

    try {
      await ref.read(authActionsProvider.notifier).signUpWithInvite(
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            inviteCode: _inviteController.text.trim().toUpperCase(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
          );

      // Se chegou aqui sem exceção, ou tem sessão (redirect cuida) ou
      // precisa de confirmação de e-mail. Verifica se há sessão.
      final hasSession =
          ref.read(authStateProvider).value?.isAuthenticated ?? false;
      if (!hasSession) {
        if (mounted) {
          setState(() => _emailConfirmationRequired = true);
        }
      }
      // Se tem sessão, o redirect do router manda para /inicio.
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = AppErrorCode.unknown);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _errorMessage(AppErrorCode code) {
    final l = AppLocalizations.of(context);
    return switch (code) {
      AppErrorCode.inviteNotFound => l.auth_error_invite_not_found,
      AppErrorCode.inviteExpired => l.auth_error_invite_expired,
      AppErrorCode.inviteExhausted => l.auth_error_invite_exhausted,
      AppErrorCode.inviteRevoked => l.auth_error_invite_revoked,
      AppErrorCode.emailAlreadyRegistered => l.auth_error_email_already_registered,
      AppErrorCode.weakPassword => l.auth_error_weak_password,
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
      appBar: AppBar(title: Text(l.auth_signup_title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _emailConfirmationRequired
              ? _EmailConfirmationView(email: _emailController.text.trim())
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.auth_signup_subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Nome
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l.auth_full_name_label,
                          prefixIcon: const Icon(Icons.person_outlined),
                          border: const OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? l.auth_error_validation : null,
                      ),
                      const SizedBox(height: 16),

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
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return l.auth_error_validation;
                          if (!v.contains('@')) return l.auth_error_validation;
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Telefone (opcional)
                      TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: l.auth_phone_label,
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
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
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.isEmpty) return l.auth_error_validation;
                          if (v.length < 8) return l.auth_error_weak_password;
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Confirmar senha
                      TextFormField(
                        controller: _confirmController,
                        decoration: InputDecoration(
                          labelText: l.auth_confirm_password_label,
                          prefixIcon: const Icon(Icons.lock_outlined),
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.isEmpty) return l.auth_error_validation;
                          if (v != _passwordController.text) {
                            return l.auth_error_validation;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Código de convite
                      TextFormField(
                        controller: _inviteController,
                        decoration: InputDecoration(
                          labelText: l.auth_invite_code_label,
                          prefixIcon: const Icon(Icons.mail_outlined),
                          border: const OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _signUp(),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? l.auth_error_validation : null,
                      ),
                      const SizedBox(height: 16),

                      // Erro
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _errorMessage(_error!),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      // Criar conta
                      FilledButton(
                        onPressed: _isLoading ? null : _signUp,
                        child: Text(
                          _isLoading ? l.auth_signing_up : l.auth_signup_button,
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextButton(
                        onPressed: () => context.go(Routes.login),
                        child: Text(l.auth_already_have_account),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _EmailConfirmationView extends StatelessWidget {
  const _EmailConfirmationView({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      children: [
        const SizedBox(height: 48),
        Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          l.auth_email_confirmation_required,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => GoRouter.of(context).go(Routes.login),
          child: Text(l.auth_login_button),
        ),
      ],
    );
  }
}
