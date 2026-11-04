import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/daos/prayer_dao.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/prayer_providers.dart';
import 'package:veredas/ui/screens/prayer/prayer_wall_screen.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/report_reason_sheet.dart';
import 'package:veredas/ui/widgets/section_header.dart';

/// Detalhe de uma oração: o cartão inteiro, os comentários e o campo para
/// comentar.
///
/// O cartão mostrava "0 comentários" desde a Fase 8, mas não havia onde
/// comentar — a tabela e o sync existiam, a tela não.
///
/// **A oração vem do feed visível, não do feed bruto.** Se a pessoa bloquear
/// o autor ou denunciar a oração pelo menu do cartão aqui em cima, ou se ela
/// for excluída (aqui ou pelo sync), a tela cai no estado vazio em vez de
/// continuar mostrando o que acabou de ser escondido.
///
/// **Comentário é conteúdo de usuário** e entra na Guideline 1.2 da App Store
/// como o pedido: todo comentário alheio tem denunciar e bloquear no menu.
/// Não há "Editar" de comentário: é uma linha de conversa, e apagar e
/// escrever de novo cobre o caso sem mais uma tela.
class PrayerDetailScreen extends ConsumerStatefulWidget {
  const PrayerDetailScreen({required this.postId, super.key});

  final String postId;

  @override
  ConsumerState<PrayerDetailScreen> createState() => _PrayerDetailScreenState();
}

