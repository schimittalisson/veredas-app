import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veredas/core/error/app_exception.dart';
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
          onPressed: () => _showInviteDialog(context, ref),
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

}

/// Diálogo de criação e de edição — é o mesmo formulário.
///
/// Com [invite] nulo cria um convite novo; com [invite] preenchido edita
/// aquele, **inclusive o código**: é assim que a base troca o código que
/// circulou demais sem criar outro convite (o índice único em `upper(code)`
/// não deixa dois convites com o mesmo código, nem se o antigo for revogado).
///
/// É função de topo, e não método da tela, porque a edição é disparada de
/// dentro de `_InviteTile`.
Future<void> _showInviteDialog(
  BuildContext context,
  WidgetRef ref, {
  InviteRow? invite,
}) async {
  final l = AppLocalizations.of(context);
  final isEdit = invite != null;

  final codeController = TextEditingController(text: invite?.code ?? _generateCode());
  final noteController = TextEditingController(text: invite?.note ?? '');
  // Vazio = sem limite. No convite novo o padrão continua sendo 1 uso: um
  // convite pessoal é o caso comum, e o convite aberto da base já existe.
  final maxUsesController = TextEditingController(
    text: isEdit ? (invite.maxUses?.toString() ?? '') : '1',
  );
  AppRole role = invite?.role ?? AppRole.obreiro;
  DateTime? expiry = invite?.expiresAt;

  await showCupertinoDialog<void>(
    context: context,
    // No iOS o toque fora não fecha um alerta — só os botões fecham.
    barrierDismissible: false,
    builder: (dialogContext) {
      final colors = dialogContext.colors;

      return StatefulBuilder(
        builder: (context, setState) => CupertinoAlertDialog(
          title: Text(
            isEdit ? l.admin_invite_edit_title : l.admin_invite_create_title,
          ),
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
                  placeholder: l.admin_invite_max_uses_hint,
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
                final code = codeController.text.trim().toUpperCase();
                final note = noteController.text.trim();
                final rawMax = maxUsesController.text.trim();

                // Campo vazio = sem limite. Um valor digitado que não seja um
                // inteiro positivo é engano de digitação, não "sem limite":
                // interpretar "abc" como ilimitado abriria o convite em
                // silêncio.
                final int? maxUses;
                if (rawMax.isEmpty) {
                  maxUses = null;
                } else {
                  final parsed = int.tryParse(rawMax);
                  if (parsed == null || parsed <= 0) {
                    showAppToast(context, l.auth_error_validation,
                        isError: true);
                    return;
                  }
                  maxUses = parsed;
                }

                // Na criação o código vazio é legítimo: o servidor gera um.
                // Na edição não há o que gerar — o convite já tem identidade.
                if (isEdit && code.isEmpty) {
                  showAppToast(context, l.admin_invite_error_code_empty,
                      isError: true);
                  return;
                }

                final adminService = ref.read(adminServiceProvider);
                try {
                  if (isEdit) {
                    await adminService.updateInvite(
                      inviteId: invite.id,
                      code: code,
                      role: role,
                      maxUses: maxUses,
                      expiresAt: expiry,
                      note: note.isEmpty ? null : note,
                    );
                  } else {
                    await adminService.createInvite(
                      role: role,
                      maxUses: maxUses,
                      expiresAt: expiry,
                      note: note.isEmpty ? null : note,
                      code: code.isEmpty ? null : code,
                    );
                  }
                  if (context.mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (context.mounted) {
                    showAppToast(context, _errorMessage(l, e), isError: true);
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
  // Um convite já vencido tem `expiresAt` no passado, e o CupertinoDatePicker
  // estoura se o valor inicial for anterior ao `minimumDate`. Na edição desse
  // convite a roda abre no padrão de 30 dias, que é a data que faz sentido
  // oferecer para renovar.
  var selected = (current != null && current.isAfter(firstDate))
      ? current
      : firstDate.add(const Duration(days: 30));

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

/// Mensagem do l10n a partir do `code` da exceção — a tela nunca mostra o
/// `toString()` de um erro de Postgrest (AGENTS.md §6, regra 6).
String _errorMessage(AppLocalizations l, Object error) {
  final code = error is AppException ? error.code : null;
  return switch (code) {
    AppErrorCode.inviteCodeTaken => l.admin_invite_error_code_taken,
    AppErrorCode.validation => l.auth_error_validation,
    AppErrorCode.permissionDenied ||
    AppErrorCode.forbidden =>
      l.auth_error_permission_denied,
    AppErrorCode.inviteNotFound ||
    AppErrorCode.notFound =>
      l.auth_error_invite_not_found,
    AppErrorCode.noConnection => l.error_no_connection,
    AppErrorCode.timeout => l.auth_error_timeout,
    AppErrorCode.serverUnavailable => l.auth_error_server_unavailable,
    _ => l.auth_error_unknown,
  };
}

// ---------------------------------------------------------------------------
// _InviteTile
// ---------------------------------------------------------------------------

class _InviteTile extends ConsumerWidget {
  const _InviteTile({required this.invite});

  final InviteRow invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    final status = _status(invite, l);
    final isRevoked = invite.revokedAt != null;
    // Sem limite (`maxUses == null`) não há como esgotar — é o estado do
    // convite aberto da base.
    final isExhausted =
        invite.maxUses != null && invite.uses >= invite.maxUses!;
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
            '${invite.maxUses == null ? l.admin_invite_uses_unlimited(invite.uses) : l.admin_invite_uses_format(invite.uses, invite.maxUses!)}',
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
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('edit'),
            child: Text(l.admin_invite_edit),
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
    } else if (value == 'edit') {
      if (!context.mounted) return;
      await _showInviteDialog(context, ref, invite: invite);
    } else if (value == 'revoke') {
      try {
        await ref.read(adminServiceProvider).revokeInvite(
              inviteId: invite.id,
            );
      } catch (e) {
        if (context.mounted) {
          showAppToast(context, _errorMessage(l, e), isError: true);
        }
      }
    }
  }

  String _status(InviteRow invite, AppLocalizations l) {
    if (invite.revokedAt != null) return l.admin_invite_status_revoked;
    if (invite.maxUses != null && invite.uses >= invite.maxUses!) {
      return l.admin_invite_status_exhausted;
    }
    if (invite.expiresAt != null &&
        invite.expiresAt!.isBefore(DateTime.now())) {
      return l.admin_invite_status_expired;
    }
    return l.admin_invite_status_active;
  }
}

// ---------------------------------------------------------------------------
// _Badge
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Random
// ---------------------------------------------------------------------------

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
