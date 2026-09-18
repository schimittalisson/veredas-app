import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';

/// Editor de um tipo de escala (uma aba da tela Escalas) — cria ou edita.
///
/// [scaleTypeId] null = criação.
///
/// O `slug` não aparece no formulário de propósito: ele é a chave estável do
/// tipo, derivada do nome na criação e imutável depois. Renomear "Almoço" para
/// "Almoço da base" é troca de rótulo, não de identidade.
class ScaleTypeEditorScreen extends ConsumerStatefulWidget {
  const ScaleTypeEditorScreen({super.key, this.scaleTypeId});

  final String? scaleTypeId;

  @override
  ConsumerState<ScaleTypeEditorScreen> createState() =>
      _ScaleTypeEditorScreenState();
}

// ---------------------------------------------------------------------------
// _ScaleTypeEditorScreenState
// ---------------------------------------------------------------------------

class _ScaleTypeEditorScreenState
    extends ConsumerState<ScaleTypeEditorScreen> {
  final _nameController = TextEditingController();
  final _slotsController = TextEditingController();

  String _cadence = 'weekly';
  bool _isActive = true;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.scaleTypeId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _slotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(_isEditing ? l.action_edit : l.admin_scales_new),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator()
              : Text(l.action_save),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoFormSection.insetGrouped(
              backgroundColor: colors.groupedBackground,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _nameController,
                  textAlign: TextAlign.end,
                  prefix: Text(
                    l.admin_scales_name,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  style: AppTypography.body.copyWith(color: colors.label),
                ),
                CupertinoFormRow(
                  prefix: Text(
                    l.admin_scales_cadence,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _pickCadence,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _cadenceLabel(l, _cadence),
                          style: AppTypography.body
                              .copyWith(color: colors.secondaryLabel),
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
                ),
              ],
            ),

            // Áreas decidem o formato da aba, então a explicação vem junto:
            // com áreas a escala vira grade, sem áreas vira lista por dia.
            CupertinoFormSection.insetGrouped(
              backgroundColor: colors.groupedBackground,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              footer: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  l.admin_scales_slots_helper,
                  style: AppTypography.footnote
                      .copyWith(color: colors.secondaryLabel),
                ),
              ),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _slotsController,
                  textAlign: TextAlign.end,
                  prefix: Text(
                    l.admin_scales_slots,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  style: AppTypography.body.copyWith(color: colors.label),
                ),
              ],
            ),

            CupertinoFormSection.insetGrouped(
              backgroundColor: colors.groupedBackground,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              footer: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  l.admin_scales_active_helper,
                  style: AppTypography.footnote
                      .copyWith(color: colors.secondaryLabel),
                ),
              ),
              children: [
                CupertinoFormRow(
                  prefix: Text(
                    l.admin_scales_active,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  child: CupertinoSwitch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ),
              ],
            ),

            if (_isEditing)
              CupertinoListSection.insetGrouped(
                backgroundColor: colors.groupedBackground,
                separatorColor: colors.separator,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  CupertinoListTile(
                    title: Text(
                      l.admin_scales_delete,
                      style: AppTypography.body
                          .copyWith(color: colors.destructive),
                    ),
                    onTap: _saving ? null : _delete,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadExisting() async {
    final row =
        await ref.read(scalesDaoProvider).getScaleType(widget.scaleTypeId!);
    if (row != null && mounted) {
      _nameController.text = row.name;
      _slotsController.text = row.slots.join(', ');
      setState(() {
        _cadence = row.cadence;
        _isActive = row.isActive;
        _loaded = true;
      });
    }
  }

  /// Folha de ações em vez de roda: são três opções, e a roda exigiria um
  /// "Pronto" para confirmar o que um toque já resolve.
  Future<void> _pickCadence() async {
    final l = AppLocalizations.of(context);

    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l.admin_scales_cadence),
        actions: [
          for (final c in const ['weekly', 'monthly', 'adhoc'])
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(c),
              child: Text(_cadenceLabel(l, c)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(l.action_cancel),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    setState(() => _cadence = picked);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      showAppToast(context, l.admin_scales_name_required, isError: true);
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(scalesRepositoryProvider);
    final slots = _parseSlots(_slotsController.text);

    try {
      if (_isEditing) {
        await repo.updateScaleType(
          id: widget.scaleTypeId!,
          name: name,
          cadence: _cadence,
          slots: slots,
          isActive: _isActive,
        );
      } else {
        await repo.createScaleType(
          name: name,
          cadence: _cadence,
          slots: slots,
        );
      }

      if (mounted) {
        showAppToast(context, l.admin_scales_saved);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString(), isError: true);
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);

    final confirmed = await ConfirmDialog.show(
      context,
      title: l.admin_scales_delete_confirm,
      // Diz o que acontece com o que já foi montado, e aponta a alternativa:
      // quem quer só tirar a aba do caminho deve desativar, não excluir.
      message: l.admin_scales_delete_message,
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(scalesRepositoryProvider)
          .deleteScaleType(widget.scaleTypeId!);
      if (mounted) {
        showAppToast(context, l.admin_scales_deleted);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString(), isError: true);
        setState(() => _saving = false);
      }
    }
  }

  /// "Preparo, Louça" -> ["Preparo", "Louça"]. Mesmo formato do campo de
  /// nomes sem conta no editor de atribuição.
  static List<String> _parseSlots(String raw) {
    return [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }
}

/// Rótulo da cadência guardada em `scale_types.cadence`.
String _cadenceLabel(AppLocalizations l, String cadence) => switch (cadence) {
      'monthly' => l.admin_scales_cadence_monthly,
      'adhoc' => l.admin_scales_cadence_adhoc,
      _ => l.admin_scales_cadence_weekly,
    };
