import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';

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

/// Feed filtrado pela busca atual. Se a busca está vazia, devolve o feed cru.
final filteredFeedProvider = Provider<List<PrayerFeedRow>>((ref) {
  final feed = ref.watch(prayerFeedProvider).value ?? const [];
  final query = ref.watch(prayerSearchProvider).trim().toLowerCase();
  if (query.isEmpty) return feed;
  return feed
      .where((p) => p.title.toLowerCase().contains(query))
      .toList();
});

/// Comentários de um post.
final commentsProvider =
    StreamProvider.family<List<PrayerCommentRow>, String>((ref, postId) {
  return ref.watch(prayerDaoProvider).watchComments(postId);
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
