import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';

/// Tela de Convites — lista + diálogo de criação.
///
/// Código gerado automaticamente (6 caracteres alfanuméricos maiúsculos,
/// sem 0/O/1/I para evitar confusão ao ditar por telefone) e editável.
class ConvitesScreen extends ConsumerWidget {
  const ConvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final invites = ref.watch(allInvitesProvider);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.admin_invites),
        backgroundColor: colors.elevatedSurface,
        // O iOS não tem FAB: a ação de criar mora no canto da navigation bar.
        // (O antigo `heroTag` existia só para desempatar FABs empilhados —
        // sem FAB, não faz mais sentido.)
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showCreateDialog(context, ref),
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: invites.when(
          loading: () => const LoadingState(),
          error: (_, _) => EmptyState(
            title: l.admin_no_invites,
            icon: CupertinoIcons.mail,
          ),
          data: (data) {
            if (data.isEmpty) {
              return EmptyState(
                title: l.admin_no_invites,
                icon: CupertinoIcons.mail,
              );
            }
            return ListView(
              children: [
                CupertinoListSection.insetGrouped(
                  backgroundColor: colors.groupedBackground,
                  separatorColor: colors.separator,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  children: data
                      .map((invite) => _InviteTile(invite: invite))
                      .toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final codeController = TextEditingController(text: _generateCode());
    final noteController = TextEditingController();
    final maxUsesController = TextEditingController(text: '1');
    AppRole role = AppRole.obreiro;
    DateTime? expiry;

    await showCupertinoDialog<void>(
      context: context,
      // No iOS o toque fora não fecha um alerta — só os botões fecham.
      barrierDismissible: false,
      builder: (dialogContext) {
        final colors = dialogContext.colors;

        return StatefulBuilder(
          builder: (context, setState) => CupertinoAlertDialog(
            title: Text(l.admin_invite_create_title),
            // O `content` do CupertinoAlertDialog já rola sozinho, então o
            // SingleChildScrollView do Material saiu.
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoTextField(
                    controller: codeController,
                    placeholder: l.admin_invite_code,
                    textCapitalization: TextCapitalization.characters,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  const SizedBox(height: 12),
                  // Dois papéis apenas: o controle segmentado é mais direto
                  // que um menu suspenso e é o padrão do iOS para escolha
                  // binária.
                  CupertinoSlidingSegmentedControl<AppRole>(
                    groupValue: role,
                    children: {
                      AppRole.obreiro: Text(
                        l.admin_role_obreiro,
                        style: AppTypography.footnote
                            .copyWith(color: colors.label),
                      ),
                      AppRole.admin: Text(
                        l.admin_role_admin,
                        style: AppTypography.footnote
                            .copyWith(color: colors.label),
                      ),
                    },
                    onValueChanged: (v) =>
                        setState(() => role = v ?? AppRole.obreiro),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: maxUsesController,
                    placeholder: l.admin_invite_max_uses,
                    keyboardType: TextInputType.number,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: noteController,
                    placeholder: l.admin_invite_note,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () async {
                      final picked = await _pickDate(context, expiry);
                      if (picked != null) setState(() => expiry = picked);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            l.admin_invite_expiry_date,
                            style: AppTypography.footnote
                                .copyWith(color: colors.secondaryLabel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          expiry != null
                              ? DateFormat('dd/MM/yyyy').format(expiry!)
                              : l.admin_invite_no_expiry,
                          style: AppTypography.footnoteEmphasis
                              .copyWith(color: colors.tint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.action_cancel),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () async {
                  final adminService = ref.read(adminServiceProvider);
                  try {
                    await adminService.createInvite(
                      role: role,
                      maxUses: int.tryParse(maxUsesController.text) ?? 1,
                      expiresAt: expiry,
                      note: noteController.text.trim().isEmpty
                          ? null
                          : noteController.text.trim(),
                      code: codeController.text.trim().isEmpty
                          ? null
                          : codeController.text.trim().toUpperCase(),
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (e) {
                    if (context.mounted) {
                      showAppToast(context, e.toString(), isError: true);
                    }
                  }
                },
                child: Text(l.action_save),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Seletor de data no formato iOS: a roda sobe de baixo, sobre uma folha
  /// translúcida. Substitui o `showDatePicker` do Material, mantendo a mesma
  /// janela (hoje até um ano à frente) e o mesmo padrão de 30 dias.
  Future<DateTime?> _pickDate(BuildContext context, DateTime? current) async {
    final colors = context.colors;
    final firstDate = DateTime.now();
    var selected = current ?? firstDate.add(const Duration(days: 30));

    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (popupContext) => Container(
        height: 280,
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 200,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: selected,
                  minimumDate: firstDate,
                  maximumDate: firstDate.add(const Duration(days: 365)),
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
              CupertinoButton(
                onPressed: () =>
                    Navigator.of(popupContext).pop<DateTime>(selected),
                child: Text(AppLocalizations.of(popupContext).action_save),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Gera um código de 6 caracteres alfanuméricos maiúsculos, sem 0/O/1/I
  /// para evitar confusão ao ditar por telefone.
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    final rng = Random(now);
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

class _InviteTile extends ConsumerWidget {
  const _InviteTile({required this.invite});

  final InviteRow invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    final status = _status(invite, l);
    final isRevoked = invite.revokedAt != null;
    final isExhausted = invite.uses >= invite.maxUses;
    final isExpired =
        invite.expiresAt != null && invite.expiresAt!.isBefore(DateTime.now());

    final isInactive = isRevoked || isExhausted || isExpired;

    return CupertinoListTile(
      leading: Icon(
        isRevoked
            ? CupertinoIcons.nosign
            : isExhausted
                ? CupertinoIcons.checkmark_circle
                : isExpired
                    ? CupertinoIcons.clock
                    : CupertinoIcons.mail,
        color: colors.secondaryLabel,
      ),
      title: Text(
        invite.code,
        style: AppTypography.headline.copyWith(
          color: colors.label,
          fontFamily: 'monospace',
          letterSpacing: 2,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${invite.role == AppRole.admin ? l.admin_role_admin : l.admin_role_obreiro} · '
            '${l.admin_invite_uses_format(invite.uses, invite.maxUses)}',
            style: AppTypography.footnote
                .copyWith(color: colors.secondaryLabel),
          ),
          if (invite.expiresAt != null)
            Text(
              '${l.admin_invite_expires}: ${DateFormat('dd/MM/yyyy').format(invite.expiresAt!)}',
              style: AppTypography.footnote
                  .copyWith(color: colors.secondaryLabel),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Badge(
            label: status,
            background: isInactive ? colors.fill : colors.tint,
            foreground: isInactive ? colors.secondaryLabel : colors.onTint,
          ),
          // Folha de ações no lugar do `PopupMenuButton`: mesmas opções, mesmas
          // condições de exibição.
          CupertinoButton(
            padding: const EdgeInsets.only(left: 8),
            minimumSize: Size.zero,
            onPressed: () => _showActions(context, ref, isRevoked),
            child: Icon(
              CupertinoIcons.ellipsis,
              size: 20,
              color: colors.secondaryLabel,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    bool isRevoked,
  ) async {
    final l = AppLocalizations.of(context);

    final value = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(invite.code),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('copy'),
            child: Text(l.admin_invite_copy),
          ),
          if (!isRevoked)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('revoke'),
              isDestructiveAction: true,
              child: Text(l.admin_invite_revoke),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(l.action_cancel),
        ),
      ),
    );

    if (value == 'copy') {
      await Clipboard.setData(ClipboardData(text: invite.code));
      if (!context.mounted) return;
      showAppToast(context, l.admin_invite_copied);
    } else if (value == 'revoke') {
      try {
        await ref.read(adminServiceProvider).revokeInvite(
              inviteId: invite.id,
            );
      } catch (e) {
        if (context.mounted) {
          showAppToast(context, e.toString(), isError: true);
        }
      }
    }
  }

  String _status(InviteRow invite, AppLocalizations l) {
    if (invite.revokedAt != null) return l.admin_invite_status_revoked;
    if (invite.uses >= invite.maxUses) return l.admin_invite_status_exhausted;
    if (invite.expiresAt != null &&
        invite.expiresAt!.isBefore(DateTime.now())) {
      return l.admin_invite_status_expired;
    }
    return l.admin_invite_status_active;
  }
}

/// Etiqueta arredondada de estado — substitui o `Chip` do Material.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(color: foreground),
        ),
      ),
    );
  }
}

/// Random simples para gerar o código — não precisa de crypto.
class Random {
  int _state;
  Random(this._state);

  int nextInt(int max) {
    // LCG simples, suficiente para gerar um código de 6 chars.
    _state = (1103515245 * _state + 12345) & 0x7FFFFFFF;
    return _state % max;
  }
}
