import 'package:flutter/cupertino.dart';

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

  /// Marca a confirmação como destrutiva — no iOS isso pinta o texto de
  /// vermelho, em vez de dar cor de fundo ao botão. Ligado por padrão, porque
  /// o caso de uso deste diálogo é exclusão.
  final bool isDestructive;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    String? confirmLabel,
    String? cancelLabel,
    bool isDestructive = true,
  }) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      // No iOS o toque fora não fecha um alerta — só os botões fecham. Manter
      // o padrão da plataforma evita fechar sem querer uma confirmação de
      // exclusão.
      barrierDismissible: false,
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

    return CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message!),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          // isDefaultAction põe o peso no cancelar: numa exclusão, a saída
          // segura é a que deve estar em destaque.
          isDefaultAction: true,
          child: Text(cancelLabel ?? l.action_cancel),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(true),
          isDestructiveAction: isDestructive,
          child: Text(
            confirmLabel ?? (isDestructive ? l.action_delete : l.action_confirm),
          ),
        ),
      ],
    );
  }
}
