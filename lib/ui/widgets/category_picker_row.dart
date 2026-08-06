import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/agenda_providers.dart';

/// Linha de formulário para escolher a categoria — e, com ela, a cor.
///
/// **Por que escolher categoria e não cor.** A cor de um compromisso não é um
/// atributo guardado no banco: ela é derivada da categoria por
/// `AppColors.accentFor`, que converte a string numa das cinco cores do
/// vitral de forma estável entre dispositivos. Isso é o que faz "roxo é
/// intercessão" valer na grade inteira, sem coluna de cor e sem risco de dois
/// registros da mesma categoria saírem com cores diferentes.
///
/// Então o seletor mostra as categorias **já em uso**, cada uma com a sua
/// bolinha: o usuário vê a cor que vai receber antes de escolher. "Outra…"
/// continua permitindo criar uma categoria nova — sem isso, a migração para
/// este seletor tiraria uma capacidade que o campo de texto livre tinha.
class CategoryPickerRow extends ConsumerWidget {
  const CategoryPickerRow({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Categoria atual. Vazio significa "nenhuma".
  final String value;

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final hasValue = value.trim().isNotEmpty;

    return CupertinoFormRow(
      prefix: Text(
        l.agenda_event_category,
        style: AppTypography.body.copyWith(color: colors.label),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => _showPicker(context, ref),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasValue) ...[
              _Swatch(category: value),
              const SizedBox(width: 8),
            ],
            Text(
              hasValue ? value : l.agenda_category_none,
              style: AppTypography.body.copyWith(color: colors.secondaryLabel),
            ),
            const SizedBox(width: 4),
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

  Future<void> _showPicker(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final categories = ref.read(usedCategoriesProvider);

    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l.agenda_event_category),
        actions: [
          for (final category in categories)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(category),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Swatch(category: category),
                  const SizedBox(width: 10),
                  Text(category),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('__new__'),
            child: Text(l.agenda_category_new),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('__none__'),
            child: Text(l.agenda_category_none),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(l.action_cancel),
        ),
      ),
    );

    if (choice == null || !context.mounted) return;

    if (choice == '__none__') {
      onChanged('');
      return;
    }
    if (choice == '__new__') {
      final created = await _promptNewCategory(context);
      if (created != null && created.trim().isNotEmpty) {
        onChanged(created.trim());
      }
      return;
    }
    onChanged(choice);
  }

  Future<String?> _promptNewCategory(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();

    return showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l.agenda_category_new),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: l.agenda_event_category,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.action_cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l.action_save),
          ),
        ],
      ),
    );
  }
}

/// Bolinha com a cor que a categoria vai receber na grade.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: colors.accentContainerFor(category),
        shape: BoxShape.circle,
        border: Border.all(color: colors.accentFor(category), width: 2),
      ),
    );
  }
}
