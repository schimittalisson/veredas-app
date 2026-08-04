import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
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
    final code = await showDialog<String>(
      context: context,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).auth_pending_redeem_success)),
        );
        // Força um sync para atualizar o cache local com o perfil aprovado.
        await ref.read(syncServiceProvider).pullAll();
        // O redirect cuida da navegação.
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(e.code))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).auth_error_unknown)),
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.hourglass_top,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l.auth_pending_title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  l.auth_pending_message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Verificar novamente
                FilledButton.icon(
                  onPressed: _isChecking ? null : _checkAgain,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(l.auth_pending_check_again),
                ),
                const SizedBox(height: 12),

                // Tenho um convite
                OutlinedButton.icon(
                  onPressed: _isRedeeming ? null : _showRedeemDialog,
                  icon: _isRedeeming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mail_outlined),
                  label: Text(l.auth_pending_have_invite),
                ),
                const SizedBox(height: 12),

                // Sair
                TextButton(
                  onPressed: _signOut,
                  child: Text(l.auth_pending_sign_out),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

    return AlertDialog(
      title: Text(l.auth_pending_redeem_title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: l.auth_invite_code_label,
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
          autofocus: true,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? l.auth_error_validation : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.action_cancel),
        ),
        FilledButton(
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
