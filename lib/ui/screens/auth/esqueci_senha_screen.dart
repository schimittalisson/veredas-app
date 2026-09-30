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

/// Tela de recuperação de senha, em dois passos: o e-mail, e depois o código
/// de 6 dígitos que chega nele.
///
/// **Por que código, e não só o link.** O link do e-mail volta para o app
/// (`br.com.veredas.app://login-callback/`), mas o PKCE do `supabase_flutter`
/// o amarra ao aparelho que pediu e ao e-mail mais recente. Aberto no
/// computador, noutro celular ou a partir de um e-mail anterior, ele abria o
/// app e nada acontecia. O código não tem esses vínculos — é a mesma decisão
/// já tomada para a confirmação de cadastro. O link continua funcionando no
/// mesmo aparelho, se o template do e-mail ainda o trouxer.
///
/// Confirmado o código, a sessão nasce em modo recuperação e o router leva
/// para `/nova-senha` sozinho.
class EsqueciSenhaScreen extends ConsumerStatefulWidget {
  const EsqueciSenhaScreen({super.key});

  @override
  ConsumerState<EsqueciSenhaScreen> createState() => _EsqueciSenhaScreenState();
}

class _EsqueciSenhaScreenState extends ConsumerState<EsqueciSenhaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;
  AppErrorCode? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authActionsProvider.notifier).resetPassword(
            _emailController.text.trim(),
          );
      if (mounted) setState(() => _sent = true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = AppErrorCode.unknown);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.auth_forgot_password_title),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: _sent
                ? _RecoveryCodeView(email: _emailController.text.trim())
                : Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            l.auth_forgot_password_subtitle,
                            style: AppTypography.subheadline
                                .copyWith(color: colors.secondaryLabel),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Um campo só, mas ainda dentro de uma seção agrupada:
                        // é assim que o iOS apresenta qualquer formulário, e
                        // manter o mesmo cartão do login evita que a tela
                        // pareça de outro app.
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
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              onFieldSubmitted: (_) => _sendResetLink(),
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
                          ],
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _error == AppErrorCode.noConnection
                                  ? l.error_no_connection
                                  : l.auth_error_unknown,
                              style: AppTypography.footnote
                                  .copyWith(color: colors.destructive),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: CupertinoButton.filled(
                              onPressed: _isLoading ? null : _sendResetLink,
                              child: Text(
                                _isLoading
                                    ? l.auth_sending
                                    : l.auth_send_reset_link,
                              ),
                            ),
                          ),
                        ),
                        CupertinoButton(
                          onPressed: () => context.go(Routes.login),
                          child: Text(l.auth_login_button),
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

// ---------------------------------------------------------------------------
// _RecoveryCodeView
// ---------------------------------------------------------------------------

/// Segundo passo: o código de 6 dígitos do e-mail.
///
/// Mesmo desenho da confirmação de cadastro (`cadastro_screen.dart`), para a
/// pessoa reconhecer a tela.
class _RecoveryCodeView extends ConsumerStatefulWidget {
  const _RecoveryCodeView({required this.email});

  final String email;

  @override
  ConsumerState<_RecoveryCodeView> createState() => _RecoveryCodeViewState();
}

class _RecoveryCodeViewState extends ConsumerState<_RecoveryCodeView> {
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
      await ref.read(authActionsProvider.notifier).verifyRecoveryOtp(
            email: widget.email,
            token: code,
          );
      // Sucesso: o router leva para /nova-senha.
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
      await ref.read(authActionsProvider.notifier).resetPassword(widget.email);
      if (mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context).auth_reset_code_resent,
        );
        // O código anterior deixa de valer quando o novo é emitido.
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(CupertinoIcons.envelope_badge, size: 64, color: colors.tint),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l.auth_reset_code_title,
            style: AppTypography.title.copyWith(color: colors.label),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l.auth_reset_code_sent_to(widget.email),
            style:
                AppTypography.subheadline.copyWith(color: colors.secondaryLabel),
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
              // Mesmo motivo do cadastro: o código colado do e-mail às vezes
              // vem com espaço.
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
        CupertinoButton(
          onPressed: () => context.go(Routes.login),
          child: Text(l.auth_login_button),
        ),
      ],
    );
  }
}
