import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';

/// Tela de definição de nova senha.
///
/// É o segundo passo da recuperação: o link do e-mail cria uma sessão e o
/// router traz para cá (ver `_redirect`, regra 2). Sem esta tela, a sessão
/// nascida do link levava direto para `/inicio` — quem abrisse o e-mail
/// entrava no app sem nunca definir senha nenhuma, e a senha antiga continuava
/// valendo, sem deixar rastro de que alguém entrou.
///
/// Não há botão de sair nem de voltar: enquanto o `passwordRecoveryProvider`
/// estiver ligado, o redirect devolve para cá. A saída é trocar a senha.
class NovaSenhaScreen extends ConsumerStatefulWidget {
  const NovaSenhaScreen({super.key});

  @override
  ConsumerState<NovaSenhaScreen> createState() => _NovaSenhaScreenState();
}

class _NovaSenhaScreenState extends ConsumerState<NovaSenhaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  AppErrorCode? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authActionsProvider.notifier).updatePassword(
            _passwordController.text,
          );
      // O `updatePassword` desliga o modo recuperação, e o redirect assume
      // daqui — não navegamos à mão.
      if (mounted) {
        showAppToast(context, AppLocalizations.of(context).auth_new_password_done);
      }
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
      AppErrorCode.noConnection => l.error_no_connection,
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
        middle: Text(l.auth_new_password_title),
        backgroundColor: colors.elevatedSurface,
        // Sem seta de voltar: não há para onde voltar enquanto a senha não for
        // trocada, e uma seta morta é pior que seta nenhuma.
        automaticallyImplyLeading: false,
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.lock_rotation, size: 64, color: colors.tint),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      l.auth_new_password_subtitle,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.secondaryLabel),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),

                  CupertinoFormSection.insetGrouped(
                    backgroundColor: colors.groupedBackground,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _passwordController,
                        prefix: Icon(
                          CupertinoIcons.lock,
                          size: 20,
                          color: colors.secondaryLabel,
                        ),
                        placeholder: l.auth_new_password_label,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        style:
                            AppTypography.body.copyWith(color: colors.label),
                        validator: (v) => (v == null || v.length < 8)
                            ? l.auth_error_password_too_short
                            : null,
                      ),
                      CupertinoTextFormFieldRow(
                        controller: _confirmController,
                        prefix: Icon(
                          CupertinoIcons.lock_fill,
                          size: 20,
                          color: colors.secondaryLabel,
                        ),
                        placeholder: l.auth_new_password_confirm_label,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        onFieldSubmitted: (_) => _save(),
                        style:
                            AppTypography.body.copyWith(color: colors.label),
                        validator: (v) => v != _passwordController.text
                            ? l.auth_error_password_mismatch
                            : null,
                      ),
                    ],
                  ),

                  // Mesma decisão do login e do cadastro: o "mostrar senha"
                  // sai de dentro do campo, porque a linha de formulário do
                  // iOS não tem espaço para um botão à direita sem brigar com
                  // a mensagem de validação.
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

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Text(
                        _errorMessage(_error!),
                        style: AppTypography.footnote
                            .copyWith(color: colors.destructive),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        onPressed: _isLoading ? null : _save,
                        child: Text(
                          _isLoading
                              ? l.auth_new_password_saving
                              : l.auth_new_password_save,
                        ),
                      ),
                    ),
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
