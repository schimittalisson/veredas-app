import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/daos/prayer_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/moderation_providers.dart';

/// Providers do Mural de Oração — streams do drift sobre o cache local.

/// Feed completo (posts mais recentes primeiro).
final prayerFeedProvider = StreamProvider<List<PrayerFeedRow>>((ref) {
  return ref.watch(prayerDaoProvider).watchFeed();
});

/// Feed filtrado por texto de busca (no título).
///
/// O filtro é feito no provider (não no DAO) porque é específico da UI e
/// muda a cada caractere digitado. Com texto vazio, devolve o feed completo.
final prayerSearchProvider =
    NotifierProvider<PrayerSearchNotifier, String>(PrayerSearchNotifier.new);

class PrayerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

/// Feed sem o que a pessoa bloqueou ou denunciou.
///
/// O servidor já tira os posts de quem foi bloqueado (a view `prayer_feed`
/// filtra por `user_blocks`), mas isso só chega no próximo pull. O filtro aqui
/// é o que faz o post sumir no toque, inclusive offline — é o que a pessoa
/// espera de "bloquear" e "denunciar". Para o admin, a denúncia não esconde
/// nada (ver `reportedPostIdsProvider`); o bloqueio, que é escolha pessoal,
/// continua valendo.
///
/// O próprio post nunca é filtrado: o app não oferece bloquear nem denunciar
/// a si mesmo, e o RLS recusaria.
final visibleFeedProvider = Provider<List<PrayerFeedRow>>((ref) {
  final feed = ref.watch(prayerFeedProvider).value ?? const [];
  final blocked = ref.watch(blockedUserIdsProvider).value ?? const {};
  final reported = ref.watch(reportedPostIdsProvider).value ?? const {};
  if (blocked.isEmpty && reported.isEmpty) return feed;
  return feed
      .where((p) => !blocked.contains(p.authorId) && !reported.contains(p.id))
      .toList();
});

/// Feed filtrado pela busca atual. Se a busca está vazia, devolve o feed
/// visível inteiro.
final filteredFeedProvider = Provider<List<PrayerFeedRow>>((ref) {
  final feed = ref.watch(visibleFeedProvider);
  final query = ref.watch(prayerSearchProvider).trim().toLowerCase();
  if (query.isEmpty) return feed;
  return feed
      .where((p) => p.title.toLowerCase().contains(query))
      .toList();
});

/// Comentários de um post, com o nome do autor.
final commentsProvider =
    StreamProvider.family<List<PrayerComment>, String>((ref, postId) {
  return ref.watch(prayerDaoProvider).watchCommentsWithAuthor(postId);
});

/// Comentários de um post sem os de quem a pessoa bloqueou ou denunciou.
///
/// Só no cliente, e de propósito: `user_blocks` é sincronizado, então o
/// filtro já acompanha a pessoa em outro aparelho, que é o que justificou o
/// filtro duplo no feed. Pôr o bloqueio na policy de `prayer_comments` faria o
/// admin que bloqueou alguém deixar de conseguir apagar um comentário dele
/// (o RETURNING do outbox reprovaria).
final visibleCommentsProvider =
    Provider.family<List<PrayerComment>, String>((ref, postId) {
  final comments = ref.watch(commentsProvider(postId)).value ?? const [];
  final blocked = ref.watch(blockedUserIdsProvider).value ?? const {};
  final reported = ref.watch(reportedCommentIdsProvider).value ?? const {};
  if (blocked.isEmpty && reported.isEmpty) return comments;
  return comments
      .where(
        (c) =>
            !blocked.contains(c.row.authorId) && !reported.contains(c.row.id),
      )
      .toList();
});

/// Quantos comentários **visíveis** cada post tem.
///
/// Contado no cache em vez de usar o `comment_count` da view: o contador da
/// view só muda no próximo pull (um comentário feito sem sinal não apareceria
/// na conta) e inclui os comentários de quem a pessoa bloqueou, que ela não vê.
final commentCountsProvider = Provider<Map<String, int>>((ref) {
  final all = ref.watch(_allCommentsProvider).value ?? const [];
  final blocked = ref.watch(blockedUserIdsProvider).value ?? const {};
  final reported = ref.watch(reportedCommentIdsProvider).value ?? const {};
  final counts = <String, int>{};
  for (final c in all) {
    if (blocked.contains(c.authorId) || reported.contains(c.id)) continue;
    counts[c.postId] = (counts[c.postId] ?? 0) + 1;
  }
  return counts;
});

final _allCommentsProvider = StreamProvider<List<PrayerCommentRow>>((ref) {
  return ref.watch(prayerDaoProvider).watchAllComments();
});

/// Estado de "estou orando" em processo (para desabilitar o botão durante
/// o toggle otimista e evitar duplo toque).
///
/// Set de IDs de posts que estão sendo toggled.
final prayingToggleInProgressProvider = NotifierProvider<
    PrayingToggleInProgressNotifier, Set<String>>(
  PrayingToggleInProgressNotifier.new,
);

class PrayingToggleInProgressNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String postId) => state = {...state, postId};
  void remove(String postId) => state = state.where((id) => id != postId).toSet();
}
