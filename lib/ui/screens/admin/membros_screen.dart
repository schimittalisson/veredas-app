import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Tela de Membros — lista de perfis com busca e ações administrativas.
///
/// Seção "Pendentes de aprovação" fixa no topo quando houver — é a ação
/// mais urgente do admin.
class MembrosScreen extends ConsumerStatefulWidget {
  const MembrosScreen({super.key});

  @override
  ConsumerState<MembrosScreen> createState() => _MembrosScreenState();
}

class _MembrosScreenState extends ConsumerState<MembrosScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _search = value.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final profiles = ref.watch(allProfilesProvider).value ?? const [];
    final pending = ref.watch(pendingProfilesProvider);
    final approved = ref.watch(approvedProfilesProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    // Filtra por busca.
    //
    // Sem busca, a lista de baixo traz só os aprovados: os pendentes já estão
    // na seção do topo, e usar `profiles` aqui fazia cada pendente aparecer
    // duas vezes na tela.
    //
    // Buscando, a seção de pendentes some (condição `_search.isEmpty` abaixo)
    // e a busca passa a valer sobre todo mundo — senão não haveria como achar
    // um pendente pelo nome.
    final filtered = _search.isEmpty
        ? approved
        : profiles
            .where((p) => p.fullName.toLowerCase().contains(_search))
            .toList();

    // Conta admins ativos (para proteção de auto-rebaixamento).
    final activeAdmins =
        profiles.where((p) => p.role == AppRole.admin && p.isApproved).length;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.admin_members),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // A `CupertinoNavigationBar` não tem o slot `bottom` da `AppBar`,
            // então a busca passa a ser a primeira linha do corpo — que é onde
            // o iOS a coloca de qualquer forma.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: CupertinoSearchTextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                placeholder: l.admin_members_search,
                // O botão de limpar já vem embutido e dispara `onChanged('')`,
                // então o `suffixIcon` manual do Material saiu.
                style: AppTypography.body.copyWith(color: colors.label),
                backgroundColor: colors.fill,
              ),
            ),
            Expanded(
              child: profiles.isEmpty
                  ? EmptyState(
                      title: l.admin_no_members,
                      icon: CupertinoIcons.person_2,
                    )
                  : ListView(
                      children: [
                        // Seção de pendentes no topo.
                        if (pending.isNotEmpty && _search.isEmpty)
                          _MemberSection(
                            header: l.admin_pending_section,
                            profiles: pending,
                            currentUserId: currentUserId,
                            activeAdmins: activeAdmins,
                          ),
                        // Lista de todos os membros. Uma segunda seção
                        // agrupada separa visualmente os dois blocos — é o que
                        // o `Divider` fazia antes.
                        if (filtered.isNotEmpty)
                          _MemberSection(
                            profiles: filtered,
                            currentUserId: currentUserId,
                            activeAdmins: activeAdmins,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bloco de membros dentro de um cartão arredondado.
class _MemberSection extends StatelessWidget {
  const _MemberSection({
    required this.profiles,
    required this.currentUserId,
    required this.activeAdmins,
    this.header,
  });

  final String? header;
  final List<ProfileRow> profiles;
  final String? currentUserId;
  final int activeAdmins;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CupertinoListSection.insetGrouped(
      backgroundColor: colors.groupedBackground,
      separatorColor: colors.separator,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      header: header == null
          ? null
          : Text(
              header!,
              style: AppTypography.sectionHeader.copyWith(color: colors.tint),
            ),
      children: profiles
          .map((p) => _MemberTile(
                profile: p,
                isSelf: p.id == currentUserId,
                activeAdmins: activeAdmins,
              ))
          .toList(),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.profile,
    required this.isSelf,
    required this.activeAdmins,
  });

  final ProfileRow profile;
  final bool isSelf;
  final int activeAdmins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    final isAdmin = profile.role == AppRole.admin;
    // Proteção: não deixar o admin rebaixar/revogar a si mesmo se for o
    // único admin ativo. Isto trancaria a base fora da administração.
    final selfProtection = isSelf && isAdmin && activeAdmins <= 1;

    return CupertinoListTile(
      leading: _Avatar(name: profile.fullName),
      title: Row(
        children: [
          Flexible(
            child: Text(
              profile.fullName,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(color: colors.label),
            ),
          ),
          if (!profile.isApproved) ...[
            const SizedBox(width: 8),
            _Badge(
              label: l.admin_pending_badge,
              background: colors.tint,
              foreground: colors.onTint,
            ),
          ],
        ],
      ),
      subtitle: Text(
        profile.email ?? '',
        style: AppTypography.footnote.copyWith(color: colors.secondaryLabel),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Badge(
            label: isAdmin ? l.admin_role_admin : l.admin_role_obreiro,
            background: colors.fill,
            foreground: colors.secondaryLabel,
          ),
          // O iOS não tem menu suspenso ancorado no botão: o equivalente é a
          // folha de ações que sobe da base da tela.
          CupertinoButton(
            padding: const EdgeInsets.only(left: 8),
            minimumSize: Size.zero,
            onPressed: () => _showActions(context, ref, selfProtection),
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

  /// Folha de ações no lugar do antigo `PopupMenuButton`.
  ///
  /// As condições de exibição de cada item são exatamente as de antes; só a
  /// apresentação mudou.
  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    bool selfProtection,
  ) async {
    final l = AppLocalizations.of(context);
    final isAdmin = profile.role == AppRole.admin;

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(profile.fullName),
        actions: [
          if (!profile.isApproved)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('approve'),
              child: Text(l.admin_action_approve),
            ),
          if (profile.isApproved)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('revoke'),
              isDestructiveAction: true,
              child: Text(l.admin_action_revoke),
            ),
          if (!isAdmin)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('promote'),
              child: Text(l.admin_action_promote),
            ),
          if (isAdmin && !selfProtection)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('demote'),
              child: Text(l.admin_action_demote),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('remove'),
            isDestructiveAction: true,
            child: Text(l.admin_action_remove),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(l.action_cancel),
        ),
      ),
    );

    if (action == null) return;
    if (!context.mounted) return;
    _handleAction(context, ref, action);
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) {
    final l = AppLocalizations.of(context);

    final isAdmin = profile.role == AppRole.admin;
    final selfProtection = isSelf && isAdmin && activeAdmins <= 1;

    if (action == 'demote' || action == 'revoke') {
      if (selfProtection) {
        showAppToast(context, l.admin_action_self_protection, isError: true);
        return;
      }
    }

    final actionLabel = switch (action) {
      'approve' => l.admin_action_approve,
      'revoke' => l.admin_action_revoke,
      'promote' => l.admin_action_promote,
      'demote' => l.admin_action_demote,
      'remove' => l.admin_action_remove,
      _ => action,
    };

    // Confirmação antes de executar.
    _confirmAndExecute(context, ref, action, actionLabel);
  }

  Future<void> _confirmAndExecute(
    BuildContext context,
    WidgetRef ref,
    String action,
    String actionLabel,
  ) async {
    // `ConfirmDialog` já é o `CupertinoAlertDialog` padrão do app; marcar
    // remover/revogar como destrutivo pinta a confirmação de vermelho.
    final confirmed = await ConfirmDialog.show(
      context,
      title: actionLabel,
      message: '${profile.fullName}?',
      confirmLabel: actionLabel,
      isDestructive: action == 'remove' || action == 'revoke',
    );

    if (!confirmed) return;

    final adminService = ref.read(adminServiceProvider);
    try {
      switch (action) {
        case 'approve':
          await adminService.setApproval(
              userId: profile.id, approved: true);
        case 'revoke':
          await adminService.setApproval(
              userId: profile.id, approved: false);
        case 'promote':
          await adminService.setRole(
              userId: profile.id, role: AppRole.admin);
        case 'demote':
          await adminService.setRole(
              userId: profile.id, role: AppRole.obreiro);
        case 'remove':
          await adminService.softDeleteUser(userId: profile.id);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString(), isError: true);
      }
    }
  }
}

/// Círculo com as iniciais — o `CircleAvatar` é do Material.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // 28px é o `leadingSize` padrão do CupertinoListTile — sair dele
    // desalinharia os separadores da seção.
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.tintContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name),
        style: AppTypography.caption.copyWith(
          color: colors.onTintContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Etiqueta arredondada de papel/estado — substitui o `Chip` do Material.
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

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  final first = parts.first.substring(0, 1);
  if (parts.length == 1) return first.toUpperCase();
  return (first + parts.last.substring(0, 1)).toUpperCase();
}
