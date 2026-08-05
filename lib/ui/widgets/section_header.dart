import 'package:flutter/cupertino.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';

/// Cabeçalho de seção ("Dados da Base", "Avisos anteriores", "Próximos
/// eventos"), com uma ação opcional à direita ("Ver tudo" no mockup).
///
/// Segue o padrão das listas agrupadas do iOS: texto em maiúsculas, pequeno e
/// em cor secundária. É o que faz uma lista "parecer Ajustes do iPhone" — no
/// Material o mesmo cabeçalho seria grande e escuro.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.prominent = false,
    super.key,
  }) : assert(
          actionLabel == null || onAction != null,
          'actionLabel sem onAction renderiza um botão morto.',
        );

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Título forte e em caixa mista, em vez do cabeçalho discreto de lista
  /// agrupada.
  ///
  /// A tela Início não é uma lista de Ajustes: ela tem hierarquia editorial
  /// ("Perguntas Frequentes" é um bloco de conteúdo, não o rótulo de um grupo
  /// de células). Nesse caso o cabeçalho pequeno e em maiúsculas some no meio
  /// dos cartões.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: prominent ? 28 : 24,
        bottom: prominent ? 10 : 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              prominent ? title : title.toUpperCase(),
              style: prominent
                  ? AppTypography.title.copyWith(color: colors.label)
                  : AppTypography.sectionHeader
                      .copyWith(color: colors.secondaryLabel),
            ),
          ),
          if (actionLabel != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.footnote.copyWith(color: colors.tint),
              ),
            ),
        ],
      ),
    );
  }
}
