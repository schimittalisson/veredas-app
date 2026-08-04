import 'package:flutter/material.dart';

import 'package:veredas/l10n/app_localizations.dart';

/// Diálogo de confirmação para ações destrutivas.
///
/// Toda exclusão do app passa por aqui. Retorna `true` só na confirmação
/// explícita — tocar fora ou usar o botão voltar retorna `null`, que o
/// `?? false` do chamador trata como cancelamento.
///
/// ```dart
/// if (await ConfirmDialog.show(context, title: l.delete_post_title)) {
///   // ...
/// }
/// ```
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    required this.title,
    this.message,
    this.confirmLabel,
    this.cancelLabel,
    this.isDestructive = true,
    super.key,
  });

  final String title;
  final String? message;
  final String? confirmLabel;
  final String? cancelLabel;

  /// Pinta o botão de confirmação com `colorScheme.error`. Ligado por padrão,
  /// porque o caso de uso deste diálogo é exclusão.
  final bool isDestructive;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    String? confirmLabel,
    String? cancelLabel,
    bool isDestructive = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message!),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel ?? l.action_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          child: Text(
            confirmLabel ?? (isDestructive ? l.action_delete : l.action_confirm),
          ),
        ),
      ],
    );
  }
}
