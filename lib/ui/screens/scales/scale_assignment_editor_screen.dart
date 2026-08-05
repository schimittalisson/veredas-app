import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';

/// Editor de atribuição de escala — cria ou edita.
///
/// [scaleTypeId] é sempre necessário (define em qual escala a atribuição
/// será criada). [assignmentId] é null para criação.
class ScaleAssignmentEditorScreen extends ConsumerStatefulWidget {
  const ScaleAssignmentEditorScreen({
    super.key,
    required this.scaleTypeId,
    this.assignmentId,
  });

  final String scaleTypeId;
  final String? assignmentId;

  @override
  ConsumerState<ScaleAssignmentEditorScreen> createState() =>
      _ScaleAssignmentEditorScreenState();
}

class _ScaleAssignmentEditorScreenState
    extends ConsumerState<ScaleAssignmentEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskController = TextEditingController();
  final _assigneeNameController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _date = DateTime.now();
  String? _slot;
  String? _assigneeId;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.assignmentId != null;

  @override
  void dispose() {
    _taskController.dispose();
    _assigneeNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    // Slots disponíveis do scale_type.
    final scaleTypes = ref.watch(allScaleTypesProvider).value ?? const [];
    final scaleType =
        scaleTypes.where((t) => t.id == widget.scaleTypeId).firstOrNull;
    final slots = scaleType?.slots ?? const <String>[];

    // Obreiros aprovados para selecionar o atribuído.
    final profiles = ref.watch(approvedProfilesProvider);

    // Mesma lista do antigo dropdown: o "—" na frente é a opção "sem obreiro
    // vinculado", usada quando o nome é digitado à mão logo abaixo.
    final assigneeIds = <String?>[null, ...profiles.map((p) => p.id)];
    final assigneeLabels = <String?, String>{
      null: '—',
      for (final p in profiles) p.id: p.fullName,
    };

    // Salvar mora no `trailing` da barra — ver a nota em
    // `announcement_editor_screen.dart` sobre por que o botão do fim saiu.
    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(_isEditing ? l.action_edit : l.scales_new_assignment),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator()
              : Text(l.action_save),
        ),
      ),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              CupertinoFormSection.insetGrouped(
                backgroundColor: colors.groupedBackground,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  _ValueRow(
                    label: l.scales_assignment_date,
                    value: _formatDate(_date),
                    onTap: _pickDate,
                  ),
                  if (slots.isNotEmpty)
                    _ValueRow(
                      label: l.scales_assignment_slot,
                      value: _slot ?? '—',
                      onTap: () => _pickSlot(slots),
                    ),
                  CupertinoTextFormFieldRow(
                    controller: _taskController,
                    placeholder: l.scales_assignment_task,
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
                // O `helperText` do campo Material vira o rodapé da seção: é
                // onde o iOS coloca a explicação de um grupo de células.
                // TODO l10n: scales_assignment_assignee_name_helper
                footer: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Use se a pessoa não tem conta no app',
                    style: AppTypography.footnote
                        .copyWith(color: colors.secondaryLabel),
                  ),
                ),
                children: [
                  // Seleção de obreiro: roda com os aprovados.
                  _ValueRow(
                    label: l.scales_assignment_assignee,
                    value: assigneeLabels[_assigneeId] ?? '—',
                    onTap: () => _pickAssignee(assigneeIds, assigneeLabels),
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _assigneeNameController,
                    placeholder: l.scales_assignment_assignee_name,
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
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _notesController,
                    placeholder: l.scales_assignment_notes,
                    maxLines: 3,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadExisting() async {
    final dao = ref.read(scalesDaoProvider);
    final row = await dao.getAssignment(widget.assignmentId!);
    if (row != null && mounted) {
      _taskController.text = row.task ?? '';
      _assigneeNameController.text = row.assigneeName ?? '';
      _notesController.text = row.notes ?? '';
      setState(() {
        _date = row.startsOn;
        _slot = row.slot;
        _assigneeId = row.assigneeId;
        _loaded = true;
      });
    }
  }

  /// Roda de data no lugar do `showDatePicker` — o calendário em grade é um
  /// padrão do Material; o iOS resolve datas com rolagem.
  ///
  /// A janela (1 ano atrás, 2 anos à frente) é a mesma de antes, e o valor só
  /// é aplicado se o usuário confirmar.
  Future<void> _pickDate() async {
    var picked = DateTime(_date.year, _date.month, _date.day);
    final confirmed = await _showPickerSheet(
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: _date,
        minimumDate: DateTime.now().subtract(const Duration(days: 365)),
        maximumDate: DateTime.now().add(const Duration(days: 365 * 2)),
        onDateTimeChanged: (v) => picked = v,
      ),
      height: 260,
    );
    if (confirmed && mounted) {
      setState(() => _date = picked);
    }
  }

  /// Slot do tipo de escala. Lista de itens preservada do dropdown original.
  Future<void> _pickSlot(List<String> slots) async {
    var selected = _slot ?? slots.first;
    final confirmed = await _showPickerSheet(
      child: CupertinoPicker(
        magnification: 1.1,
        squeeze: 1.2,
        itemExtent: 32,
        scrollController: FixedExtentScrollController(
          initialItem: _slot == null
              ? 0
              : slots.indexOf(_slot!).clamp(0, slots.length - 1),
        ),
        onSelectedItemChanged: (i) => selected = slots[i],
        children: [for (final s in slots) Center(child: Text(s))],
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _slot = selected);
  }

  /// Obreiro atribuído. O primeiro item continua sendo "nenhum" (`null`).
  Future<void> _pickAssignee(
    List<String?> ids,
    Map<String?, String> labels,
  ) async {
    var selected = _assigneeId;
    final confirmed = await _showPickerSheet(
      child: CupertinoPicker(
        magnification: 1.1,
        squeeze: 1.2,
        itemExtent: 32,
        scrollController: FixedExtentScrollController(
          initialItem: ids.indexOf(_assigneeId).clamp(0, ids.length - 1),
        ),
        onSelectedItemChanged: (i) => selected = ids[i],
        children: [
          for (final id in ids) Center(child: Text(labels[id] ?? '—')),
        ],
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _assigneeId = selected);
  }

  /// Folha modal padrão dos seletores: altura fixa, fundo de cartão e um botão
  /// de confirmar. Sem o confirmar, girar a roda já aplicaria o valor — o que
  /// torna impossível desistir da alteração.
  Future<bool> _showPickerSheet({
    required Widget child,
    double height = 260,
  }) async {
    final colors = context.colors;
    final l = AppLocalizations.of(context);

    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => Container(
        height: height,
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  // TODO l10n: action_done ("Pronto") — não existe no .arb,
                  // action_save é o rótulo mais próximo.
                  child: Text(l.action_save),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _save() async {
    // Valida: precisa de assigneeId OU assigneeName.
    if (_assigneeId == null &&
        _assigneeNameController.text.trim().isEmpty) {
      // TODO l10n: scales_assignment_assignee_required
      showAppToast(
        context,
        'Selecione um obreiro ou digite um nome.',
        isError: true,
      );
      return;
    }

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(scalesRepositoryProvider);

    try {
      if (_isEditing) {
        await repo.updateAssignment(
          id: widget.assignmentId!,
          scaleTypeId: widget.scaleTypeId,
          startsOn: _date,
          slot: _slot,
          task: _taskController.text.trim().isEmpty
              ? null
              : _taskController.text.trim(),
          assigneeId: _assigneeId,
          assigneeName: _assigneeNameController.text.trim().isEmpty
              ? null
              : _assigneeNameController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await repo.createAssignment(
          scaleTypeId: widget.scaleTypeId,
          startsOn: _date,
          slot: _slot,
          task: _taskController.text.trim().isEmpty
              ? null
              : _taskController.text.trim(),
          assigneeId: _assigneeId,
          assigneeName: _assigneeNameController.text.trim().isEmpty
              ? null
              : _assigneeNameController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }

      if (mounted) {
        showAppToast(context, l.scales_assignment_saved);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString(), isError: true);
        setState(() => _saving = false);
      }
    }
  }
}

/// Linha de formulário que mostra um valor e abre um seletor ao ser tocada.
///
/// Substitui o `ListTile` com `trailing: Icon(chevron_right)`: dentro de uma
/// `CupertinoFormSection` a célula precisa ser um `CupertinoFormRow`, senão os
/// separadores e o recuo do grupo não se aplicam.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CupertinoFormRow(
      prefix: Text(
        label,
        style: AppTypography.body.copyWith(color: colors.label),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTypography.body.copyWith(color: colors.secondaryLabel),
              ),
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
}
