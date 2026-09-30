import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/moderation_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';

/// Usuários bloqueados, com a opção de desbloquear.
///
/// Alcançada pelo menu da conta na tela Início. Existe porque bloquear sem
/// ter como desfazer transforma um toque acidental em algo permanente — e a
/// pessoa nem saberia onde procurar os pedidos que pararam de aparecer.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final blocked = ref.watch(blockedUsersProvider);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.blocked_users_title),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        bottom: false,
        child: blocked.when(
          loading: () => const LoadingState(),
          error: (_, _) => EmptyState(
            title: l.error_generic,
            icon: CupertinoIcons.exclamationmark_triangle,
          ),
          data: (users) {
            if (users.isEmpty) {
              return EmptyState(
                title: l.blocked_users_empty,
                icon: CupertinoIcons.person_crop_circle_badge_xmark,
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
                  footer: Text(
                    l.blocked_users_footer,
                    style: AppTypography.footnote
                        .copyWith(color: colors.secondaryLabel),
                  ),
                  children: [
                    for (final u in users)
                      CupertinoListTile(
                        title: Text(
                          u.name ?? l.blocked_users_unknown,
                          style:
                              AppTypography.body.copyWith(color: colors.label),
                        ),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => _unblock(context, ref, u.id),
                          child: Text(
                            l.blocked_users_unblock,
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

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    String blockedId,
  ) async {
    final l = AppLocalizations.of(context);
    // A linha some da lista quando a escrita grava; capturar antes do await
    // pelo mesmo motivo do cartão do mural.
    final overlay = Overlay.of(context);
    final colors = context.colors;
    try {
      await ref.read(moderationRepositoryProvider).unblockUser(blockedId);
      showAppToastIn(overlay, colors, l.blocked_users_unblock_done);
    } catch (_) {
      showAppToastIn(overlay, colors, l.error_generic, isError: true);
    }
  }
}
