import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/app_toast.dart';

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
      final completed =
          await ref.read(authActionsProvider.notifier).signUpWithInvite(
                fullName: _nameController.text.trim(),
                email: _emailController.text.trim(),
                password: _passwordController.text,
                inviteCode: _inviteController.text.trim().toUpperCase(),
                phone: _phoneController.text.trim().isEmpty
                    ? null
                    : _phoneController.text.trim(),
              );

      // O retorno do serviço é a fonte da verdade, e não o `authStateProvider`:
      // o stream de sessão é assíncrono e ainda não emitiu neste ponto, então
      // lê-lo aqui mostrava "confirme seu e-mail" por um instante para um
      // cadastro que já tinha dado certo.
      if (!completed && mounted) {
        setState(() => _emailConfirmationRequired = true);
      }
      // Com o cadastro concluído, o redirect do router manda para /inicio.
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

/// Confirmação do e-mail por código de 6 dígitos.
///
/// Substitui o link de confirmação do Supabase. O link dependia do deep link
/// `br.com.veredas.app://`, que só resolve no aparelho onde a pessoa se
/// cadastrou — abrir o e-mail no computador levava a uma página morta. O código
/// não tem esse vínculo: lê-se o e-mail em qualquer lugar e digita-se aqui.
///
/// O `verifyEmailOtp` devolve a sessão **e** resgata o convite guardado no
/// cadastro, então em caso de sucesso não há nada a fazer aqui: o redirect do
/// router leva para `/inicio`.
class _EmailConfirmationView extends ConsumerStatefulWidget {
  const _EmailConfirmationView({required this.email});

  final String email;

  @override
  ConsumerState<_EmailConfirmationView> createState() =>
      _EmailConfirmationViewState();
}

class _EmailConfirmationViewState
    extends ConsumerState<_EmailConfirmationView> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;
  AppErrorCode? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _error = AppErrorCode.otpInvalid);
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      await ref.read(authActionsProvider.notifier).verifyEmailOtp(
            email: widget.email,
            token: code,
          );
      // Sucesso: a sessão existe e o convite já foi resgatado. O redirect do
      // router assume daqui.
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = AppErrorCode.unknown);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });

    try {
      await ref
          .read(authActionsProvider.notifier)
          .resendEmailConfirmation(widget.email);
      if (mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context).auth_confirm_email_resent,
        );
        // O código antigo deixa de valer assim que o novo é emitido; limpar
        // evita a pessoa confirmar com o que já está digitado e receber
        // "código incorreto" sem entender por quê.
        _codeController.clear();
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = AppErrorCode.unknown);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  String _errorMessage(AppErrorCode code) {
    final l = AppLocalizations.of(context);
    return switch (code) {
      AppErrorCode.otpInvalid => l.auth_error_otp_invalid,
      AppErrorCode.otpExpired => l.auth_error_otp_expired,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Icon(CupertinoIcons.envelope_badge, size: 64, color: colors.tint),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l.auth_confirm_email_title,
            style: AppTypography.title.copyWith(color: colors.label),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l.auth_confirm_email_sent_to(widget.email),
            style: AppTypography.subheadline
                .copyWith(color: colors.secondaryLabel),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),

        CupertinoFormSection.insetGrouped(
          backgroundColor: colors.groupedBackground,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          children: [
            CupertinoTextFormFieldRow(
              controller: _codeController,
              prefix: Icon(
                CupertinoIcons.number,
                size: 20,
                color: colors.secondaryLabel,
              ),
              placeholder: l.auth_confirm_email_code_label,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              // Formatter em vez de `maxLength`: o contador "0/6" do Flutter
              // não combina com a linha de formulário do iOS, e filtrar para
              // dígitos evita o código colado do e-mail vir com espaço.
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onFieldSubmitted: (_) => _verify(),
              style: AppTypography.body.copyWith(color: colors.label),
            ),
          ],
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              _errorMessage(_error!),
              style: AppTypography.footnote.copyWith(color: colors.destructive),
              textAlign: TextAlign.center,
            ),
          ),

        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: _isVerifying ? null : _verify,
              child: Text(
                _isVerifying
                    ? l.auth_confirming_email
                    : l.auth_confirm_email_button,
              ),
            ),
          ),
        ),

        CupertinoButton(
          onPressed: _isResending ? null : _resend,
          child: Text(
            _isResending ? l.auth_sending : l.auth_confirm_email_resend,
          ),
        ),
      ],
    );
  }
}
