import 'package:flutter/material.dart';

/// Cabeçalho de seção ("Dados da Base", "Avisos anteriores", "Próximos
/// eventos"), com uma ação opcional à direita ("Ver tudo" no mockup).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert(
          actionLabel == null || onAction != null,
          'actionLabel sem onAction renderiza um botão morto.',
        );

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4, top: 24, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
