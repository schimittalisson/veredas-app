import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';

/// Tela inescapável para usuários não aprovados.
///
/// O `redirect` do router garante que `is_approved == false` só pode estar
/// aqui — mesmo com deep link para `/escalas`, o redirect manda de volta.
/// Os botões oferecem sair ou resgatar um convite (que aprova de imediato).
class AguardandoScreen extends ConsumerStatefulWidget {
  const AguardandoScreen({super.key});

  @override
  ConsumerState<AguardandoScreen> createState() => _AguardandoScreenState();
}

class _AguardandoScreenState extends ConsumerState<AguardandoScreen> {
  bool _isRedeeming = false;
  bool _isChecking = false;

  Future<void> _checkAgain() async {
    setState(() => _isChecking = true);
    try {
      // Força um pull do perfil do servidor.
      await ref.read(syncServiceProvider).pullAll();
      // O currentProfileProvider emite o perfil atualizado, e o redirect
      // cuida da navegação — se aprovado, manda para /inicio.
    } catch (_) {
      // Silencioso: o erro já está no sync_state. O usuário pode tentar de novo.
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _showRedeemDialog() async {
    final code = await showCupertinoDialog<String>(
      context: context,
      // No iOS o toque fora não fecha um alerta; e aqui há texto digitado,
      // que seria perdido sem aviso.
      barrierDismissible: false,
      builder: (context) => const _RedeemInviteDialog(),
    );
    if (code == null || code.trim().isEmpty) return;
    await _redeemInvite(code.trim().toUpperCase());
  }

  Future<void> _redeemInvite(String code) async {
    setState(() => _isRedeeming = true);
    try {
      final role = await ref.read(authActionsProvider.notifier).redeemInvite(code);
      if (mounted && role != null) {
        showAppToast(
          context,
          AppLocalizations.of(context).auth_pending_redeem_success,
        );
        // Força um sync para atualizar o cache local com o perfil aprovado.
        await ref.read(syncServiceProvider).pullAll();
        // O redirect cuida da navegação.
      }
    } on AppException catch (e) {
      if (mounted) {
        showAppToast(context, _errorMessage(e.code), isError: true);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context).auth_error_unknown,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }

  Future<void> _signOut() async {
    final l = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l.auth_pending_sign_out,
      message: l.auth_sign_out_confirm,
      isDestructive: false,
    );
    if (!confirmed) return;

    await ref.read(authActionsProvider.notifier).signOut();
    // O redirect cuida da navegação para /login.
  }

  String _errorMessage(AppErrorCode code) {
    final l = AppLocalizations.of(context);
    return switch (code) {
      AppErrorCode.inviteNotFound => l.auth_error_invite_not_found,
      AppErrorCode.inviteExpired => l.auth_error_invite_expired,
      AppErrorCode.inviteExhausted => l.auth_error_invite_exhausted,
      AppErrorCode.inviteRevoked => l.auth_error_invite_revoked,
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
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.hourglass,
                  size: 64,
                  color: colors.tint,
                ),
                const SizedBox(height: 24),
                Text(
                  l.auth_pending_title,
                  style: AppTypography.title.copyWith(color: colors.label),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l.auth_pending_message,
                  style: AppTypography.subheadline
                      .copyWith(color: colors.secondaryLabel),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Verificar novamente — ação primária.
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _isChecking ? null : _checkAgain,
                    child: _ButtonContent(
                      isBusy: _isChecking,
                      icon: CupertinoIcons.refresh,
                      label: l.auth_pending_check_again,
                      color: colors.onTint,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Tenho um convite — ação secundária. O Cupertino não tem
                // equivalente ao OutlinedButton: no iOS a hierarquia entre
                // duas ações se faz com botão preenchido vs. texto puro, e não
                // com dois botões de contorno diferente.
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    onPressed: _isRedeeming ? null : _showRedeemDialog,
                    child: _ButtonContent(
                      isBusy: _isRedeeming,
                      icon: CupertinoIcons.mail,
                      label: l.auth_pending_have_invite,
                      color: colors.tint,
                    ),
                  ),
                ),

                // Sair — ação terciária, em texto de apoio para não competir
                // com as duas acima.
                CupertinoButton(
                  onPressed: _signOut,
                  child: Text(
                    l.auth_pending_sign_out,
                    style: AppTypography.subheadline
                        .copyWith(color: colors.secondaryLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ButtonContent
// ---------------------------------------------------------------------------

/// Conteúdo de um botão com ícone que vira spinner enquanto carrega.
///
/// O `CupertinoButton` não tem construtor `.icon` como o Material, então o
/// ícone e o rótulo entram como um `Row` — extraído aqui para os dois botões
/// não duplicarem a troca ícone↔indicador.
class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.isBusy,
    required this.icon,
    required this.label,
    required this.color,
  });

  final bool isBusy;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isBusy)
          // radius 9 dá ~18px, o mesmo tamanho do ícone que ele substitui,
          // então o rótulo não pula de posição ao começar a carregar.
          CupertinoActivityIndicator(radius: 9, color: color)
        else
          Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: AppTypography.body.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _RedeemInviteDialog
// ---------------------------------------------------------------------------

class _RedeemInviteDialog extends StatefulWidget {
  const _RedeemInviteDialog();

  @override
  State<_RedeemInviteDialog> createState() => _RedeemInviteDialogState();
}

class _RedeemInviteDialogState extends State<_RedeemInviteDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return CupertinoAlertDialog(
      title: Text(l.auth_pending_redeem_title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Form(
          key: _formKey,
          child: CupertinoTextFormFieldRow(
            controller: _controller,
            placeholder: l.auth_invite_code_label,
            // Dentro do alerta não há célula de lista para dar contorno ao
            // campo, então a caixa vem do `fill` do tema — é o que o iOS usa
            // em campos de texto sobre superfície clara.
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            autofocus: true,
            style: AppTypography.body.copyWith(color: colors.label),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l.auth_error_validation : null,
          ),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.action_cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_controller.text);
            }
          },
          child: Text(l.action_confirm),
        ),
      ],
    );
  }
}
