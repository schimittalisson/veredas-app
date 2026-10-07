import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/remote/admin_service.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';
import 'package:veredas/ui/widgets/pull_to_refresh.dart';

/// Membros removidos por um admin, com a opção de restaurar.
///
/// **Online, e não do cache.** Os removidos nunca chegam ao drift: o sync
/// descarta perfis com `deleted_at` (ver `SyncService._doPull`). A lista vem
/// da RPC `list_removed_members` na hora em que a tela abre.
///
/// Existe porque remover alguém travava a volta dessa pessoa: o login dela
/// continua no Supabase, então um cadastro novo com o mesmo e-mail não envia
/// código nenhum. Restaurar devolve a conta que já existe, com o histórico.
class MembrosRemovidosScreen extends ConsumerStatefulWidget {
  const MembrosRemovidosScreen({super.key});

  @override
  ConsumerState<MembrosRemovidosScreen> createState() =>
      _MembrosRemovidosScreenState();
}

class _MembrosRemovidosScreenState
    extends ConsumerState<MembrosRemovidosScreen> {
  late Future<List<RemovedMember>> _members;

  @override
  void initState() {
    super.initState();
    _members = _load();
  }

  Future<List<RemovedMember>> _load() =>
      ref.read(adminServiceProvider).listRemovedMembers();

  // Chaves, e não `=> _members = _load()`: a atribuição tem valor (o
  // Future), e o setState recusa um callback que devolve Future — a lista
  // simplesmente não recarregava.
  void _reload() => setState(() {
        _members = _load();
      });

  /// O arrasto daqui recarrega a lista do servidor, e não o cache: os
  /// removidos não estão no cache (o sync descarta lápides). O erro fica
  /// com o `FutureBuilder`, que mostra "tentar de novo".
  Future<void> _refresh() async {
    _reload();
    try {
      await _members;
    } catch (_) {}
  }

  Future<void> _restore(RemovedMember member) async {
    final l = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l.admin_restore_confirm_title(member.fullName),
      message: l.admin_restore_confirm_message,
      confirmLabel: l.admin_restore,
      isDestructive: false,
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(adminServiceProvider).restoreMember(userId: member.id);
    } catch (_) {
      if (mounted) showAppToast(context, l.error_generic, isError: true);
      return;
    }

    // Traz o perfil restaurado para o cache, para ele aparecer na tela de
    // Membros ao voltar. Só `profiles`: é o que muda, e o pull completo fica
    // com o SyncCoordinator. Falhar aqui não desfaz a restauração, que já
    // aconteceu no servidor — o próximo sync traz a pessoa.
    try {
      await ref.read(syncServiceProvider).pull(syncEntityByName('profiles')!);
    } catch (_) {}

    if (!mounted) return;
    showAppToast(context, l.admin_restore_done);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.admin_removed_members),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        bottom: false,
        child: FutureBuilder<List<RemovedMember>>(
          future: _members,
          builder: (context, snapshot) {
            // Ao recarregar, o FutureBuilder mantém o dado anterior: a lista
            // fica na tela sob o indicador do arrasto, em vez de piscar.
            if (snapshot.connectionState != ConnectionState.done &&
                !snapshot.hasData) {
              return const LoadingState();
            }
            if (snapshot.hasError) {
              return RefreshableBox(
                onRefresh: _refresh,
                child: EmptyState(
                  title: l.admin_removed_members_load_error,
                  icon: CupertinoIcons.wifi_slash,
                  action: CupertinoButton(
                    onPressed: _reload,
                    child: Text(l.action_retry),
                  ),
                ),
              );
            }
            final members = snapshot.data ?? const [];
            if (members.isEmpty) {
              return RefreshableBox(
                onRefresh: _refresh,
                child: EmptyState(
                  title: l.admin_removed_members_empty,
                  icon: CupertinoIcons.person_2,
                ),
              );
            }
            return RefreshableListView(
              onRefresh: _refresh,
              children: [
                CupertinoListSection.insetGrouped(
                  backgroundColor: colors.groupedBackground,
                  separatorColor: colors.separator,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  footer: Text(
                    l.admin_removed_members_footer,
                    style: AppTypography.footnote
                        .copyWith(color: colors.secondaryLabel),
                  ),
                  children: [
                    for (final m in members)
                      CupertinoListTile(
                        title: Text(
                          m.fullName,
                          style:
                              AppTypography.body.copyWith(color: colors.label),
                        ),
                        subtitle: Text(
                          '${m.email} · ${l.admin_removed_at(timeago.format(m.deletedAt, locale: 'pt_BR'))}',
                          style: AppTypography.footnote
                              .copyWith(color: colors.secondaryLabel),
                        ),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => _restore(m),
                          child: Text(
                            l.admin_restore,
                            style: AppTypography.body
                                .copyWith(color: colors.tint),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
