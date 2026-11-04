import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/home_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Detalhe de um aviso: o texto inteiro, para todos; editar e excluir, para o
/// admin.
///
/// Existe porque a célula da lista "Avisos" corta o texto em duas linhas e o
/// toque nela não fazia nada — um aviso não fixado não tinha como ser lido
/// por inteiro, nem editado (só excluído, arrastando).
///
/// **Não abre direto o editor**, nem para o admin: a maior parte das vezes o
/// admin também só quer ler o aviso, e um formulário aberto convida a mudar o
/// texto sem querer. Editar fica no `trailing` da barra, como no app Notas.
///
/// O aviso é lido do stream do cache, não passado por parâmetro: depois de
/// editar e voltar, a tela já mostra o texto novo; e se o aviso for excluído
/// (aqui ou pelo sync), a tela mostra o estado vazio em vez de um aviso morto.
class AnnouncementDetailScreen extends ConsumerWidget {
  const AnnouncementDetailScreen({required this.announcementId, super.key});

  final String announcementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final announcement = ref.watch(announcementByIdProvider(announcementId));
    final isAdmin = ref.watch(isAdminProvider);
    final loading = ref.watch(announcementsProvider).isLoading;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(l.home_announcement_detail_title),
        trailing: isAdmin && announcement != null
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => context.push(
                  '${Routes.avisoEditar}?id=${announcement.id}',
                ),
                child: Text(l.home_announcement_edit),
              )
            : null,
      ),
      child: SafeArea(
        child: announcement == null
            ? (loading
                ? const Center(child: CupertinoActivityIndicator())
                : EmptyState(
                    title: l.home_announcement_not_found,
                    icon: CupertinoIcons.bell_slash,
                  ))
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  _Body(announcement: announcement),
                  if (isAdmin) _DeleteSection(announcement: announcement),
                ],
              ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.announcement});

  final AnnouncementRow announcement;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final title = announcement.title;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      // `SelectableText` é Material; o `SelectableRegion` com os controles do
      // iOS deixa copiar um telefone, endereço ou link do aviso.
      child: SelectableRegion(
        selectionControls: cupertinoTextSelectionHandleControls,
        contextMenuBuilder: (context, state) =>
            CupertinoAdaptiveTextSelectionToolbar.buttonItems(
          buttonItems: state.contextMenuButtonItems,
          anchors: state.contextMenuAnchors,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null && title.isNotEmpty) ...[
              Text(
                title,
                style: AppTypography.title.copyWith(color: colors.label),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              [
                if (announcement.authorName?.isNotEmpty == true)
                  announcement.authorName!,
                timeago.format(announcement.createdAt, locale: 'pt_BR'),
                if (announcement.pinned) l.home_announcement_pinned_badge,
              ].join(' · '),
              style: AppTypography.footnote
                  .copyWith(color: colors.secondaryLabel),
            ),
            const SizedBox(height: 12),
            Text(
              announcement.body,
              style: AppTypography.body.copyWith(color: colors.label),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteSection extends ConsumerWidget {
  const _DeleteSection({required this.announcement});

  final AnnouncementRow announcement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    // Mesmo desenho da linha de excluir dos editores
    // (`admin/scale_type_editor_screen.dart`).
    return CupertinoListSection.insetGrouped(
      backgroundColor: colors.groupedBackground,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      children: [
        CupertinoListTile(
          title: Text(
            l.home_announcement_delete,
            style: AppTypography.body.copyWith(color: colors.destructive),
          ),
          onTap: () => _delete(context, ref),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l.home_announcement_delete,
      message: l.home_announcement_delete_confirm,
      confirmLabel: l.home_announcement_delete,
    );
    if (!confirmed || !context.mounted) return;

    final repo = ref.read(homeRepositoryProvider);
    try {
      await repo.deleteAnnouncement(announcement.id);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        showAppToast(
          context,
          announcementDeleteErrorMessage(l, e),
          isError: true,
        );
      }
    }
  }
}

/// Mensagem do l10n para uma falha ao excluir um aviso — a tela nunca mostra
/// o `toString()` de uma exceção do Postgrest (AGENTS.md §6, regra 6).
String announcementDeleteErrorMessage(AppLocalizations l, Object error) {
  final code = error is AppException ? error.code : null;
  return switch (code) {
    AppErrorCode.permissionDenied ||
    AppErrorCode.forbidden =>
      l.auth_error_permission_denied,
    AppErrorCode.permissionDeniedOrStale ||
    AppErrorCode.notFound =>
      l.auth_error_permission_denied_or_stale,
    AppErrorCode.noConnection => l.error_no_connection,
    AppErrorCode.timeout => l.auth_error_timeout,
    AppErrorCode.serverUnavailable => l.auth_error_server_unavailable,
    _ => l.auth_error_unknown,
  };
}
