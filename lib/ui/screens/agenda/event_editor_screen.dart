import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/category_picker_row.dart';

/// Editor de evento — cria ou edita.
class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, this.eventId});

  final String? eventId;

  @override
  ConsumerState<EventEditorScreen> createState() =>
      _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _categoryController = TextEditingController();
  DateTime _startsAt = DateTime.now().add(const Duration(hours: 1));
  DateTime? _endsAt;
  bool _allDay = false;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.eventId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    // Salvar mora no `trailing` da barra — ver a nota em
    // `announcement_editor_screen.dart` sobre por que o botão do fim saiu.
    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(_isEditing ? l.action_edit : l.agenda_new_event),
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
                  CupertinoTextFormFieldRow(
                    controller: _titleController,
                    textAlign: TextAlign.end,
                    prefix: Text(
                      l.agenda_event_title_label,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    style: AppTypography.body.copyWith(color: colors.label),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? l.agenda_event_title_label
                        : null,
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _descriptionController,
                    placeholder: l.agenda_event_description_label,
                    maxLines: 4,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                ],
              ),

              // Datas em seção própria: no iOS as linhas que abrem uma roda de
              // seleção ficam separadas dos campos de digitação.
              CupertinoFormSection.insetGrouped(
                backgroundColor: colors.groupedBackground,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  CupertinoFormRow(
                    prefix: Text(
                      l.agenda_event_all_day,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    child: CupertinoSwitch(
                      value: _allDay,
                      onChanged: (v) => setState(() => _allDay = v),
                    ),
                  ),
                  _ValueRow(
                    label: l.agenda_event_starts_at,
                    value: _formatDateTime(_startsAt),
                    onTap: () => _pickDateTime(isStart: true),
                  ),
                  if (!_allDay)
                    _ValueRow(
                      label: l.agenda_event_ends_at,
                      value: _endsAt != null ? _formatDateTime(_endsAt!) : '—',
                      onTap: () => _pickDateTime(isStart: false),
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
                      l.agenda_event_location,
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
    final row = await dao.getEvent(widget.eventId!);
    if (row != null && mounted) {
      _titleController.text = row.title;
      _descriptionController.text = row.description ?? '';
      _locationController.text = row.location ?? '';
      _categoryController.text = row.category ?? '';
      setState(() {
        _startsAt = row.startsAt;
        _endsAt = row.endsAt;
        _allDay = row.allDay;
        _loaded = true;
      });
    }
  }

  /// Abre a roda de data e, se o evento não for de dia inteiro, a de hora.
  ///
  /// O parâmetro `BuildContext` da versão Material saiu: as duas folhas usam o
  /// `context` do `State`, sempre precedido de `if (!mounted) return;`. Era
  /// exatamente para isso que existia o antigo `context: this.context` na
  /// segunda chamada (lint `use_build_context_synchronously`).
  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? _startsAt : (_endsAt ?? _startsAt);

    final date = await _showDateSheet(
      initial: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    if (_allDay) {
      setState(() {
        if (isStart) {
          _startsAt = date;
        } else {
          _endsAt = date;
        }
      });
      return;
    }

    if (!mounted) return;
    final time = await _showTimeSheet(initial: initial);
    if (time == null || !mounted) return;

    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startsAt = dt;
      } else {
        _endsAt = dt;
      }
    });
  }

  /// Roda de data numa folha modal — o `showDatePicker` (calendário Material)
  /// não existe no Cupertino.
  ///
  /// Só devolve valor se o usuário confirmar: a roda dispara `onDateTimeChanged`
  /// a cada giro, então sem o botão de confirmar um toque acidental já mudaria
  /// a data.
  Future<DateTime?> _showDateSheet({
    required DateTime initial,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    var picked = DateTime(initial.year, initial.month, initial.day);
    final confirmed = await _showPickerSheet(
      height: 260,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: initial,
        minimumDate: firstDate,
        maximumDate: lastDate,
        onDateTimeChanged: (v) => picked = v,
      ),
    );
    return confirmed ? picked : null;
  }

  /// Roda de hora. Devolve um `DateTime` do qual só interessam hora e minuto —
  /// o dia vem da roda de data, como no fluxo Material original.
  Future<DateTime?> _showTimeSheet({required DateTime initial}) async {
    var picked = initial;
    final confirmed = await _showPickerSheet(
      height: 260,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: initial,
        use24hFormat: true,
        onDateTimeChanged: (v) => picked = v,
      ),
    );
    return confirmed ? picked : null;
  }

  Future<bool> _showPickerSheet({
    required double height,
    required Widget child,
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

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    if (_allDay) {
      return '${d.day}/${d.month}/${d.year}';
    }
    return '${d.day}/${d.month}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(agendaRepositoryProvider);

    try {
      if (_isEditing) {
        await repo.updateEvent(
          id: widget.eventId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startsAt: _startsAt,
          endsAt: _endsAt,
          allDay: _allDay,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
        );
      } else {
        await repo.createEvent(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startsAt: _startsAt,
          endsAt: _endsAt,
          allDay: _allDay,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
        );
      }

      if (mounted) {
        showAppToast(context, l.agenda_event_saved);
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
