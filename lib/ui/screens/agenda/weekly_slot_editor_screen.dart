import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/agenda_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/color_picker_row.dart';

/// Editor de slot do cronograma semanal — cria ou edita.
class WeeklySlotEditorScreen extends ConsumerStatefulWidget {
  const WeeklySlotEditorScreen({super.key, this.slotId});

  final String? slotId;

  @override
  ConsumerState<WeeklySlotEditorScreen> createState() =>
      _WeeklySlotEditorScreenState();
}

// ---------------------------------------------------------------------------
// _WeeklySlotEditorScreenState
// ---------------------------------------------------------------------------

class _WeeklySlotEditorScreenState
    extends ConsumerState<WeeklySlotEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _categoryController = TextEditingController();
  final _notesController = TextEditingController();
  /// Dias marcados. Na criação pode ter vários — é o que evita cadastrar
  /// sete vezes o mesmo horário de meditação. Na edição fica sempre com
  /// um: mudar os dias de um slot que já existe viraria duplicação
  /// silenciosa, e não é o que quem toca em "editar" está pedindo.
  Set<int> _weekdays = {1}; // 1=segunda ... 7=domingo

  // O horário passa a ser guardado em minutos desde a meia-noite, e não mais
  // em `TimeOfDay`: aquele tipo é do Material e some junto com o import. Como
  // o banco já grava minutos (`startsAtMinutes`), guardar minutos aqui elimina
  // uma conversão em vez de criar outra — o payload enviado é idêntico.
  int _startsAtMinutes = 19 * 60;
  int? _endsAtMinutes;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.slotId != null;


  /// Cor escolhida explicitamente. Nulo enquanto o usuário não mexeu.
  int? _colorIndex;

  /// Cor que o seletor exibe: a escolhida ou, na falta dela, a que a categoria
  /// já usa nos outros registros. Se a categoria for nova, cai na derivação
  /// pelo nome — que é o que a grade mostraria de qualquer forma.
  ///
  /// Sempre resolve para um índice concreto porque é isso que vai ser salvo:
  /// gravar nulo faria a grade recair na derivação por hash, que pode ser uma
  /// cor diferente da que o usuário acabou de ver na tela.
  int get _effectiveColorIndex {
    if (_colorIndex != null) return _colorIndex!;
    final category = _categoryController.text.trim();
    if (category.isEmpty) return 0;
    final known = ref.read(categoryColorsProvider)[category.toLowerCase()];
    return known ?? context.colors.defaultIndexFor(category);
  }

  /// Reavalia a sugestão a cada tecla, enquanto o usuário não escolheu cor.
  void _onCategoryChanged(String _) {
    if (_colorIndex == null) setState(() {});
  }

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
                    label: _isEditing
                        ? l.agenda_slot_weekday
                        : l.agenda_slot_weekdays,
                    value: _weekdaysLabel(weekdayLabels, l),
                    onTap: () => _isEditing
                        ? _pickWeekday(weekdayLabels)
                        : _pickWeekdays(weekdayLabels),
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
                  CupertinoTextFormFieldRow(
                    controller: _categoryController,
                    textAlign: TextAlign.end,
                    prefix: Text(
                      l.agenda_slot_category,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    style: AppTypography.body.copyWith(color: colors.label),
                    // Ao trocar de categoria, o seletor de cor acompanha a cor
                    // que aquela categoria já usa nos outros registros.
                    onChanged: _onCategoryChanged,
                  ),
                  ColorPickerRow(
                    value: _effectiveColorIndex,
                    onChanged: (i) => setState(() => _colorIndex = i),
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
        _weekdays = {row.weekday};
        _startsAtMinutes = row.startsAtMinutes;
        _endsAtMinutes = row.endsAtMinutes;
        // Nulo aqui é registro antigo, anterior à coluna de cor: o
        // seletor cai na sugestão pela categoria, que é a cor que a
        // grade já vinha mostrando para ele.
        _colorIndex = row.colorIndex;
        _loaded = true;
      });
    }
  }

  /// Texto da linha "dias da semana": "Seg, Qua, Sex", ou "Todos os dias"
  /// quando os sete estão marcados — sete siglas não cabem na linha do iOS.
  String _weekdaysLabel(Map<int, String> labels, AppLocalizations l) {
    if (_weekdays.isEmpty) return '—';
    if (_weekdays.length == 7) return l.agenda_slot_weekdays_all;
    final ordered = _weekdays.toList()..sort();
    return ordered.map((d) => labels[d] ?? '?').join(', ');
  }

  /// Seleção de vários dias, usada só na criação.
  ///
  /// Não é uma `CupertinoPicker`: roda serve para escolher **um** valor. Para
  /// marcar vários, o iOS usa uma lista com check — e a lista ainda cabe na
  /// mesma folha modal do resto da tela.
  ///
  /// O conjunto só é aplicado ao confirmar: mexer direto em `_weekdays` faria
  /// um cancelamento deixar as marcações alteradas.
  Future<void> _pickWeekdays(Map<int, String> labels) async {
    final colors = context.colors;
    final l = AppLocalizations.of(context);
    final selected = Set<int>.from(_weekdays);

    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          height: 380,
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    // Confirmar sem nada marcado deixaria a tela num estado
                    // que o save recusaria depois, sem dizer por quê.
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.of(sheetContext).pop(true),
                    child: Text(l.action_done),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in labels.entries)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          onPressed: () => setSheetState(() {
                            if (!selected.remove(entry.key)) {
                              selected.add(entry.key);
                            }
                          }),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.value,
                                  textAlign: TextAlign.start,
                                  style: AppTypography.body
                                      .copyWith(color: colors.label),
                                ),
                              ),
                              if (selected.contains(entry.key))
                                Icon(CupertinoIcons.check_mark,
                                    size: 20, color: colors.tint),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _weekdays = selected);
  }

  /// Dia da semana numa roda, no lugar do `DropdownButtonFormField`.
  ///
  /// O iOS não tem menu suspenso em formulário: a escolha entre poucas opções
  /// fixas é feita numa `CupertinoPicker` que sobe do rodapé. A lista de itens
  /// e o efeito do antigo `onChanged` (1..7, com fallback para 1) são os
  /// mesmos.
  Future<void> _pickWeekday(Map<int, String> labels) async {
    final values = labels.keys.toList();
    var selected = _weekdays.first;

    final confirmed = await _showPickerSheet(
      child: CupertinoPicker(
        magnification: 1.1,
        squeeze: 1.2,
        itemExtent: 32,
        scrollController: FixedExtentScrollController(
          initialItem:
              values.indexOf(_weekdays.first).clamp(0, values.length - 1),
        ),
        onSelectedItemChanged: (i) => selected = values[i],
        children: [
          for (final v in values)
            Center(child: Text(labels[v]!)),
        ],
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _weekdays = {selected});
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
                  child: Text(l.action_done),
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

    // O seletor já impede confirmar vazio; esta guarda cobre o resto dos
    // caminhos até aqui, e dá a mensagem em vez de gravar nada.
    if (_weekdays.isEmpty) {
      showAppToast(context, AppLocalizations.of(context).agenda_slot_weekdays_none,
          isError: true);
      return;
    }

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(agendaRepositoryProvider);

    final startsAtMinutes = _startsAtMinutes;
    final endsAtMinutes = _endsAtMinutes;

    try {
      if (_isEditing) {
        await repo.updateWeeklySlot(
          id: widget.slotId!,
          weekday: _weekdays.first,
          startsAtMinutes: startsAtMinutes,
          endsAtMinutes: endsAtMinutes,
          title: _titleController.text.trim(),
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
          colorIndex: _effectiveColorIndex,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await repo.createWeeklySlotsForWeekdays(
          weekdays: _weekdays,
          startsAtMinutes: startsAtMinutes,
          endsAtMinutes: endsAtMinutes,
          title: _titleController.text.trim(),
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
          colorIndex: _effectiveColorIndex,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }

      if (mounted) {
        showAppToast(
          context,
          _isEditing
              ? l.agenda_slot_saved
              : l.agenda_slots_saved(_weekdays.length),
        );
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

// ---------------------------------------------------------------------------
// _ValueRow
// ---------------------------------------------------------------------------

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
