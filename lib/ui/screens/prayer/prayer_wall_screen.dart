import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/data/models/profile.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/prayer_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
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
    final feed = ref.watch(filteredFeedProvider);
    final searchQuery = ref.watch(prayerSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.tab_oracao),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: l.prayer_search_hint,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: _clearSearch,
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        // Ver comentário em home_screen.dart: as 4 tabs coexistem.
        heroTag: 'fab-oracao',
        onPressed: () => context.push(Routes.oracaoNovo),
        tooltip: l.prayer_new,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Composer inline no topo do feed.
          const _InlineComposer(),
          const Divider(height: 1),
          // Feed.
          Expanded(
            child: feed.isEmpty
                ? (searchQuery.isNotEmpty
                    ? EmptyState(
                        title: l.prayer_no_results(searchQuery),
                        icon: Icons.search_off,
                      )
                    : EmptyState(
                        title: l.prayer_no_posts,
                        icon: Icons.favorite_outline,
                      ))
                : ListView.builder(
                    itemCount: feed.length,
                    itemBuilder: (context, i) => PrayerCard(post: feed[i]),
                  ),
          ),
        ],
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
    final profile = ref.watch(currentProfileProvider).value;

    return InkWell(
      onTap: () => context.push(Routes.oracaoNovo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                profile?.initials ?? '?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.prayer_composer_hint,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final theme = Theme.of(context);
    final post = widget.post;

    final isAnonymous = post.isAnonymous || post.authorName == null;
    final authorName = isAnonymous ? l.prayer_anonymous : post.authorName!;
    final currentUserId = ref.watch(currentUserIdProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final isAuthor = post.authorId == currentUserId;
    final canEdit = isAuthor || isAdmin;

    final inProgress =
        ref.watch(prayingToggleInProgressProvider).contains(post.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha do autor.
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: isAnonymous
                      ? Icon(
                          Icons.person,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : Text(
                          _initials(authorName),
                          style: theme.textTheme.labelSmall,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$authorName · ${timeago.format(post.createdAt, locale: 'pt_BR')}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (canEdit)
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      switch (value) {
                        case 'edit':
                          await context.push(
                            '${Routes.oracaoEditar}?id=${widget.post.id}',
                          );
                        case 'delete':
                          await _confirmDelete(context);
                        case 'mark_answered':
                          await _markAnswered(context);
                      }
                    },
                    itemBuilder: (context) => [
                      if (canEdit)
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(l.prayer_edit),
                        ),
                      if (canEdit)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l.prayer_delete),
                        ),
                      if (isAuthor || isAdmin)
                        PopupMenuItem(
                          value: 'mark_answered',
                          child: Text(l.prayer_mark_answered),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Título.
            Text(
              post.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l.prayer_answered,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Ações: orando + comentários.
            Row(
              children: [
                // Botão "Estou orando" — toggle otimista.
                ActionChip(
                  onPressed: inProgress ? null : () => _togglePraying(),
                  avatar: Icon(
                    post.isPraying
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 16,
                    color: post.isPraying
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    '${post.prayingCount} ${l.prayer_praying}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 12),
                // Comentários.
                Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  l.prayer_comments(post.commentCount),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.prayer_delete),
        content: Text(l.prayer_delete),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.action_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.prayer_delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(prayerRepositoryProvider).deletePost(widget.post.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
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
    final theme = Theme.of(context);

    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onToggle,
            child: Text(
              collapseLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: theme.textTheme.bodyMedium,
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
              style: theme.textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (exceeds) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onToggle,
                child: Text(
                  expandLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
