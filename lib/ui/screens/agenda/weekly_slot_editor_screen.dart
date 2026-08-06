import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/category_picker_row.dart';

/// Editor de slot do cronograma semanal — cria ou edita.
class WeeklySlotEditorScreen extends ConsumerStatefulWidget {
  const WeeklySlotEditorScreen({super.key, this.slotId});

  final String? slotId;

  @override
  ConsumerState<WeeklySlotEditorScreen> createState() =>
      _WeeklySlotEditorScreenState();
}

class _WeeklySlotEditorScreenState
    extends ConsumerState<WeeklySlotEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _categoryController = TextEditingController();
  final _notesController = TextEditingController();
  int _weekday = 1; // 1=segunda ... 7=domingo

  // O horário passa a ser guardado em minutos desde a meia-noite, e não mais
  // em `TimeOfDay`: aquele tipo é do Material e some junto com o import. Como
  // o banco já grava minutos (`startsAtMinutes`), guardar minutos aqui elimina
  // uma conversão em vez de criar outra — o payload enviado é idêntico.
  int _startsAtMinutes = 19 * 60;
  int? _endsAtMinutes;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.slotId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _categoryController.dispose();
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

    final weekdayLabels = <int, String>{
      1: l.agenda_weekday_mon,
      2: l.agenda_weekday_tue,
      3: l.agenda_weekday_wed,
      4: l.agenda_weekday_thu,
      5: l.agenda_weekday_fri,
      6: l.agenda_weekday_sat,
      7: l.agenda_weekday_sun,
    };

    // Salvar mora no `trailing` da barra — ver a nota em
    // `announcement_editor_screen.dart` sobre por que o botão do fim saiu.
    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(_isEditing ? l.action_edit : l.agenda_new_slot),
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
                    label: l.agenda_slot_weekday,
                    value: weekdayLabels[_weekday] ?? '—',
                    onTap: () => _pickWeekday(weekdayLabels),
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _titleController,
                    textAlign: TextAlign.end,
                    prefix: Text(
                      l.agenda_slot_title_label,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    style: AppTypography.body.copyWith(color: colors.label),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? l.agenda_slot_title_label
                        : null,
                  ),
                  _ValueRow(
                    label: l.agenda_slot_starts_at,
                    value: _formatMinutes(_startsAtMinutes),
                    onTap: () => _pickTime(isStart: true),
                  ),
                  _ValueRow(
                    label: l.agenda_slot_ends_at,
                    value: _endsAtMinutes != null
                        ? _formatMinutes(_endsAtMinutes!)
                        : '—',
                    onTap: () => _pickTime(isStart: false),
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
                    controller: _locationController,
                    textAlign: TextAlign.end,
                    prefix: Text(
                      l.agenda_slot_location,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  // A cor do bloco na agenda deriva da categoria, então
                  // escolher categoria é escolher cor — ver CategoryPickerRow.
                  CategoryPickerRow(
                    value: _categoryController.text,
                    onChanged: (v) =>
                        setState(() => _categoryController.text = v),
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _notesController,
                    placeholder: l.agenda_slot_notes,
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
    final dao = ref.read(agendaDaoProvider);
    final row = await dao.getWeeklySlot(widget.slotId!);
    if (row != null && mounted) {
      _titleController.text = row.title;
      _locationController.text = row.location ?? '';
      _categoryController.text = row.category ?? '';
      _notesController.text = row.notes ?? '';
      setState(() {
        _weekday = row.weekday;
        _startsAtMinutes = row.startsAtMinutes;
        _endsAtMinutes = row.endsAtMinutes;
        _loaded = true;
      });
    }
  }

  /// Dia da semana numa roda, no lugar do `DropdownButtonFormField`.
  ///
  /// O iOS não tem menu suspenso em formulário: a escolha entre poucas opções
  /// fixas é feita numa `CupertinoPicker` que sobe do rodapé. A lista de itens
  /// e o efeito do antigo `onChanged` (1..7, com fallback para 1) são os
  /// mesmos.
  Future<void> _pickWeekday(Map<int, String> labels) async {
    final values = labels.keys.toList();
    var selected = _weekday;

    final confirmed = await _showPickerSheet(
      child: CupertinoPicker(
        magnification: 1.1,
        squeeze: 1.2,
        itemExtent: 32,
        scrollController: FixedExtentScrollController(
          initialItem: values.indexOf(_weekday).clamp(0, values.length - 1),
        ),
        onSelectedItemChanged: (i) => selected = values[i],
        children: [
          for (final v in values)
            Center(child: Text(labels[v]!)),
        ],
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _weekday = selected);
  }

  /// Roda de hora no lugar do `showTimePicker`.
  ///
  /// A roda trabalha com `DateTime`, então a hora vai e volta convertida para
  /// minutos — que é como o slot é gravado. A data usada na conversão é
  /// descartável (só hora e minuto são lidos).
  Future<void> _pickTime({required bool isStart}) async {
    final initialMinutes =
        isStart ? _startsAtMinutes : (_endsAtMinutes ?? _startsAtMinutes);
    var picked = DateTime(
      2000,
      1,
      1,
      initialMinutes ~/ 60,
      initialMinutes % 60,
    );

    final confirmed = await _showPickerSheet(
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: picked,
        use24hFormat: true,
        onDateTimeChanged: (v) => picked = v,
      ),
    );
    if (!confirmed || !mounted) return;

    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (isStart) {
        _startsAtMinutes = minutes;
      } else {
        _endsAtMinutes = minutes;
      }
    });
  }

  /// Folha modal padrão dos seletores: altura fixa, fundo de cartão e um botão
  /// de confirmar. Sem o confirmar, girar a roda já aplicaria o valor — o que
  /// torna impossível desistir da alteração.
  Future<bool> _showPickerSheet({required Widget child}) async {
    final colors = context.colors;
    final l = AppLocalizations.of(context);

    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => Container(
        height: 260,
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

  String _formatMinutes(int minutes) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(agendaRepositoryProvider);

    final startsAtMinutes = _startsAtMinutes;
    final endsAtMinutes = _endsAtMinutes;

    try {
      if (_isEditing) {
        await repo.updateWeeklySlot(
          id: widget.slotId!,
          weekday: _weekday,
          startsAtMinutes: startsAtMinutes,
          endsAtMinutes: endsAtMinutes,
          title: _titleController.text.trim(),
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await repo.createWeeklySlot(
          weekday: _weekday,
          startsAtMinutes: startsAtMinutes,
          endsAtMinutes: endsAtMinutes,
          title: _titleController.text.trim(),
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }

      if (mounted) {
        showAppToast(context, l.agenda_slot_saved);
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
            Text(
              value,
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
}
