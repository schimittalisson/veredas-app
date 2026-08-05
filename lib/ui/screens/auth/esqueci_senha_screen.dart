import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';

/// Tela de recuperação de senha.
///
/// Envia um link de recuperação para o e-mail. O link contém um deep link
/// de volta para o app (`br.com.veredas.app://login-callback/`), configurado
/// no `AndroidManifest.xml` (intent-filter) e no `Info.plist` (CFBundleURLTypes).
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
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.envelope_badge,
                        size: 64,
                        color: colors.tint,
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          l.auth_reset_email_sent,
                          style:
                              AppTypography.body.copyWith(color: colors.label),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: CupertinoButton.filled(
                            onPressed: () => context.go(Routes.login),
                            child: Text(l.auth_login_button),
                          ),
                        ),
                      ),
                    ],
                  )
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
