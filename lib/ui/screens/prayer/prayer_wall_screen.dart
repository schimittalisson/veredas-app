import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/data/models/profile.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/prayer_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Mural de Oração — quarta tab.
///
/// Feed estilo Twitter com busca por título (debounce 400 ms), composer inline
/// no topo, cartões com "estou orando" (toggle otimista) e badge "Respondido".
class PrayerWallScreen extends ConsumerStatefulWidget {
  const PrayerWallScreen({super.key});

  @override
  ConsumerState<PrayerWallScreen> createState() => _PrayerWallScreenState();
}

class _PrayerWallScreenState extends ConsumerState<PrayerWallScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounce de 400 ms antes de disparar a busca — mesmo padrão do
    // CalorieMate. Evita filtrar a cada caractere.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(prayerSearchProvider.notifier).update(value);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    ref.read(prayerSearchProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final feed = ref.watch(filteredFeedProvider);
    final searchQuery = ref.watch(prayerSearchProvider);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.tab_oracao),
        backgroundColor: colors.elevatedSurface,
        // O iOS não tem FloatingActionButton: a ação principal da tela mora
        // no canto direito da barra de navegação.
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => context.push(Routes.oracaoNovo),
          // O CupertinoButton não tem `tooltip` como o FAB tinha; o rótulo do
          // l10n vira semântica para o leitor de tela.
          child: Semantics(
            label: l.prayer_new,
            button: true,
            child: const Icon(CupertinoIcons.add),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // A busca sai do `bottom` da AppBar (que não existe na
            // CupertinoNavigationBar) e passa a ser a primeira linha do corpo.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: CupertinoSearchTextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                placeholder: l.prayer_search_hint,
                backgroundColor: colors.fill,
                style: AppTypography.body.copyWith(color: colors.label),
                placeholderStyle: AppTypography.body.copyWith(
                  color: colors.tertiaryLabel,
                ),
                // O botão de limpar já é nativo do campo — só precisamos
                // limpar também o debounce e o provider de busca.
                onSuffixTap: _clearSearch,
              ),
            ),
            // Composer inline no topo do feed.
            const _InlineComposer(),
            Container(height: 0.5, color: colors.separator),
            // Feed.
            Expanded(
              child: feed.isEmpty
                  ? (searchQuery.isNotEmpty
                      ? EmptyState(
                          title: l.prayer_no_results(searchQuery),
                          icon: CupertinoIcons.search,
                        )
                      : EmptyState(
                          title: l.prayer_no_posts,
                          icon: CupertinoIcons.heart,
                        ))
                  : ListView.builder(
                      itemCount: feed.length,
                      itemBuilder: (context, i) => PrayerCard(post: feed[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composer inline (avatar + campo falso que navega para /oracao/novo)
// ---------------------------------------------------------------------------

class _InlineComposer extends ConsumerWidget {
  const _InlineComposer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final profile = ref.watch(currentProfileProvider).value;

    // GestureDetector no lugar do InkWell: o ripple é um efeito do Material e
    // não existe no iOS — lá o feedback de toque de uma linha é a navegação
    // em si.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(Routes.oracaoNovo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.tintContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                profile?.initials ?? '?',
                style: AppTypography.subheadline.copyWith(
                  color: colors.onTintContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.prayer_composer_hint,
                style: AppTypography.body.copyWith(
                  color: colors.secondaryLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cartão do post
// ---------------------------------------------------------------------------

class PrayerCard extends ConsumerStatefulWidget {
  const PrayerCard({required this.post, super.key});

  final PrayerFeedRow post;

  @override
  ConsumerState<PrayerCard> createState() => _PrayerCardState();
}

class _PrayerCardState extends ConsumerState<PrayerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final post = widget.post;

    final isAnonymous = post.isAnonymous || post.authorName == null;
    final authorName = isAnonymous ? l.prayer_anonymous : post.authorName!;
    final currentUserId = ref.watch(currentUserIdProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final isAuthor = post.authorId == currentUserId;
    final canEdit = isAuthor || isAdmin;

    final inProgress =
        ref.watch(prayingToggleInProgressProvider).contains(post.id);

    // Cartão sem Material: um contêiner arredondado sobre o fundo agrupado,
    // que é como o iOS separa conteúdo em listas.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha do autor.
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.tintContainer,
                    shape: BoxShape.circle,
                  ),
                  child: isAnonymous
                      ? Icon(
                          CupertinoIcons.person_fill,
                          size: 18,
                          color: colors.onTintContainer,
                        )
                      : Text(
                          _initials(authorName),
                          style: AppTypography.caption.copyWith(
                            color: colors.onTintContainer,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$authorName · ${timeago.format(post.createdAt, locale: 'pt_BR')}',
                    style: AppTypography.footnote.copyWith(
                      color: colors.secondaryLabel,
                    ),
                  ),
                ),
                if (canEdit)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () => _showActions(
                      canEdit: canEdit,
                      isAuthor: isAuthor,
                      isAdmin: isAdmin,
                    ),
                    child: Icon(
                      CupertinoIcons.ellipsis,
                      size: 20,
                      color: colors.secondaryLabel,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Título.
            Text(
              post.title,
              style: AppTypography.headline.copyWith(color: colors.label),
            ),
            const SizedBox(height: 4),
            // Corpo (3 linhas + "ver mais").
            _ExpandableText(
              text: post.body,
              expanded: _expanded,
              onToggle: () => setState(() => _expanded = !_expanded),
              expandLabel: l.prayer_ver_more,
              collapseLabel: l.prayer_ver_less,
            ),
            const SizedBox(height: 8),
            // Badge "Respondido".
            if (post.answeredAt != null) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.success,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        size: 14,
                        color: colors.onTint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l.prayer_answered,
                        style: AppTypography.caption.copyWith(
                          color: colors.onTint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Ações: orando + comentários.
            Row(
              children: [
                // Botão "Estou orando" — toggle otimista.
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: inProgress ? null : () => _togglePraying(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.fill,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            post.isPraying
                                ? CupertinoIcons.heart_fill
                                : CupertinoIcons.heart,
                            size: 16,
                            color: post.isPraying
                                ? colors.tint
                                : colors.secondaryLabel,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${post.prayingCount} ${l.prayer_praying}',
                            style: AppTypography.caption.copyWith(
                              color: colors.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Comentários.
                Icon(
                  CupertinoIcons.chat_bubble,
                  size: 16,
                  color: colors.secondaryLabel,
                ),
                const SizedBox(width: 4),
                Text(
                  l.prayer_comments(post.commentCount),
                  style: AppTypography.caption.copyWith(
                    color: colors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Substitui o `PopupMenuButton` do Material.
  ///
  /// No iOS um menu de opções sobre um item de lista é uma action sheet vinda
  /// de baixo — as mesmas três ações, com "Excluir" em vermelho e um
  /// "Cancelar" separado, que o menu suspenso do Material não tem.
  // Sem parâmetro `BuildContext`: ele sombrearia o `State.context` e o
  // `if (!mounted)` abaixo passaria a guardar um contexto diferente do que é
  // usado depois do await — exatamente o que o lint
  // use_build_context_synchronously acusa.
  Future<void> _showActions({
    required bool canEdit,
    required bool isAuthor,
    required bool isAdmin,
  }) async {
    final l = AppLocalizations.of(context);

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          if (canEdit)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('edit'),
              child: Text(l.prayer_edit),
            ),
          if (canEdit)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('delete'),
              isDestructiveAction: true,
              child: Text(l.prayer_delete),
            ),
          if (isAuthor || isAdmin)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('mark_answered'),
              child: Text(l.prayer_mark_answered),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(l.action_cancel),
        ),
      ),
    );

    if (!mounted) return;

    switch (action) {
      case 'edit':
        await context.push(
          '${Routes.oracaoEditar}?id=${widget.post.id}',
        );
      case 'delete':
        await _confirmDelete(context);
      case 'mark_answered':
        await _markAnswered(context);
    }
  }

  Future<void> _togglePraying() async {
    final post = widget.post;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    // Marca como em progresso para desabilitar o botão (evita duplo toque).
    ref.read(prayingToggleInProgressProvider.notifier).add(post.id);

    try {
      // Toggle otimista via repositório: ajusta o cache da view e enfileira
      // INSERT/DELETE em prayer_interactions na outbox.
      await ref.read(prayerRepositoryProvider).togglePraying(
            postId: post.id,
            userId: userId,
          );
    } finally {
      ref.read(prayingToggleInProgressProvider.notifier).remove(post.id);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l = AppLocalizations.of(context);
    // O ConfirmDialog já é o CupertinoAlertDialog padrão do app — evita
    // reconstruir o mesmo alerta em cada tela.
    final confirmed = await ConfirmDialog.show(
      context,
      title: l.prayer_delete_confirm,
      confirmLabel: l.prayer_delete,
    );

    if (!confirmed) return;

    try {
      await ref.read(prayerRepositoryProvider).deletePost(widget.post.id);
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString(), isError: true);
      }
    }
  }

  Future<void> _markAnswered(BuildContext context) async {
    try {
      await ref.read(prayerRepositoryProvider).markAnswered(
            id: widget.post.id,
          );
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString(), isError: true);
      }
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    final first = parts.first.substring(0, 1);
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.substring(0, 1)).toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// Texto expansível (3 linhas + "ver mais")
// ---------------------------------------------------------------------------

class _ExpandableText extends StatelessWidget {
  const _ExpandableText({
    required this.text,
    required this.expanded,
    required this.onToggle,
    required this.expandLabel,
    required this.collapseLabel,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;
  final String expandLabel;
  final String collapseLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.subheadline.copyWith(color: colors.label);
    final linkStyle = AppTypography.caption.copyWith(color: colors.tint);

    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: bodyStyle),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onToggle,
            child: Text(collapseLabel, style: linkStyle),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: bodyStyle,
          ),
          maxLines: 3,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final exceeds = textPainter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: bodyStyle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (exceeds) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onToggle,
                child: Text(expandLabel, style: linkStyle),
              ),
            ],
          ],
        );
      },
    );
  }
}
