import 'package:flutter/material.dart';

/// Estado vazio compartilhado por todas as listas do app.
///
/// Centralizado para que "nenhum evento neste dia" e "escala ainda não montada"
/// tenham exatamente o mesmo peso visual — e para que a mensagem venha sempre
/// do l10n, nunca hardcoded na tela.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;

  /// Botão de saída do estado vazio (ex.: "Montar escala"), quando o usuário
  /// tem permissão para resolver o vazio. Omitir se ele só pode esperar.
  final Widget? action;

  /// Versão reduzida, para encaixar abaixo de um calendário ou dentro de um
  /// card, onde a versão de tela cheia empurraria o conteúdo para fora.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 32,
          vertical: compact ? 24 : 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 36 : 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: compact ? 12 : 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: (compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium)
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? 16 : 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
