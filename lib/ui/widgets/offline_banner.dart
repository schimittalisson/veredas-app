import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
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
///
/// Era um `MaterialBanner`, que não tem equivalente no Cupertino. A versão
/// própria é uma faixa fina e discreta: o iOS comunica estado de conexão sem
/// roubar altura da tela (pense na pílula de gravação de tela).
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final l = AppLocalizations.of(context);

    return switch (status) {
      SyncStatus.idle => const SizedBox.shrink(),
      SyncStatus.offline => _Banner(
          icon: CupertinoIcons.wifi_slash,
          text: l.offline_showing_cached,
        ),
      SyncStatus.syncing => _PendingBanner(l: l),
      SyncStatus.error => _Banner(
          icon: CupertinoIcons.exclamationmark_triangle,
          text: l.error_generic,
          isError: true,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => ref.read(syncStatusProvider.notifier).pullAll(),
            child: Text(
              l.action_retry,
              style: AppTypography.footnoteEmphasis
                  .copyWith(color: context.colors.tint),
            ),
          ),
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
    final count = ref.watch(pendingOutboxCountProvider).value ?? 0;

    if (count == 0) {
      // Sincronizando sem pendentes: é um pull em andamento.
      return _Banner(
        leading: const CupertinoActivityIndicator(radius: 7),
        text: l.offline_showing_cached,
      );
    }

    return _Banner(
      icon: CupertinoIcons.arrow_up_circle,
      text: l.offline_pending_changes(count),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    this.icon,
    this.leading,
    this.trailing,
    this.isError = false,
  });

  final String text;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = isError ? colors.destructive : colors.secondaryLabel;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        border: Border(
          bottom: BorderSide(color: colors.separator, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            leading ?? Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: AppTypography.footnote.copyWith(color: foreground),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
