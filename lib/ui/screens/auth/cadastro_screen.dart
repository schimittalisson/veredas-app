import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
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
    final colors = context.colors;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.auth_signup_title),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: _emailConfirmationRequired
              ? _EmailConfirmationView(email: _emailController.text.trim())
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          l.auth_signup_subtitle,
                          style: AppTypography.subheadline
                              .copyWith(color: colors.secondaryLabel),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Duas seções em vez de sete caixas soltas: no iOS os
                      // formulários são cartões agrupados, e separar
                      // "quem é você" de "como você entra" dá a pausa visual
                      // que antes vinha do espaçamento entre os campos.
                      CupertinoFormSection.insetGrouped(
                        backgroundColor: colors.groupedBackground,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        children: [
                          // Nome
                          CupertinoTextFormFieldRow(
                            controller: _nameController,
                            prefix: Icon(
                              CupertinoIcons.person,
                              size: 20,
                              color: colors.secondaryLabel,
                            ),
                            placeholder: l.auth_full_name_label,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            style: AppTypography.body
                                .copyWith(color: colors.label),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? l.auth_error_validation
                                : null,
                          ),

                          // E-mail
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
                            style: AppTypography.body
                                .copyWith(color: colors.label),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return l.auth_error_validation;
                              }
                              if (!v.contains('@')) {
                                return l.auth_error_validation;
                              }
                              return null;
                            },
                          ),

                          // Telefone (opcional)
                          CupertinoTextFormFieldRow(
                            controller: _phoneController,
                            prefix: Icon(
                              CupertinoIcons.phone,
                              size: 20,
                              color: colors.secondaryLabel,
                            ),
                            placeholder: l.auth_phone_label,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            style: AppTypography.body
                                .copyWith(color: colors.label),
                          ),
                        ],
                      ),

                      CupertinoFormSection.insetGrouped(
                        backgroundColor: colors.groupedBackground,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        children: [
                          // Senha
                          CupertinoTextFormFieldRow(
                            controller: _passwordController,
                            prefix: Icon(
                              CupertinoIcons.lock,
                              size: 20,
                              color: colors.secondaryLabel,
                            ),
                            placeholder: l.auth_password_label,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            style: AppTypography.body
                                .copyWith(color: colors.label),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l.auth_error_validation;
                              }
                              if (v.length < 8) return l.auth_error_weak_password;
                              return null;
                            },
                          ),

                          // Confirmar senha
                          CupertinoTextFormFieldRow(
                            controller: _confirmController,
                            prefix: Icon(
                              CupertinoIcons.lock_rotation,
                              size: 20,
                              color: colors.secondaryLabel,
                            ),
                            placeholder: l.auth_confirm_password_label,
                            obscureText: true,
                            textInputAction: TextInputAction.next,
                            style: AppTypography.body
                                .copyWith(color: colors.label),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l.auth_error_validation;
                              }
                              if (v != _passwordController.text) {
                                return l.auth_error_validation;
                              }
                              return null;
                            },
                          ),

                          // Código de convite
                          CupertinoTextFormFieldRow(
                            controller: _inviteController,
                            prefix: Icon(
                              CupertinoIcons.ticket,
                              size: 20,
                              color: colors.secondaryLabel,
                            ),
                            placeholder: l.auth_invite_code_label,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            onFieldSubmitted: (_) => _signUp(),
                            style: AppTypography.body
                                .copyWith(color: colors.label),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? l.auth_error_validation
                                : null,
                          ),
                        ],
                      ),

                      // Mesma decisão do login: o "mostrar senha" sai de dentro
                      // do campo, porque a linha do formulário do iOS não tem
                      // espaço para um botão à direita sem brigar com a
                      // mensagem de validação. Só afeta o campo Senha —
                      // o de confirmação continua sempre oculto, como antes.
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

                      // Erro
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                          child: Text(
                            _errorMessage(_error!),
                            style: AppTypography.footnote
                                .copyWith(color: colors.destructive),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 8),

                      // Criar conta
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: CupertinoButton.filled(
                            onPressed: _isLoading ? null : _signUp,
                            child: Text(
                              _isLoading
                                  ? l.auth_signing_up
                                  : l.auth_signup_button,
                            ),
                          ),
                        ),
                      ),

                      CupertinoButton(
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
    final colors = context.colors;

    return Column(
      children: [
        const SizedBox(height: 48),
        Icon(
          CupertinoIcons.envelope_badge,
          size: 64,
          color: colors.tint,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l.auth_email_confirmation_required,
            style: AppTypography.body.copyWith(color: colors.label),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: () => GoRouter.of(context).go(Routes.login),
              child: Text(l.auth_login_button),
            ),
          ),
        ),
      ],
    );
  }
}