class _PrayerDetailScreenState extends ConsumerState<PrayerDetailScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  /// Liga a rolagem até o fim quando o comentário recém-enviado chegar pelo
  /// stream. Rolar logo depois do `await` não serve: a emissão do drift pode
  /// vir depois, e a lista ainda não teria o item novo.
  bool _scrollOnNextComment = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final post = ref
        .watch(visibleFeedProvider)
        .where((p) => p.id == widget.postId)
        .firstOrNull;
    final loading = ref.watch(prayerFeedProvider).isLoading;
    final comments = ref.watch(visibleCommentsProvider(widget.postId));

    ref.listen(visibleCommentsProvider(widget.postId), (prev, next) {
      if (!_scrollOnNextComment || next.length <= (prev?.length ?? 0)) return;
      _scrollOnNextComment = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.prayer_detail_title),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        child: post == null
            ? (loading
                ? const Center(child: CupertinoActivityIndicator())
                : EmptyState(
                    title: l.prayer_detail_not_found,
                    icon: CupertinoIcons.heart_slash,
                  ))
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      children: [
                        PrayerCard(post: post, inDetail: true),
                        SectionHeader(title: l.prayer_comments_section),
                        if (comments.isEmpty)
                          EmptyState(
                            title: l.prayer_comments_empty,
                            icon: CupertinoIcons.chat_bubble,
                            compact: true,
                          )
                        else
                          for (final c in comments) _CommentTile(comment: c),
                      ],
                    ),
                  ),
                  _Composer(
                    controller: _controller,
                    sending: _sending,
                    onSend: _send,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    final userId = ref.read(currentUserIdProvider);
    if (body.isEmpty || userId == null || _sending) return;

    final l = AppLocalizations.of(context);
    setState(() => _sending = true);
    _scrollOnNextComment = true;
    try {
      await ref.read(prayerRepositoryProvider).addComment(
            postId: widget.postId,
            authorId: userId,
            body: body,
          );
      _controller.clear();
    } catch (_) {
      _scrollOnNextComment = false;
      if (mounted) showAppToast(context, l.error_generic, isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Campo de comentário
// ---------------------------------------------------------------------------

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        border: Border(top: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: controller,
                placeholder: l.prayer_comment_hint,
                minLines: 1,
                maxLines: 5,
                // O CHECK de `prayer_comments.body` vai até 2000.
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                style: AppTypography.body.copyWith(color: colors.label),
                placeholderStyle:
                    AppTypography.body.copyWith(color: colors.tertiaryLabel),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // O botão só acende com texto: enviar vazio seria recusado pelo
            // CHECK do servidor depois de já ter aparecido na tela.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final enabled = !sending && value.text.trim().isNotEmpty;
                return CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 36),
                  onPressed: enabled ? onSend : null,
                  child: sending
                      ? const CupertinoActivityIndicator()
                      : Text(l.prayer_comment_send),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comentário
// ---------------------------------------------------------------------------

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment});

  final PrayerComment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final row = comment.row;
    final name = comment.authorName;
    final displayName = name ?? l.prayer_comment_author_unknown;

    final currentUserId = ref.watch(currentUserIdProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final isAuthor = row.authorId == currentUserId;
    final canDelete = isAuthor || isAdmin;
    final canReport = !isAuthor && currentUserId != null;
    // Sem nome não há o que pôr no "Bloquear …" nem na lista de bloqueados.
    final blockName = canReport ? name : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.tintContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(displayName),
              style:
                  AppTypography.caption2.copyWith(color: colors.onTintContainer),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$displayName · '
                  '${timeago.format(row.createdAt, locale: 'pt_BR')}',
                  style: AppTypography.footnote
                      .copyWith(color: colors.secondaryLabel),
                ),
                const SizedBox(height: 2),
                Text(
                  row.body,
                  style:
                      AppTypography.subheadline.copyWith(color: colors.label),
                ),
              ],
            ),
          ),
          if (canDelete || canReport)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              onPressed: () => _showActions(
                context,
                ref,
                canDelete: canDelete,
                canReport: canReport,
                blockName: blockName,
              ),
              child: Icon(
                CupertinoIcons.ellipsis,
                size: 18,
                color: colors.secondaryLabel,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref, {
    required bool canDelete,
    required bool canReport,
    required String? blockName,
  }) async {
    final l = AppLocalizations.of(context);

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          if (canDelete)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('delete'),
              isDestructiveAction: true,
              child: Text(l.prayer_delete),
            ),
          if (canReport)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('report'),
              child: Text(l.prayer_report),
            ),
          if (blockName != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('block'),
              isDestructiveAction: true,
              child: Text(l.prayer_block(blockName)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(l.action_cancel),
        ),
      ),
    );
    if (!context.mounted) return;

    switch (action) {
      case 'delete':
        await _delete(context, ref);
      case 'report':
        await _report(context, ref);
      case 'block':
        await _block(context, ref, blockName!);
    }
  }

  // Nas três ações, tudo o que é usado depois do `await` da escrita é
  // capturado antes dele: a escrita tira o comentário da lista, e se o stream
  // do drift emitir antes de o await voltar, esta célula já foi desmontada.
  // Mesmo cuidado do `PrayerCard`.

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l.prayer_comment_delete_confirm,
      confirmLabel: l.prayer_delete,
    );
    if (!confirmed || !context.mounted) return;

    final repo = ref.read(prayerRepositoryProvider);
    final overlay = Overlay.of(context);
    final colors = context.colors;
    try {
      await repo.deleteComment(comment.row.id);
    } catch (_) {
      showAppToastIn(overlay, colors, l.error_generic, isError: true);
    }
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final reason = await showReportReasonSheet(
      context,
      title: l.prayer_comment_report_title,
    );
    if (reason == null || !context.mounted) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final repo = ref.read(moderationRepositoryProvider);
    final overlay = Overlay.of(context);
    final colors = context.colors;
    try {
      final sent = await repo.reportComment(
        commentId: comment.row.id,
        reporterId: userId,
        reason: reason,
      );
      showAppToastIn(
        overlay,
        colors,
        sent ? l.prayer_comment_report_sent : l.prayer_comment_report_already,
      );
    } catch (_) {
      showAppToastIn(overlay, colors, l.error_generic, isError: true);
    }
  }

  Future<void> _block(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final l = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l.prayer_block_confirm_title(name),
      message: l.prayer_block_confirm_message,
      confirmLabel: l.prayer_block_action,
    );
    if (!confirmed || !context.mounted) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final repo = ref.read(moderationRepositoryProvider);
    final overlay = Overlay.of(context);
    final colors = context.colors;
    try {
      await repo.blockUser(blockerId: userId, blockedId: comment.row.authorId);
      showAppToastIn(overlay, colors, l.prayer_block_done);
    } catch (_) {
      showAppToastIn(overlay, colors, l.error_generic, isError: true);
    }
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first.substring(0, 1);
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.substring(0, 1)).toUpperCase();
  }
}
