import 'package:flutter/cupertino.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';

/// Estado de erro compartilhado.
///
/// Recebe uma **mensagem já localizada**, nunca uma exceção. A tela é
/// responsável por traduzir o `code` da `AppException` numa string do l10n
/// antes de chegar aqui.
///
/// Isto é deliberado: exibir `'Error: $e'` vaza detalhe de implementação (e
/// eventualmente payload de `PostgrestException`) para o usuário, em inglês.
/// É um erro explícito que o projeto de referência comete e que não repetimos.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.message,
    this.title,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  final String message;
  final String? title;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

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
              CupertinoIcons.exclamationmark_circle,
              size: compact ? 36 : 56,
              color: colors.destructive,
            ),
            SizedBox(height: compact ? 12 : 20),
            Text(
              title ?? l.error_default_title,
              textAlign: TextAlign.center,
              style: AppTypography.headline.copyWith(color: colors.label),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.subheadline
                  .copyWith(color: colors.secondaryLabel),
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? 16 : 24),
              CupertinoButton(
                onPressed: onRetry,
                child: Text(l.action_retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
