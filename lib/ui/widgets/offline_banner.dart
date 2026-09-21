import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/sync_providers.dart';

/// Banner no topo do body que indica o estado de sincronização.
///
/// Visível apenas quando há algo que o usuário precisa saber:
/// - **offline**: "Sem conexão — mostrando dados salvos"
/// - **error**: "Não foi possível sincronizar" com botão de tentar de novo
///
/// Nos estados `idle` e `syncing`, o banner não aparece.
///
/// **`syncing` não mostra nada de propósito.** A faixa "N alterações
/// aguardando envio" existia e foi retirada a pedido do solicitante: ela
/// expunha a outbox, que é detalhe de implementação, e confundia — a pessoa
/// salva algo, vê a tela já atualizada e ainda assim lê um aviso de que falta
/// enviar. Quem garante que a fila não fica parada é o gatilho de drenagem em
/// `SyncCoordinator`; se o envio falhar de verdade, o estado vira `error` e a
/// faixa volta com o botão de tentar de novo.
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
      SyncStatus.syncing => const SizedBox.shrink(),
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

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    this.icon,
    this.trailing,
    this.isError = false,
  });

  final String text;
  final IconData? icon;
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
            Icon(icon, size: 16, color: foreground),
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
