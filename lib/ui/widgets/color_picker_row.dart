import 'package:flutter/cupertino.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';

/// Linha de formulário para escolher a cor de um registro.
///
/// A cor é guardada como **índice na paleta**, não como hex: cada índice
/// resolve para um trio (traço, fundo, texto) com contraste já verificado, e
/// resolve diferente no tema claro e no escuro. Um hex fixo ficaria ilegível
/// num dos dois.
///
/// O valor chega pré-selecionado com a cor que a categoria já usa nos outros
/// registros (ver `categoryColorsProvider`). Sem isso, criar um segundo
/// compromisso da mesma categoria exigiria lembrar de repetir a cor — e
/// esquecer uma vez já quebra a leitura da grade.
class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return CupertinoFormRow(
      prefix: Text(
        l.agenda_color,
        style: AppTypography.body.copyWith(color: colors.label),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => _showPicker(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Swatch(index: value, selected: false, size: 22),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: colors.tertiaryLabel,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    final chosen = await showCupertinoModalPopup<int>(
      context: context,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.agenda_color,
                  style: AppTypography.headline.copyWith(color: colors.label),
                ),
                const SizedBox(height: 16),
                // Grade de amostras em vez de lista: com 10 cores, uma lista
                // vertical exigiria rolagem para ver a última, e comparar duas
                // cores distantes ficaria impossível.
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (int i = 0; i < colors.accentCount; i++)
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.of(sheetContext).pop(i),
                        child: _Swatch(
                          index: i,
                          selected: i == value,
                          size: 44,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(l.action_cancel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (chosen != null) onChanged(chosen);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.index,
    required this.selected,
    required this.size,
  });

  final int index;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Mostra o par que o registro vai usar de verdade: fundo pastel com o
        // traço vivo em volta, igual ao bloco na grade.
        color: colors.accentContainerAt(index),
        shape: BoxShape.circle,
        border: Border.all(color: colors.accentAt(index), width: 2),
      ),
      child: selected
          ? Icon(
              CupertinoIcons.check_mark,
              size: size * 0.5,
              color: colors.onAccentContainerAt(index),
            )
          : null,
    );
  }
}
