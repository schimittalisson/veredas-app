import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Providers da tela Início — streams do drift sobre o cache local.
///
/// A UI observa estes providers e reage a mudanças no cache (que são
/// alimentadas pelo SyncService). Sem rede, o cache continua disponível.

/// Todos os avisos, ordenados: fixados primeiro, depois por data decrescente.
/// A ordenação já vem do DAO; este provider só expõe o stream.
final announcementsProvider = StreamProvider<List<AnnouncementRow>>((ref) {
  return ref.watch(homeDaoProvider).watchAnnouncements();
});

/// O aviso fixado no topo (primeiro com `pinned = true`), ou null se não houver.
final pinnedAnnouncementProvider = Provider<AnnouncementRow?>((ref) {
  final announcements = ref.watch(announcementsProvider).value ?? const [];
  return announcements.where((a) => a.pinned).firstOrNull;
});

/// Avisos não fixados (para a seção "Avisos anteriores"), limite 10.
final recentAnnouncementsProvider = Provider<List<AnnouncementRow>>((ref) {
  final announcements = ref.watch(announcementsProvider).value ?? const [];
  final notPinned = announcements.where((a) => !a.pinned).toList();
  if (notPinned.length <= 10) return notPinned;
  return notPinned.sublist(0, 10);
});

/// Dados da base (acordeão), ordenados por `ordering`.
final baseInfoProvider = StreamProvider<List<BaseInfoRow>>((ref) {
  return ref.watch(homeDaoProvider).watchBaseInfo();
});

/// Links sociais ativos, ordenados por `ordering`.
final socialLinksProvider = StreamProvider<List<SocialLinkRow>>((ref) {
  return ref.watch(homeDaoProvider).watchSocialLinks();
});
