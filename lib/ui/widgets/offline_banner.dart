import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/sync_providers.dart';

/// Banner no topo do body que indica o estado de sincronização.
///
/// Visível apenas quando há algo a comunicar:
/// - **offline**: "Sem conexão — mostrando dados salvos"
/// - **syncing** com pendentes: "N alterações aguardando envio"
/// - **error**: "Não foi possível sincronizar" com botão de tentar de novo
///
/// No estado `idle`, o banner não aparece — a UI fica limpa.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final l = AppLocalizations.of(context);

    return switch (status) {
      SyncStatus.idle => const SizedBox.shrink(),
      SyncStatus.offline => MaterialBanner(
          content: Text(l.offline_showing_cached),
          leading: const Icon(Icons.cloud_off, size: 20),
          actions: const [SizedBox.shrink()],
        ),
      SyncStatus.syncing => _PendingBanner(l: l),
      SyncStatus.error => MaterialBanner(
          content: Text(l.error_generic),
          leading: const Icon(Icons.sync_problem, size: 20),
          actions: [
            TextButton(
              onPressed: () =>
                  ref.read(syncStatusProvider.notifier).pullAll(),
              child: Text(l.action_retry),
            ),
          ],
        ),
    };
  }
}

class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // O número de pendentes vem da outbox. O StreamProvider pode não ter
    // resolvido ainda no primeiro frame; usa 0 como fallback (o banner
    // aparece quando o stream emite).
    final hasPending =
        ref.watch(hasPendingOutboxProvider).value ?? false;
    if (!hasPending) {
      // Sincronizando sem pendentes: é um pull em andamento. Mostra um
      // indicador discreto.
      return MaterialBanner(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l.offline_showing_cached),
          ],
        ),
        actions: const [SizedBox.shrink()],
      );
    }

    return MaterialBanner(
      content: Text(l.offline_pending_changes(1)),
      leading: const Icon(Icons.sync, size: 20),
      actions: const [SizedBox.shrink()],
    );
  }
}
