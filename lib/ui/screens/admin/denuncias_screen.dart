import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/report_reason.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/moderation_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';
import 'package:veredas/ui/widgets/pull_to_refresh.dart';

/// Denúncias pendentes do mural — a metade "alguém age sobre a denúncia" da
/// Guideline 1.2 da App Store.
///
/// Mostra a cópia do post tirada pelo servidor na hora da denúncia, e não o
/// post atual: o autor pode ter editado o texto, e o admin que bloqueou o
/// autor nem vê mais o post no feed.
///
/// Toda ação resolve a denúncia. "Excluir" e "Remover da base" também apagam o
/// conteúdo denunciado — o post, ou o comentário; "Manter" só tira a denúncia
/// da fila.
///
/// Numa denúncia de comentário, o título do post aparece como contexto, mas o
/// que se julga (e o que se apaga) é o comentário, e o autor mostrado é o do
/// comentário. O autor de um pedido anônimo continua sem aparecer.
class DenunciasScreen extends ConsumerWidget {
  const DenunciasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final reports = ref.watch(pendingReportsProvider);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.admin_reports),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        bottom: false,
        child: reports.when(
          loading: () => const RefreshableBox(child: LoadingState()),
          error: (_, _) => RefreshableBox(
            child: EmptyState(
              title: l.error_generic,
              icon: CupertinoIcons.exclamationmark_triangle,
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return RefreshableBox(
                child: EmptyState(
                  title: l.admin_reports_empty,
                  icon: CupertinoIcons.checkmark_shield,
                ),
              );
            }
            return RefreshableListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    l.admin_reports_deadline,
                    style: AppTypography.footnote
                        .copyWith(color: colors.secondaryLabel),
                  ),
                ),
                for (final r in list) _ReportCard(report: r),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ReportCard
// ---------------------------------------------------------------------------

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report});

  final ContentReportRow report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final authorName = _authorName(ref);
    final isComment = report.commentId != null;

    final reasonLabel = switch (ReportReason.fromWire(report.reason)) {
      ReportReason.offensive => l.report_reason_offensive,
      ReportReason.spam => l.report_reason_spam,
      ReportReason.other => l.report_reason_other,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showActions(context, ref, authorName),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$reasonLabel · ${l.admin_reports_reported_at(timeago.format(report.createdAt, locale: 'pt_BR'))}',
                    style: AppTypography.footnote
                        .copyWith(color: colors.destructive),
                  ),
                  const SizedBox(height: 6),
                  if (isComment)
                    Text(
                      l.admin_reports_comment_on(report.postTitle ?? ''),
                      style: AppTypography.footnote
                          .copyWith(color: colors.secondaryLabel),
                    )
                  else if (report.postTitle != null)
                    Text(
                      report.postTitle!,
                      style:
                          AppTypography.headline.copyWith(color: colors.label),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    (isComment ? report.commentBody : report.postBody) ??
                        l.admin_reports_text_unavailable,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppTypography.subheadline.copyWith(color: colors.label),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    authorName == null
                        ? l.admin_reports_author_anonymous
                        : l.admin_reports_author(authorName),
                    style: AppTypography.footnote
                        .copyWith(color: colors.secondaryLabel),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const CupertinoListTileChevron(),
          ],
        ),
      ),
    );
  }

  /// Quem escreveu o conteúdo denunciado: o comentário, se a denúncia é de
  /// comentário; senão, o post.
  String? get _authorId =>
      report.commentId != null ? report.commentAuthorId : report.postAuthorId;

  /// Nome do autor, ou `null` quando o pedido é anônimo.
  ///
  /// O anonimato vale também para o admin: a tela não revela quem escreveu um
  /// pedido anônimo, e por isso não oferece "remover da base" nele — excluir
  /// o pedido resolve a denúncia sem expor ninguém. Comentário nunca é
  /// anônimo, mesmo num pedido anônimo.
  String? _authorName(WidgetRef ref) {
    final authorId = _authorId;
    if (authorId == null) return null;
    if (report.commentId == null && report.postIsAnonymous) return null;
    final profiles = ref.watch(allProfilesProvider).value ?? const [];
    return profiles.where((p) => p.id == authorId).firstOrNull?.fullName;
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    String? authorName,
  ) async {
    final l = AppLocalizations.of(context);
    final currentUserId = ref.read(currentUserIdProvider);
    // Sem nome não há como confirmar quem sai, e o próprio admin não se
    // remove por aqui (a tela de Membros tem a proteção do último admin).
    final isComment = report.commentId != null;
    final authorId = _authorId;
    final canRemoveAuthor = authorName != null && authorId != currentUserId;

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('delete'),
            isDestructiveAction: true,
            child: Text(
              isComment
                  ? l.admin_reports_delete_comment
                  : l.admin_reports_delete_post,
            ),
          ),
          if (canRemoveAuthor)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('remove'),
              isDestructiveAction: true,
              child: Text(l.admin_reports_remove_member(authorName)),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('keep'),
            child: Text(
              isComment ? l.admin_reports_keep_comment : l.admin_reports_keep,
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(l.action_cancel),
        ),
      ),
    );
    if (action == null || !context.mounted || currentUserId == null) return;

    var confirmed = true;
    if (action == 'delete') {
      confirmed = await ConfirmDialog.show(
        context,
        title: isComment
            ? l.admin_reports_delete_comment_confirm
            : l.prayer_delete_confirm,
        confirmLabel: l.action_delete,
      );
    } else if (action == 'remove') {
      confirmed = await ConfirmDialog.show(
        context,
        title: l.admin_reports_remove_member(authorName!),
        message: isComment
            ? l.admin_reports_remove_confirm_comment(authorName)
            : l.admin_reports_remove_confirm(authorName),
        confirmLabel: l.admin_action_remove,
      );
    }
    if (!confirmed || !context.mounted) return;

    // O cartão sai da lista assim que a denúncia é resolvida no cache.
    final overlay = Overlay.of(context);
    final colors = context.colors;
    final moderation = ref.read(moderationRepositoryProvider);
    final prayers = ref.read(prayerRepositoryProvider);
    final admin = ref.read(adminServiceProvider);

    try {
      // Remover a pessoa é RPC direta (como na tela de Membros) e pode falhar
      // — por exemplo, sem conexão. Vem primeiro para que, se falhar, a
      // denúncia continue na fila em vez de sumir sem a ação ter acontecido.
      if (action == 'remove') {
        await admin.softDeleteUser(userId: authorId!);
      }
      // Resolver antes de apagar: as duas vão pela outbox, na ordem, e o
      // trigger do servidor também resolve ao apagar — a ordem só importa
      // para o cache, onde a denúncia precisa sair da fila na hora.
      await moderation.resolveReport(
        reportId: report.id,
        resolvedBy: currentUserId,
      );
      if (action != 'keep') {
        if (isComment) {
          await prayers.deleteComment(report.commentId!);
        } else {
          await prayers.deletePost(report.postId);
        }
      }
      showAppToastIn(overlay, colors, l.admin_reports_resolved);
    } catch (_) {
      showAppToastIn(overlay, colors, l.error_generic, isError: true);
    }
  }
}
